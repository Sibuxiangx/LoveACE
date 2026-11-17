// Package userdata reads and writes the small JSON files the app keeps in its user data
// directory: settings, the login cooldowns and the smart page's course offerings.
package userdata

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"github.com/egoist/mygo"
)

// ReadJSON decodes the file name of the user data directory into v. A missing file
// leaves v as it is.
func ReadJSON(name string, v any) error {
	path, err := path(name)
	if err != nil {
		return err
	}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// WriteJSON writes v to the file name of the user data directory. It writes a temporary
// file first, so a crash never leaves half a file behind.
func WriteJSON(name string, v any) error {
	path, err := path(name)
	if err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func path(name string) (string, error) {
	dir, err := mygo.App.Path(mygo.PathUserData)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return filepath.Join(dir, name), nil
}
