package provider

import (
	"encoding/json"
	"fmt"
)

// JSONValue is any JSON value, decoded with numbers as float64: MCP tool arguments
// differ per tool, and Stremio request bodies are ad hoc. Nil is JSON null.
type JSONValue = any

// EncodeJSONValue is v as a JSONValue, after a round trip through encoding/json
// (dates as the `/v1` routes send them when v uses apitime.Time).
func EncodeJSONValue(v any) (JSONValue, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return nil, fmt.Errorf("encode json value: %w", err)
	}
	var out JSONValue
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("decode json value: %w", err)
	}
	return out, nil
}

// DecodeJSONValue reads value as a typed input.
func DecodeJSONValue[T any](value JSONValue) (T, error) {
	var out T
	data, err := json.Marshal(value)
	if err != nil {
		return out, fmt.Errorf("encode json value: %w", err)
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return out, fmt.Errorf("decode json value: %w", err)
	}
	return out, nil
}

// JSONObject is value as an object, or nil.
func JSONObject(value JSONValue) map[string]any {
	m, _ := value.(map[string]any)
	return m
}

// JSONString is value as a string, and whether it was one.
func JSONString(value JSONValue) (string, bool) {
	s, ok := value.(string)
	return s, ok
}
