package ftnlclient

import "testing"

func TestNewNormalizesBaseURL(t *testing.T) {
	client := New("https://example.test///", "")
	if client.BaseURL != "https://example.test" { t.Fatalf("unexpected base URL: %q", client.BaseURL) }
}
