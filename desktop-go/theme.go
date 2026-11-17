package main

import (
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// preset is an accent of the app, defined by the HCT hue and chroma the
// Android app defines it by (ThemePresets.kt).
type preset struct {
	id, name    string
	hue, chroma float64
}

// presets are the Android app's presets, in the order its settings show them.
var presets = []preset{
	{"pine", "松青", 155, 24},
	{"satin_purple", "缎紫", 275, 28},
	{"cherry", "樱红", 355, 30},
	{"apricot", "杏黄", 75, 32},
	{"lake", "湖蓝", 212.6, 26.8},
	{"ink", "黛墨", 240, 9},
}

// presetByID is the preset with the id, or the default preset for an unknown id.
func presetByID(id string) preset {
	var def preset
	for _, p := range presets {
		if p.id == id {
			return p
		}
		if p.id == defaultPreset {
			def = p
		}
	}
	return def
}

// schemes caches the schemes of the presets: the palette solves each color by
// search, too slow for every frame. The view runs on the main thread, so the
// map needs no lock.
var schemes = map[schemeKey]palette.Scheme{}

type schemeKey struct {
	preset preset
	dark   bool
}

func schemeOf(p preset, dark bool) palette.Scheme {
	k := schemeKey{p, dark}
	s, ok := schemes[k]
	if !ok {
		s = palette.NewAndroidScheme(p.hue, p.chroma, dark)
		schemes[k] = s
	}
	return s
}

// extended is the success and warning roles, which the palette has no names for.
// The Android app takes them from fixed hues, not from the preset
// (ExtendedColors.kt), so they do not change with the accent.
type extended struct {
	success, onSuccess, successContainer, onSuccessContainer ui.Color
	warning, onWarning, warningContainer, onWarningContainer ui.Color
}

var extendedCache = map[bool]extended{}

// extendedOf is the success and warning roles in the brightness. The tones are
// the scheme's: 40/100/90/10 in the light, 80/20/30/90 in the dark.
func extendedOf(dark bool) extended {
	if x, ok := extendedCache[dark]; ok {
		return x
	}
	success := palette.NewTonalPalette(145, 32)
	warning := palette.NewTonalPalette(70, 40)
	pick := func(p palette.TonalPalette, light, darkTone int) ui.Color {
		if dark {
			return uiColor(p.Tone(darkTone))
		}
		return uiColor(p.Tone(light))
	}
	x := extended{
		success:            pick(success, 40, 80),
		onSuccess:          pick(success, 100, 20),
		successContainer:   pick(success, 90, 30),
		onSuccessContainer: pick(success, 10, 90),
		warning:            pick(warning, 40, 80),
		onWarning:          pick(warning, 100, 20),
		warningContainer:   pick(warning, 90, 30),
		onWarningContainer: pick(warning, 10, 90),
	}
	extendedCache[dark] = x
	return x
}

// appearance is the scheme and the brightness the frame shows. It must run
// before the frame's SetTheme: following the system reads the system's theme,
// which SetTheme replaces.
func (a *app) appearance(c *ui.Context) (palette.Scheme, bool) {
	dark := a.isDark(c)
	return schemeOf(presetByID(a.settings.Preset), dark), dark
}

// isDark reports whether the app shows the dark appearance.
func (a *app) isDark(c *ui.Context) bool {
	switch a.settings.DarkMode {
	case darkLight:
		return false
	case darkDark:
		return true
	default:
		return c.Theme().Dark
	}
}

// themeOf is the app's theme for a scheme in the chosen brightness: the
// Material 3 roles of the chosen preset.
func themeOf(c *ui.Context, s palette.Scheme, dark bool) *ui.Theme {
	base := ui.LightTheme()
	if dark {
		base = ui.DarkTheme()
	}
	// The desktop's own asks, as high contrast and text scale, carry over.
	t := base.WithPreferences(c.Preferences()).WithAccent(uiColor(s.Primary))
	t.AccentText = uiColor(s.OnPrimary)
	t.Background = uiColor(s.Background)
	// Cards sit one step above the background, so they show in both appearances.
	t.Surface = uiColor(s.SurfaceContainer)
	t.SurfaceHover = uiColor(s.SurfaceContainerHigh)
	t.SurfacePressed = uiColor(s.SurfaceContainerHighest)
	t.Text = uiColor(s.OnSurface)
	t.TextMuted = uiColor(s.OnSurfaceVariant)
	t.Border = uiColor(s.Outline)
	t.Danger = uiColor(s.Error)
	t.Font = "MiSans"
	t.Radius = 16
	return t
}

func uiColor(c palette.Color) ui.Color { return ui.Hex(c.Hex()) }
