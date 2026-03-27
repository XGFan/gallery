package main

import (
	"errors"
	"gallery/config"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"testing"

	"github.com/gin-gonic/gin"
)

func withLoadConfigStubs(t *testing.T, locate func(path string) ([]byte, error), unmarshal func(in []byte, out interface{}) error) {
	t.Helper()
	originalLocateAndRead := locateAndRead
	originalUnmarshalYAML := unmarshalYAML
	locateAndRead = locate
	unmarshalYAML = unmarshal
	t.Cleanup(func() {
		locateAndRead = originalLocateAndRead
		unmarshalYAML = originalUnmarshalYAML
	})
}

func TestLoadConfig_FileMissingFallsBackWithoutMutation(t *testing.T) {
	conf := &config.GalleryConfig{Port: 9090}
	withLoadConfigStubs(t,
		func(path string) ([]byte, error) {
			if path != "gallery.yaml" {
				t.Fatalf("expected gallery.yaml path, got %q", path)
			}
			return nil, os.ErrNotExist
		},
		func(in []byte, out interface{}) error {
			t.Fatal("unmarshal should not be called for locate error")
			return nil
		},
	)

	loadConfig(conf)

	if conf.Port != 9090 {
		t.Fatalf("expected config unchanged on fallback, got port=%d", conf.Port)
	}
}

func TestLoadConfig_ParseFailureFallsBackWithoutMutation(t *testing.T) {
	conf := &config.GalleryConfig{Port: 7777}
	withLoadConfigStubs(t,
		func(path string) ([]byte, error) {
			return []byte("invalid"), nil
		},
		func(in []byte, out interface{}) error {
			return errors.New("bad yaml")
		},
	)

	loadConfig(conf)

	if conf.Port != 7777 {
		t.Fatalf("expected config unchanged on parse fallback, got port=%d", conf.Port)
	}
}

func TestCorsMiddleware_OPTIONSShortCircuitsWithHeaders(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(corsMiddleware())
	r.Any("/api/test", func(c *gin.Context) {
		c.Status(http.StatusTeapot)
	})

	req, err := http.NewRequest(http.MethodOptions, "/api/test", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)

	if resp.Code != http.StatusNoContent {
		t.Fatalf("expected status 204 for OPTIONS short-circuit, got %d", resp.Code)
	}
	if got := resp.Header().Get("Server"); got != "SAIO" {
		t.Fatalf("expected Server header SAIO, got %q", got)
	}
	if got := resp.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected Access-Control-Allow-Origin *, got %q", got)
	}
	if got := resp.Header().Get("Access-Control-Allow-Methods"); got != "GET, POST, OPTIONS" {
		t.Fatalf("expected Access-Control-Allow-Methods header, got %q", got)
	}
	if got := resp.Header().Get("Access-Control-Allow-Headers"); got != "Origin, Content-Type" {
		t.Fatalf("expected Access-Control-Allow-Headers header, got %q", got)
	}
}

func TestCorsMiddleware_NonOPTIONSContinuesToHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(corsMiddleware())
	r.GET("/api/test", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req, err := http.NewRequest(http.MethodGet, "/api/test", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)

	if resp.Code != http.StatusOK {
		t.Fatalf("expected status 200 for GET passthrough, got %d", resp.Code)
	}
	if got := resp.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected Access-Control-Allow-Origin *, got %q", got)
	}
}

func TestBrowserCommand_SelectsCommandByOS(t *testing.T) {
	url := "http://localhost:8080/"
	tests := []struct {
		name        string
		goos        string
		wantCommand string
		wantArgs    []string
		wantOK      bool
	}{
		{
			name:        "linux",
			goos:        "linux",
			wantCommand: "xdg-open",
			wantArgs:    []string{url},
			wantOK:      true,
		},
		{
			name:        "windows",
			goos:        "windows",
			wantCommand: "rundll32",
			wantArgs:    []string{"url.dll,FileProtocolHandler", url},
			wantOK:      true,
		},
		{
			name:        "darwin",
			goos:        "darwin",
			wantCommand: "open",
			wantArgs:    []string{url},
			wantOK:      true,
		},
		{
			name:        "unknown os",
			goos:        "plan9",
			wantCommand: "",
			wantArgs:    nil,
			wantOK:      false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gotCommand, gotArgs, gotOK := browserCommand(tc.goos, url)
			if gotOK != tc.wantOK {
				t.Fatalf("expected ok=%v, got %v", tc.wantOK, gotOK)
			}
			if gotCommand != tc.wantCommand {
				t.Fatalf("expected command %q, got %q", tc.wantCommand, gotCommand)
			}
			if !reflect.DeepEqual(gotArgs, tc.wantArgs) {
				t.Fatalf("expected args %v, got %v", tc.wantArgs, gotArgs)
			}
		})
	}
}
