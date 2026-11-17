package palette

import "math"

// Scheme is the Material 3 color roles of one preset, in one brightness.
type Scheme struct {
	Primary, OnPrimary, PrimaryContainer, OnPrimaryContainer, InversePrimary Color
	Secondary, OnSecondary, SecondaryContainer, OnSecondaryContainer         Color
	Tertiary, OnTertiary, TertiaryContainer, OnTertiaryContainer             Color
	Error, OnError, ErrorContainer, OnErrorContainer                         Color
	Background, OnBackground, Surface, OnSurface                             Color
	SurfaceVariant, OnSurfaceVariant, Outline, OutlineVariant                Color
	SurfaceDim, SurfaceBright                                                Color
	SurfaceContainerLowest, SurfaceContainerLow, SurfaceContainer            Color
	SurfaceContainerHigh, SurfaceContainerHighest                            Color
	InverseSurface, InverseOnSurface                                         Color
}

// NewAndroidScheme is the scheme of a preset given by its HCT hue and chroma,
// in the light or the dark brightness. It is the Android app's
// schemeFromPreset (ui/theme/Theme.kt), tone for tone, so the desktop app
// shows the colors the phone app shows.
func NewAndroidScheme(hue, chroma float64, dark bool) Scheme {
	primary := NewTonalPalette(hue, chroma)
	secondary := NewTonalPalette(hue+3, math.Min(13, chroma*0.6))
	tertiary := NewTonalPalette(hue+50, math.Min(22, chroma*0.8))
	neutral := NewTonalPalette(hue+3, 4.5)
	neutralVariant := NewTonalPalette(hue+4, 8)
	errorP := NewTonalPalette(25, 84)

	// pick is the tone of p in the light or the dark brightness.
	pick := func(p TonalPalette, light, darkTone int) Color {
		if dark {
			return p.Tone(darkTone)
		}
		return p.Tone(light)
	}
	return Scheme{
		Primary:                 pick(primary, 40, 80),
		OnPrimary:               pick(primary, 100, 20),
		PrimaryContainer:        pick(primary, 90, 30),
		OnPrimaryContainer:      pick(primary, 10, 90),
		InversePrimary:          pick(primary, 80, 40),
		Secondary:               pick(secondary, 40, 80),
		OnSecondary:             pick(secondary, 100, 20),
		SecondaryContainer:      pick(secondary, 90, 30),
		OnSecondaryContainer:    pick(secondary, 10, 90),
		Tertiary:                pick(tertiary, 40, 80),
		OnTertiary:              pick(tertiary, 100, 20),
		TertiaryContainer:       pick(tertiary, 90, 30),
		OnTertiaryContainer:     pick(tertiary, 10, 90),
		Error:                   pick(errorP, 40, 80),
		OnError:                 pick(errorP, 100, 20),
		ErrorContainer:          pick(errorP, 90, 30),
		OnErrorContainer:        pick(errorP, 10, 90),
		Background:              pick(neutral, 99, 6),
		OnBackground:            pick(neutral, 10, 90),
		Surface:                 pick(neutral, 99, 6),
		OnSurface:               pick(neutral, 10, 90),
		SurfaceVariant:          pick(neutralVariant, 90, 30),
		OnSurfaceVariant:        pick(neutralVariant, 30, 80),
		Outline:                 pick(neutralVariant, 50, 60),
		OutlineVariant:          pick(neutralVariant, 80, 30),
		SurfaceDim:              pick(neutral, 87, 6),
		SurfaceBright:           pick(neutral, 99, 24),
		SurfaceContainerLowest:  pick(neutral, 100, 4),
		SurfaceContainerLow:     pick(neutral, 96, 10),
		SurfaceContainer:        pick(neutral, 93, 12),
		SurfaceContainerHigh:    pick(neutral, 91, 17),
		SurfaceContainerHighest: pick(neutral, 88, 22),
		InverseSurface:          pick(neutral, 20, 90),
		InverseOnSurface:        pick(neutral, 95, 20),
	}
}
