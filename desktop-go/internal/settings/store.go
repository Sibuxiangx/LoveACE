package settings

import (
	"log"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
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
	if err := userdata.ReadJSON("settings.json", &s); err != nil {
		log.Printf("settings: %v", err)
		return Default()
	}
	return s
}

// Save writes settings.json.
func (s Settings) Save() error { return userdata.WriteJSON("settings.json", s) }

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
