// Package billing is Aaru Plus (BIL-001…003): App Store subscriptions the server verifies and
// keeps. The port of Sources/App/Billing and PostgresEntitlementStore.swift.
package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Transaction is one signed App Store transaction (`JWSTransactionDecodedPayload`), the fields Aaru reads.
type Transaction struct {
	OriginalTransactionID string
	TransactionID         string
	BundleID              string
	ProductID             string
	Environment           string
	// AppAccountToken is the UUID the app set at purchase: the buyer's Aaru user id.
	AppAccountToken *uuid.UUID
	ExpiresAt       *time.Time
	RevokedAt       *time.Time
	SignedAt        time.Time
}

// Notification is one App Store Server Notification v2 (`ResponseBodyV2DecodedPayload`).
type Notification struct {
	Type     string
	Subtype  *string
	BundleID *string
	// Transaction is the one it concerns, already verified; nil for one without (TEST).
	Transaction *Transaction
}

// AppleVerifier verifies Apple's signed data: the chain up to Apple's root, then the signature.
type AppleVerifier interface {
	Transaction(jws string) (Transaction, error)
	Notification(jws string) (Notification, error)
}

// Verification errors.
var (
	ErrInvalid     = errors.New("billing: the signed data did not verify")
	ErrWrongBundle = errors.New("billing: the signed data is for another app")
)

