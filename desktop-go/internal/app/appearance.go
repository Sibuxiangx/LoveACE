package app

import (
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-desktop/internal/settings"
	"github.com/egoist/mygo/ui"
)

// appearance is the scheme and the brightness the frame shows. It must run before the
// frame's SetTheme: following the system reads the system's theme, which SetTheme replaces.
func (a *app) appearance(c *ui.Context) (palette.Scheme, bool) {
	dark := a.isDark(c)
	return design.SchemeOf(design.PresetByID(a.set.Preset), dark), dark
}

// isDark reports whether the app shows the dark appearance.
func (a *app) isDark(c *ui.Context) bool {
	switch a.set.DarkMode {
	case settings.DarkLight:
		return false
	case settings.DarkDark:
		return true
	default:
		return c.Theme().Dark
	}
}
