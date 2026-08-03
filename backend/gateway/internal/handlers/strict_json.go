package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"reflect"
	"strings"
)

func decodeStrictJSON(raw json.RawMessage, target any) error {
	if err := rejectDuplicateJSONKeys(raw); err != nil {
		return err
	}
	if err := rejectNonCanonicalJSONFields(raw, reflect.TypeOf(target)); err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON value")
	}
	return nil
}

// encoding/json deliberately matches struct fields without regard to case.
// That convenience is unsafe for operator configuration and privacy schemas:
// `contract` plus `Contract` can otherwise assign the same field twice while
// evading an exact duplicate-key check. Validate the untyped JSON tree against
// the exact json-tag spelling before the ordinary typed decode.
func rejectNonCanonicalJSONFields(raw json.RawMessage, targetType reflect.Type) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return err
	}
	return validateCanonicalJSONFields(value, targetType)
}

func validateCanonicalJSONFields(value any, targetType reflect.Type) error {
	for targetType != nil && targetType.Kind() == reflect.Pointer {
		if value == nil {
			return nil
		}
		targetType = targetType.Elem()
	}
	if targetType == nil {
		return errors.New("strict JSON target has no schema")
	}

	switch targetType.Kind() {
	case reflect.Struct:
		object, ok := value.(map[string]any)
		if !ok {
			return nil // The typed decoder reports the shape/type error.
		}
		fields, err := canonicalJSONFields(targetType)
		if err != nil {
			return err
		}
		for key, child := range object {
			fieldType, found := fields[key]
			if !found {
				return fmt.Errorf("unknown or non-canonical JSON field %q", key)
			}
			if err := validateCanonicalJSONFields(child, fieldType); err != nil {
				return fmt.Errorf("field %q: %w", key, err)
			}
		}
	case reflect.Slice, reflect.Array:
		values, ok := value.([]any)
		if !ok {
			return nil
		}
		for i, child := range values {
			if err := validateCanonicalJSONFields(child, targetType.Elem()); err != nil {
				return fmt.Errorf("item %d: %w", i, err)
			}
		}
	case reflect.Map:
		object, ok := value.(map[string]any)
		if !ok || targetType.Key().Kind() != reflect.String {
			return nil
		}
		for key, child := range object {
			if err := validateCanonicalJSONFields(child, targetType.Elem()); err != nil {
				return fmt.Errorf("map value %q: %w", key, err)
			}
		}
	}
	return nil
}

func canonicalJSONFields(targetType reflect.Type) (map[string]reflect.Type, error) {
	fields := make(map[string]reflect.Type, targetType.NumField())
	for i := 0; i < targetType.NumField(); i++ {
		field := targetType.Field(i)
		if !field.IsExported() {
			continue
		}
		tag := field.Tag.Get("json")
		name, _, _ := strings.Cut(tag, ",")
		if name == "-" {
			continue
		}
		if field.Anonymous && name == "" {
			embeddedType := field.Type
			for embeddedType.Kind() == reflect.Pointer {
				embeddedType = embeddedType.Elem()
			}
			if embeddedType.Kind() == reflect.Struct {
				embedded, err := canonicalJSONFields(embeddedType)
				if err != nil {
					return nil, err
				}
				for embeddedName, embeddedFieldType := range embedded {
					if _, exists := fields[embeddedName]; exists {
						return nil, fmt.Errorf("ambiguous JSON schema field %q", embeddedName)
					}
					fields[embeddedName] = embeddedFieldType
				}
				continue
			}
		}
		if name == "" {
			name = field.Name
		}
		if _, exists := fields[name]; exists {
			return nil, fmt.Errorf("ambiguous JSON schema field %q", name)
		}
		fields[name] = field.Type
	}
	return fields, nil
}

func rejectDuplicateJSONKeys(raw json.RawMessage) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	var consumeValue func() error
	consumeValue = func() error {
		token, err := decoder.Token()
		if err != nil {
			return err
		}
		delim, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]struct{}{}
			for decoder.More() {
				keyToken, err := decoder.Token()
				if err != nil {
					return err
				}
				key, ok := keyToken.(string)
				if !ok {
					return errors.New("non-string JSON object key")
				}
				if _, duplicate := seen[key]; duplicate {
					return errors.New("duplicate JSON object key")
				}
				seen[key] = struct{}{}
				if err := consumeValue(); err != nil {
					return err
				}
			}
			end, err := decoder.Token()
			if err != nil {
				return err
			}
			if end != json.Delim('}') {
				return errors.New("unterminated JSON object")
			}
		case '[':
			for decoder.More() {
				if err := consumeValue(); err != nil {
					return err
				}
			}
			end, err := decoder.Token()
			if err != nil {
				return err
			}
			if end != json.Delim(']') {
				return errors.New("unterminated JSON array")
			}
		default:
			return errors.New("unexpected JSON delimiter")
		}
		return nil
	}
	if err := consumeValue(); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON value")
	}
	return nil
}
