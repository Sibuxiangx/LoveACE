package palette

// TonalPalette is the colors of one hue and chroma at every tone, from 0
// (black) to 100 (white). Material's schemes take their roles from these.
type TonalPalette struct {
	hue, chroma float64
}

// NewTonalPalette is the palette of a hue and a chroma, as Material's
// TonalPalette.fromHueAndChroma.
func NewTonalPalette(hue, chroma float64) TonalPalette {
	return TonalPalette{hue: hue, chroma: chroma}
}

// Tone is the color of the palette at a tone, 0 to 100.
func (p TonalPalette) Tone(tone int) Color {
	// Yellow hues at tone 99 use the average of tones 98 and 100, as
	// material-color-utilities does.
	if tone == 99 && isYellow(p.hue) {
		return averageArgb(p.Tone(98), p.Tone(100))
	}
	return HctFrom(p.hue, p.chroma, float64(tone)).Argb()
}

func averageArgb(a, b Color) Color {
	r := jsRound(float64(a>>16&0xff+b>>16&0xff) / 2)
	g := jsRound(float64(a>>8&0xff+b>>8&0xff) / 2)
	bl := jsRound(float64(a&0xff+b&0xff) / 2)
	return RGB(int(r), int(g), int(bl))
}
