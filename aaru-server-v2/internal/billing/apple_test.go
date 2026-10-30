package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"math/big"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// testAppleChain is a chain shaped like Apple's (root, intermediate and leaf, with Apple's
// marker extensions), made here so signed data verifies end to end without Apple's keys.
type testAppleChain struct {
	root    *x509.Certificate
	x5c     []string
	leafKey *ecdsa.PrivateKey
}

func newTestAppleChain(t *testing.T, markers bool) testAppleChain {
	t.Helper()
	now := time.Now()
	key := func() *ecdsa.PrivateKey {
		k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		require.NoError(t, err)
		return k
	}
	rootKey, middleKey, leafKey := key(), key(), key()
	marker := func(oid []int) []pkix.Extension {
		if !markers {
			return nil
		}
		return []pkix.Extension{{Id: oid, Value: []byte{0x05, 0x00}}}
	}
	template := func(name string, ca bool, ext []pkix.Extension) *x509.Certificate {
		serial, _ := rand.Int(rand.Reader, big.NewInt(1<<62))
		c := &x509.Certificate{
			SerialNumber: serial, Subject: pkix.Name{CommonName: name},
			NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), ExtraExtensions: ext,
		}
		if ca {
			c.IsCA, c.BasicConstraintsValid, c.KeyUsage = true, true, x509.KeyUsageCertSign
		}
		return c
	}
	issue := func(tmpl, parent *x509.Certificate, pub *ecdsa.PublicKey, signer *ecdsa.PrivateKey) *x509.Certificate {
		der, err := x509.CreateCertificate(rand.Reader, tmpl, parent, pub, signer)
		require.NoError(t, err)
		cert, err := x509.ParseCertificate(der)
		require.NoError(t, err)
		return cert
	}
	rootTmpl := template("Test Root", true, nil)
	root := issue(rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)
	middle := issue(template("Test Intermediate", true, marker(oidAppleIntermediate)), root, &middleKey.PublicKey, rootKey)
	leaf := issue(template("Test Leaf", false, marker(oidAppleLeaf)), middle, &leafKey.PublicKey, middleKey)
	var x5c []string
	for _, c := range []*x509.Certificate{leaf, middle, root} {
		x5c = append(x5c, base64.StdEncoding.EncodeToString(c.Raw))
	}
	return testAppleChain{root: root, x5c: x5c, leafKey: leafKey}
}

func (c testAppleChain) sign(t *testing.T, payload any) string {
	t.Helper()
	header, err := json.Marshal(map[string]any{"alg": "ES256", "x5c": c.x5c})
	require.NoError(t, err)
	body, err := json.Marshal(payload)
	require.NoError(t, err)
	enc := base64.RawURLEncoding
	message := enc.EncodeToString(header) + "." + enc.EncodeToString(body)
	digest := sha256.Sum256([]byte(message))
	r, s, err := ecdsa.Sign(rand.Reader, c.leafKey, digest[:])
	require.NoError(t, err)
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return message + "." + enc.EncodeToString(sig)
}

const testBundle = "com.fernandocorreia.aaru.beta"

func payload(original string, token *uuid.UUID, bundle string) map[string]any {
	p := map[string]any{
		"originalTransactionId": original, "transactionId": original + "1", "bundleId": bundle,
		"productId": "aaru_plus_monthly", "environment": "Sandbox",
		"expiresDate": time.Now().Add(30 * 24 * time.Hour).UnixMilli(), "signedDate": time.Now().UnixMilli(),
	}
	if token != nil {
		p["appAccountToken"] = token.String()
	}
	return p
}

func TestTransactionVerifiesUpAnAppleShapedChainOnly(t *testing.T) {
	chain := newTestAppleChain(t, true)
	apple, err := NewAppleSignedData([]string{testBundle}, chain.root)
	require.NoError(t, err)
	token := uuid.New()
	jws := chain.sign(t, payload("2000000001", &token, testBundle))
	tx, err := apple.Transaction(jws)
	require.NoError(t, err)
	assert.Equal(t, "2000000001", tx.OriginalTransactionID)
	assert.Equal(t, &token, tx.AppAccountToken)
	assert.Equal(t, "aaru_plus_monthly", tx.ProductID)
	assert.NotNil(t, tx.ExpiresAt)

	// Another bundle's purchase, a payload changed after signing, a chain without Apple's
	// markers, and a chain from another root.
	_, err = apple.Transaction(chain.sign(t, payload("1", &token, "com.example.other")))
	require.ErrorIs(t, err, ErrWrongBundle)
	parts := strings.Split(jws, ".")
	forged := strings.Split(chain.sign(t, payload("999", &token, testBundle)), ".")
	_, err = apple.Transaction(parts[0] + "." + forged[1] + "." + parts[2])
	require.ErrorIs(t, err, ErrInvalid)
	unmarked := newTestAppleChain(t, false)
	lenient, err := NewAppleSignedData([]string{testBundle}, unmarked.root)
	require.NoError(t, err)
	_, err = lenient.Transaction(unmarked.sign(t, payload("1", &token, testBundle)))
	require.ErrorIs(t, err, ErrInvalid)
	production, err := NewAppleSignedData([]string{testBundle})
	require.NoError(t, err)
	_, err = production.Transaction(jws)
	require.ErrorIs(t, err, ErrInvalid)

	// A payload signed when the chain was not yet valid does not verify.
	old := payload("2", &token, testBundle)
	old["signedDate"] = time.Now().Add(-48 * time.Hour).UnixMilli()
	_, err = apple.Transaction(chain.sign(t, old))
	require.ErrorIs(t, err, ErrInvalid)
	_, err = apple.Transaction("garbage")
	require.ErrorIs(t, err, ErrInvalid)
}

func TestNotificationVerifiesItsTransaction(t *testing.T) {
	chain := newTestAppleChain(t, true)
	apple, err := NewAppleSignedData([]string{testBundle}, chain.root)
	require.NoError(t, err)
	token := uuid.New()
	inner := chain.sign(t, payload("3000", &token, testBundle))
	n, err := apple.Notification(chain.sign(t, map[string]any{
		"notificationType": "DID_RENEW", "signedDate": time.Now().UnixMilli(),
		"data": map[string]any{"bundleId": testBundle, "signedTransactionInfo": inner},
	}))
	require.NoError(t, err)
	assert.Equal(t, "DID_RENEW", n.Type)
	require.NotNil(t, n.Transaction)
	assert.Equal(t, "3000", n.Transaction.OriginalTransactionID)

	test, err := apple.Notification(chain.sign(t, map[string]any{"notificationType": "TEST", "signedDate": time.Now().UnixMilli()}))
	require.NoError(t, err)
	assert.Nil(t, test.Transaction)

	_, err = apple.Notification(chain.sign(t, map[string]any{
		"notificationType": "SUBSCRIBED", "signedDate": time.Now().UnixMilli(), "data": map[string]any{"bundleId": "com.example.other"},
	}))
	require.ErrorIs(t, err, ErrWrongBundle)
}

func TestAppleRootIsTheOneBundled(t *testing.T) {
	root, err := x509.ParseCertificate(AppleRootG3)
	require.NoError(t, err)
	assert.Equal(t, "Apple Root CA - G3", root.Subject.CommonName)
	sum := sha256.Sum256(AppleRootG3)
	assert.Equal(t, "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179", strings.ToUpper(hex.EncodeToString(sum[:])))
}
