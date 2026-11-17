package design

import (
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// DefaultPreset is the id of 湖蓝, the Android app's default preset: the one an unknown id
// falls back to.
const DefaultPreset = "lake"

// Preset is an accent of the app, defined by the HCT hue and chroma the
// Android app defines it by (ThemePresets.kt).
type Preset struct {
	ID, Name    string
	Hue, Chroma float64
}

// Presets are the Android app's Presets, in the order its settings show them.
var Presets = []Preset{
	{"pine", "松青", 155, 24},
	{"satin_purple", "缎紫", 275, 28},
	{"cherry", "樱红", 355, 30},
	{"apricot", "杏黄", 75, 32},
	{"lake", "湖蓝", 212.6, 26.8},
	{"ink", "黛墨", 240, 9},
}

// PresetByID is the preset with the id, or the default preset for an unknown id.
func PresetByID(id string) Preset {
	var def Preset
	for _, p := range Presets {
		if p.ID == id {
			return p
		}
		if p.ID == DefaultPreset {
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
	preset Preset
	dark   bool
}

func SchemeOf(p Preset, dark bool) palette.Scheme {
	k := schemeKey{p, dark}
	s, ok := schemes[k]
	if !ok {
		s = palette.NewAndroidScheme(p.Hue, p.Chroma, dark)
		schemes[k] = s
	}
	return s
}

// Extended is the success and warning roles, which the palette has no names for.
// The Android app takes them from fixed hues, not from the preset
// (ExtendedColors.kt), so they do not change with the accent.
type Extended struct {
	Success, OnSuccess, SuccessContainer, OnSuccessContainer ui.Color
	Warning, OnWarning, WarningContainer, OnWarningContainer ui.Color
}

var extendedCache = map[bool]Extended{}

// ExtendedOf is the success and warning roles in the brightness. The tones are
// the scheme's: 40/100/90/10 in the light, 80/20/30/90 in the dark.
func ExtendedOf(dark bool) Extended {
	if x, ok := extendedCache[dark]; ok {
		return x
	}
	success := palette.NewTonalPalette(145, 32)
	warning := palette.NewTonalPalette(70, 40)
	pick := func(p palette.TonalPalette, light, darkTone int) ui.Color {
		if dark {
			return UIColor(p.Tone(darkTone))
		}
		return UIColor(p.Tone(light))
	}
	x := Extended{
		Success:            pick(success, 40, 80),
		OnSuccess:          pick(success, 100, 20),
		SuccessContainer:   pick(success, 90, 30),
		OnSuccessContainer: pick(success, 10, 90),
		Warning:            pick(warning, 40, 80),
		OnWarning:          pick(warning, 100, 20),
		WarningContainer:   pick(warning, 90, 30),
		OnWarningContainer: pick(warning, 10, 90),
	}
	extendedCache[dark] = x
	return x
}

// ThemeOf is the app's theme for a scheme in the chosen brightness: the
// Material 3 roles of the chosen preset.
func ThemeOf(c *ui.Context, s palette.Scheme, dark bool) *ui.Theme {
	base := ui.LightTheme()
	if dark {
		base = ui.DarkTheme()
	}
	// The desktop's own asks, as high contrast and text scale, carry over.
	t := base.WithPreferences(c.Preferences()).WithAccent(UIColor(s.Primary))
	t.AccentText = UIColor(s.OnPrimary)
	t.Background = UIColor(s.Background)
	// Cards sit one step above the background, so they show in both appearances.
	t.Surface = UIColor(s.SurfaceContainer)
	t.SurfaceHover = UIColor(s.SurfaceContainerHigh)
	t.SurfacePressed = UIColor(s.SurfaceContainerHighest)
	t.Text = UIColor(s.OnSurface)
	t.TextMuted = UIColor(s.OnSurfaceVariant)
	t.Border = UIColor(s.Outline)
	t.Danger = UIColor(s.Error)
	t.Font = "MiSans"
	t.Radius = 16
	return t
}

func UIColor(c palette.Color) ui.Color { return ui.Hex(c.Hex()) }
