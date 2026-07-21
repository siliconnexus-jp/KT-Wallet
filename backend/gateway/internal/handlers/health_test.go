package handlers_test

import "testing"

func TestHealthGolden(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", nil)
	assertJSONEq(t, `{"ok":true,"version":"9.9.9-test"}`, result(t, resp))
}

func TestHealthIgnoresParams(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", `{"anything":"goes"}`)
	if result(t, resp)["ok"] != true {
		t.Fatal("kt_health must succeed regardless of params")
	}
}
