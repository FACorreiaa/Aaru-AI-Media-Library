package auth

import (
	"aaru-go-api/internal/apperr"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// MagicLinkSending sends the sign-in email: the link and its 6-digit code.
type MagicLinkSending interface {
	Send(ctx context.Context, email, link, code string) error
}

// ResendEndpoint is Resend's `POST /emails`.
const ResendEndpoint = "https://api.resend.com/emails"

// ResendSender sends the sign-in link through Resend.
type ResendSender struct {
	Client   *http.Client
	Endpoint string
	APIKey   string
	From     string
}

// NewResendSender sends from `from` with RESEND_API_KEY.
func NewResendSender(client *http.Client, apiKey, from string) *ResendSender {
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	return &ResendSender{Client: client, Endpoint: ResendEndpoint, APIKey: apiKey, From: from}
}

type resendEmail struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	Text    string   `json:"text"`
}

var errEmailNotSent = apperr.New(http.StatusBadGateway, "email_unavailable", "The sign-in email could not be sent.")

// Send implements MagicLinkSending.
func (s *ResendSender) Send(ctx context.Context, email, link, code string) error {
	spaced := code
	if len(code) >= 3 {
		spaced = code[:3] + " " + code[len(code)-3:]
	}
	payload, err := json.Marshal(resendEmail{
		From:    s.From,
		To:      []string{email},
		Subject: "Your Aaru sign-in code: " + spaced,
		Text: "Your Aaru sign-in code is " + spaced + "\n\nOr open this link:\n\n" + link +
			"\n\nEither works once and expires in 15 minutes. If you did not ask for it, ignore this email.",
	})
	if err != nil {
		return fmt.Errorf("resend payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.Endpoint, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("resend request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+s.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.Client.Do(req)
	if err != nil {
		return errEmailNotSent
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return errEmailNotSent
	}
	return nil
}
