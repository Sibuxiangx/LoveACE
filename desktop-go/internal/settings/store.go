package settings

import (
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/egoist/mygo"
)

// Settings are the app's choices, kept as settings.json in the user data
// directory. Passwords are not here: the system's credential store keeps them
// (account.SavePassword).
type Settings struct {
	// Preset is the id of the accent preset, as in design.Presets.
	Preset string `json:"preset"`
	// DarkMode is DarkSystem, DarkLight or DarkDark.
	DarkMode string `json:"dark_mode"`
	// RememberID is the student ID whose password the credential store keeps,
	// for signing in at launch. "" when nothing is remembered.
	RememberID string `json:"remember_id"`
}

const (
	DarkSystem = "system"
	DarkLight  = "light"
	DarkDark   = "dark"
)

// Default is the settings of a first launch.
func Default() Settings {
	return Settings{Preset: design.DefaultPreset, DarkMode: DarkSystem}
}

// Load reads settings.json; a missing or unreadable file gives the defaults.
func Load() Settings {
	s := Default()
	if err := readJSON("settings.json", &s); err != nil {
		log.Printf("settings: %v", err)
		return Default()
	}
	return s
}

// Save writes settings.json.
func (s Settings) Save() error { return writeJSON("settings.json", s) }

// Persist saves s. A failure is logged; the in-memory settings still apply for
// this run.
func (s Settings) Persist() {
	if err := s.Save(); err != nil {
		log.Printf("settings: %v", err)
	}
}

// DropRemembered forgets the remembered account's password and ID. The caller
// persists the settings.
func (s *Settings) DropRemembered() {
	if s.RememberID == "" {
		return
	}
	if err := account.ForgetPassword(s.RememberID); err != nil {
		log.Printf("credentials: forget: %v", err)
	}
	s.RememberID = ""
}

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
