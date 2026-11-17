package main

import (
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"

	"github.com/egoist/mygo"
)

// Settings are the app's choices, kept as settings.json in the user data
// directory. Passwords are not here: the system's credential store keeps them
// (mygo.Secrets).
type settings struct {
	// Preset is the id of the accent preset, as in presets (theme.go).
	Preset string `json:"preset"`
	// DarkMode is darkSystem, darkLight or darkDark.
	DarkMode string `json:"dark_mode"`
	// RememberID is the student ID whose password the credential store keeps,
	// for signing in at launch. "" when nothing is remembered.
	RememberID string `json:"remember_id"`
}

const (
	darkSystem = "system"
	darkLight  = "light"
	darkDark   = "dark"

	// defaultPreset is 湖蓝, the Android app's default preset.
	defaultPreset = "lake"
)

func defaultSettings() settings {
	return settings{Preset: defaultPreset, DarkMode: darkSystem}
}

// loadSettings reads settings.json; a missing or unreadable file gives the
// defaults.
func loadSettings() settings {
	s := defaultSettings()
	if err := readJSON("settings.json", &s); err != nil {
		log.Printf("settings: %v", err)
		return defaultSettings()
	}
	return s
}

func (s settings) save() error { return writeJSON("settings.json", s) }

// readJSON decodes the file name of the user data directory into v. A missing
// file leaves v as it is.
func readJSON(name string, v any) error {
	path, err := userDataPath(name)
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

// writeJSON writes v to the file name of the user data directory. It writes a
// temporary file first, so a crash never leaves half a file behind.
func writeJSON(name string, v any) error {
	path, err := userDataPath(name)
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

func userDataPath(name string) (string, error) {
	dir, err := mygo.App.Path(mygo.PathUserData)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return filepath.Join(dir, name), nil
}