// Apple's marker extensions on the leaf and the intermediate.
var (
	oidAppleLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// AppleSignedData is BIL-002: App Store signed data, checked the way Apple's server library
// does it with online checks off. The `x5c` chain must end at Apple Root CA - G3, carry Apple's
// marker extensions (leaf 1.2.840.113635.100.6.11.1, intermediate 1.2.840.113635.100.6.2.1), and
// be valid when Apple signed the payload; the JWS must verify with the leaf's key; the bundle id
// must be one of Aaru's.
type AppleSignedData struct {
	roots     *x509.CertPool
	bundleIDs map[string]bool
}

// NewAppleSignedData trusts Apple Root CA - G3, or roots when given (tests).
func NewAppleSignedData(bundleIDs []string, roots ...*x509.Certificate) (*AppleSignedData, error) {
	pool := x509.NewCertPool()
	if len(roots) == 0 {
		root, err := x509.ParseCertificate(AppleRootG3)
		if err != nil {
			return nil, err
		}
		roots = []*x509.Certificate{root}
	}
	for _, r := range roots {
		pool.AddCert(r)
	}
	ids := make(map[string]bool, len(bundleIDs))
	for _, id := range bundleIDs {
		ids[id] = true
	}
	return &AppleSignedData{roots: pool, bundleIDs: ids}, nil
}

type transactionPayload struct {
	OriginalTransactionID *string `json:"originalTransactionId"`
	TransactionID         *string `json:"transactionId"`
	BundleID              *string `json:"bundleId"`
	ProductID             *string `json:"productId"`
	Environment           *string `json:"environment"`
	AppAccountToken       *string `json:"appAccountToken"`
	ExpiresDate           *int64  `json:"expiresDate"`
	RevocationDate        *int64  `json:"revocationDate"`
	SignedDate            *int64  `json:"signedDate"`
}

type notificationPayload struct {
	NotificationType *string `json:"notificationType"`
	Subtype          *string `json:"subtype"`
	Data             *struct {
		BundleID              *string `json:"bundleId"`
		Environment           *string `json:"environment"`
		SignedTransactionInfo *string `json:"signedTransactionInfo"`
	} `json:"data"`
	SignedDate *int64 `json:"signedDate"`
}

// Apple's dates are milliseconds since 1970.
func millis(ms int64) time.Time { return time.UnixMilli(ms) }

func millisPtr(ms *int64) *time.Time {
	if ms == nil {
		return nil
	}
	t := millis(*ms)
	return &t
}

// Transaction verifies a signed transaction.
func (a *AppleSignedData) Transaction(jws string) (Transaction, error) {
	var p transactionPayload
	if err := a.verify(jws, &p, func() *int64 { return p.SignedDate }); err != nil {
		return Transaction{}, err
	}
	if p.OriginalTransactionID == nil || p.TransactionID == nil || p.BundleID == nil || p.ProductID == nil || p.Environment == nil {
		return Transaction{}, ErrInvalid
	}
	if !a.bundleIDs[*p.BundleID] {
		return Transaction{}, ErrWrongBundle
	}
	t := Transaction{
		OriginalTransactionID: *p.OriginalTransactionID, TransactionID: *p.TransactionID, BundleID: *p.BundleID,
		ProductID: *p.ProductID, Environment: *p.Environment,
		ExpiresAt: millisPtr(p.ExpiresDate), RevokedAt: millisPtr(p.RevocationDate), SignedAt: millis(*p.SignedDate),
	}
	if p.AppAccountToken != nil && len(*p.AppAccountToken) == 36 {
		if id, err := uuid.Parse(*p.AppAccountToken); err == nil {
			t.AppAccountToken = &id
		}
	}
	return t, nil
}

// Notification verifies an App Store Server Notification and the transaction inside it.
func (a *AppleSignedData) Notification(jws string) (Notification, error) {
	var p notificationPayload
	if err := a.verify(jws, &p, func() *int64 { return p.SignedDate }); err != nil {
		return Notification{}, err
	}
	if p.NotificationType == nil {
		return Notification{}, ErrInvalid
	}
	n := Notification{Type: *p.NotificationType, Subtype: p.Subtype}
	if p.Data != nil {
		n.BundleID = p.Data.BundleID
		if p.Data.BundleID != nil && !a.bundleIDs[*p.Data.BundleID] {
			return Notification{}, ErrWrongBundle
		}
		if p.Data.SignedTransactionInfo != nil {
			t, err := a.Transaction(*p.Data.SignedTransactionInfo)
			if err != nil {
				return Notification{}, err
			}
			n.Transaction = &t
		}
	}
	return n, nil
}

// verify checks the x5c chain at the payload's signed date, Apple's markers, and the ES256
// signature, then leaves the payload decoded in out. Every failure is ErrInvalid.
func (a *AppleSignedData) verify(jws string, out any, signedDate func() *int64) error {
	parts := strings.Split(jws, ".")
	if len(parts) != 3 {
		return ErrInvalid
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return ErrInvalid
	}
	var header struct {
		Alg string   `json:"alg"`
		X5C []string `json:"x5c"`
	}
	if json.Unmarshal(headerJSON, &header) != nil || header.Alg != "ES256" || len(header.X5C) == 0 {
		return ErrInvalid
	}
	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ErrInvalid
	}
	if json.Unmarshal(payloadJSON, out) != nil {
		return ErrInvalid
	}
	signed := signedDate()
	if signed == nil {
		return ErrInvalid
	}
	certs := make([]*x509.Certificate, 0, len(header.X5C))
	for _, c := range header.X5C {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return ErrInvalid
		}
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			return ErrInvalid
		}
		certs = append(certs, cert)
	}
	intermediates := x509.NewCertPool()
	for _, c := range certs[1:] {
		intermediates.AddCert(c)
	}
	chains, err := certs[0].Verify(x509.VerifyOptions{
		Roots: a.roots, Intermediates: intermediates, CurrentTime: millis(*signed),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	})
	if err != nil || !meetsApplePolicy(chains) {
		return ErrInvalid
	}
	key, ok := certs[0].PublicKey.(*ecdsa.PublicKey)
	if !ok || key.Curve != elliptic.P256() {
		return ErrInvalid
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return ErrInvalid
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(key, digest[:], r, s) {
		return ErrInvalid
	}
	return nil
}

// meetsApplePolicy: leaf, intermediate and root, with Apple's markers on the first two.
func meetsApplePolicy(chains [][]*x509.Certificate) bool {
	for _, chain := range chains {
		if len(chain) == 3 && hasExtension(chain[0], oidAppleLeaf) && hasExtension(chain[1], oidAppleIntermediate) {
			return true
		}
	}
	return false
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}

// AppleRootG3 is Apple Root CA - G3 (DER), from apple.com/certificateauthority. SHA-256
// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79.
var AppleRootG3 = func() []byte {
	der, err := base64.StdEncoding.DecodeString("" +
		"MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQL" +
		"DB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMw" +
		"MTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRp" +
		"ZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA" +
		"BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqX" +
		"l5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8w" +
		"DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWT" +
		"xnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==")
	if err != nil {
		panic(err)
	}
	return der
}()
