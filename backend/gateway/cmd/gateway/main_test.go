package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidateMetricsBearerToken(t *testing.T) {
	t.Parallel()

	if got, err := validateMetricsBearerToken(""); err != nil || got != "" {
		t.Fatalf("empty token = %q, %v", got, err)
	}
	valid := strings.Repeat("a", 32)
	if got, err := validateMetricsBearerToken("  " + valid + "  "); err != nil || got != valid {
		t.Fatalf("valid token = %q, %v", got, err)
	}
	if _, err := validateMetricsBearerToken(strings.Repeat("a", 31)); err == nil {
		t.Fatal("short token accepted")
	}
}

func TestMetricsHandlerRequiresBearer(t *testing.T) {
	t.Parallel()

	token := strings.Repeat("d", 32)
	handler := metricsHandler(func() string { return "kt_gateway_info 1\n" }, token)

	for _, tt := range []struct {
		name   string
		header string
		status int
		body   string
	}{
		{name: "missing", status: http.StatusNotFound},
		{name: "wrong", header: "Bearer " + strings.Repeat("e", 32), status: http.StatusNotFound},
		{name: "valid", header: "Bearer " + token, status: http.StatusOK, body: "kt_gateway_info 1\n"},
	} {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, req)
			if recorder.Code != tt.status {
				t.Fatalf("status = %d, want %d", recorder.Code, tt.status)
			}
			if tt.body != "" && recorder.Body.String() != tt.body {
				t.Fatalf("body = %q, want %q", recorder.Body.String(), tt.body)
			}
		})
	}
}

func TestHasValidMetricsBearer(t *testing.T) {
	t.Parallel()

	token := strings.Repeat("b", 32)
	tests := []struct {
		name   string
		server string
		header string
		want   bool
	}{
		{name: "disabled", header: "Bearer " + token},
		{name: "missing", server: token},
		{name: "wrong scheme", server: token, header: "Basic " + token},
		{name: "wrong value", server: token, header: "Bearer " + strings.Repeat("c", 32)},
		{name: "valid", server: token, header: "Bearer " + token, want: true},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequest("GET", "/metrics", nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}
			if got := hasValidMetricsBearer(req, tt.server); got != tt.want {
				t.Fatalf("hasValidMetricsBearer() = %v, want %v", got, tt.want)
			}
		})
	}
}
