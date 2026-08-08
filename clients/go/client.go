package ftnlclient

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	BaseURL string
	Token string
	HTTPClient *http.Client
}

func New(baseURL, token string) *Client {
	return &Client{BaseURL: strings.TrimRight(baseURL, "/"), Token: token, HTTPClient: &http.Client{Timeout: 30 * time.Second}}
}

func (c *Client) Request(ctx context.Context, method, path string, body any, out any) error {
	var payload io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil { return fmt.Errorf("encode request: %w", err) }
		payload = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+"/"+strings.TrimLeft(path, "/"), payload)
	if err != nil { return fmt.Errorf("build request: %w", err) }
	req.Header.Set("Accept", "application/json")
	if body != nil { req.Header.Set("Content-Type", "application/json") }
	if c.Token != "" { req.Header.Set("Authorization", "Bearer "+c.Token) }
	res, err := c.HTTPClient.Do(req)
	if err != nil { return fmt.Errorf("send request: %w", err) }
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		message, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
		return fmt.Errorf("File Tunnel API returned %s: %s", res.Status, strings.TrimSpace(string(message)))
	}
	if out == nil || res.StatusCode == http.StatusNoContent { return nil }
	if err := json.NewDecoder(res.Body).Decode(out); err != nil { return fmt.Errorf("decode response: %w", err) }
	return nil
}

func (c *Client) Health(ctx context.Context) (map[string]any, error) {
	var result map[string]any
	err := c.Request(ctx, http.MethodGet, "/health", nil, &result)
	return result, err
}
