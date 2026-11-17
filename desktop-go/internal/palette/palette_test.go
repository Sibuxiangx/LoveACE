package palette

import (
	"encoding/json"
	"math"
	"os"
	"strconv"
	"strings"
	"testing"
)

// The references are generated under Bun from material-color-utilities'
// TypeScript: testdata/reference.json holds the core palettes of 8 seeds, and
// testdata/android_lake.json holds the Android app's schemeFromPreset for the
// lake preset. The port must match them.

type referenceSeed struct {
	HCT   [3]float64 `json:"hct"`
	A1    []string   `json:"a1"`
	A2    []string   `json:"a2"`
	A3    []string   `json:"a3"`
	N1    []string   `json:"n1"`
	N2    []string   `json:"n2"`
	Error []string   `json:"error"`
}

// referenceTones are the tones the reference was written at, in its order.
var referenceTones = []int{0, 4, 6, 10, 12, 17, 20, 22, 24, 30, 40, 50, 60, 70, 80, 87, 90, 92, 94, 95, 96, 98, 99, 100}

func loadReference(t *testing.T) map[string]referenceSeed {
	t.Helper()
	data, err := os.ReadFile("testdata/reference.json")
	if err != nil {
		t.Fatal(err)
	}
	var ref map[string]referenceSeed
	if err := json.Unmarshal(data, &ref); err != nil {
		t.Fatal(err)
	}
	return ref
}

func parseHex(t *testing.T, s string) Color {
	t.Helper()
	v, err := strconv.ParseUint(strings.TrimPrefix(s, "#"), 16, 32)
	if err != nil {
		t.Fatal(err)
	}
	return Color(0xff000000 | uint32(v))
}

// corePalettes are the six palettes of a seed in material-color-utilities'
// CorePalette, the TonalSpot rules the reference was generated with.
func corePalettes(seed Color) []TonalPalette {
	hct := HctFromArgb(seed)
	hue, chroma := hct.Hue, hct.Chroma
	return []TonalPalette{
		NewTonalPalette(hue, math.Max(48, chroma)),
		NewTonalPalette(hue, 16),
		NewTonalPalette(hue+60, 24),
		NewTonalPalette(hue, 4),
		NewTonalPalette(hue, 8),
		NewTonalPalette(25, 84),
	}
}

func TestHCTMatchesReference(t *testing.T) {
	for seed, want := range loadReference(t) {
		got := HctFromArgb(parseHex(t, seed))
		for i, v := range []float64{got.Hue, got.Chroma, got.Tone} {
			if math.Abs(v-want.HCT[i]) > 1e-6 {
				t.Errorf("%s hct[%d] = %v, reference %v", seed, i, v, want.HCT[i])
			}
		}
	}
}

func TestTonalPalettesMatchReference(t *testing.T) {
	names := []string{"a1", "a2", "a3", "n1", "n2", "error"}
	for seed, ref := range loadReference(t) {
		want := [][]string{ref.A1, ref.A2, ref.A3, ref.N1, ref.N2, ref.Error}
		for i, p := range corePalettes(parseHex(t, seed)) {
			for j, tone := range referenceTones {
				if got := p.Tone(tone).Hex(); got != want[i][j] {
					t.Errorf("%s %s tone %d = %s, reference %s", seed, names[i], tone, got, want[i][j])
				}
			}
		}
	}
}

type androidPreset struct {
	Seed  string            `json:"seed"`
	Light map[string]string `json:"light"`
	Dark  map[string]string `json:"dark"`
}

// lake is ThemePresets.LAKE in the Android app.
const lakeHue, lakeChroma = 212.6, 26.8

// roleColors names every role of a scheme as the Android reference does.
func roleColors(s Scheme) map[string]Color {
	return map[string]Color{
		"primary": s.Primary, "onPrimary": s.OnPrimary,
		"primaryContainer": s.PrimaryContainer, "onPrimaryContainer": s.OnPrimaryContainer,
		"inversePrimary": s.InversePrimary,
		"secondary":      s.Secondary, "onSecondary": s.OnSecondary,
		"secondaryContainer": s.SecondaryContainer, "onSecondaryContainer": s.OnSecondaryContainer,
		"tertiary": s.Tertiary, "onTertiary": s.OnTertiary,
		"tertiaryContainer": s.TertiaryContainer, "onTertiaryContainer": s.OnTertiaryContainer,
		"error": s.Error, "onError": s.OnError,
		"errorContainer": s.ErrorContainer, "onErrorContainer": s.OnErrorContainer,
		"background": s.Background, "onBackground": s.OnBackground,
		"surface": s.Surface, "onSurface": s.OnSurface,
		"surfaceVariant": s.SurfaceVariant, "onSurfaceVariant": s.OnSurfaceVariant,
		"outline": s.Outline, "outlineVariant": s.OutlineVariant,
		"surfaceDim": s.SurfaceDim, "surfaceBright": s.SurfaceBright,
		"surfaceContainerLowest": s.SurfaceContainerLowest, "surfaceContainerLow": s.SurfaceContainerLow,
		"surfaceContainer": s.SurfaceContainer, "surfaceContainerHigh": s.SurfaceContainerHigh,
		"surfaceContainerHighest": s.SurfaceContainerHighest,
		"inverseSurface":          s.InverseSurface, "inverseOnSurface": s.InverseOnSurface,
	}
}

func TestAndroidLakeSchemeMatchesReference(t *testing.T) {
	data, err := os.ReadFile("testdata/android_lake.json")
	if err != nil {
		t.Fatal(err)
	}
	var ref map[string]androidPreset
	if err := json.Unmarshal(data, &ref); err != nil {
		t.Fatal(err)
	}
	lake := ref["lake"]
	for _, dark := range []bool{false, true} {
		want := lake.Light
		if dark {
			want = lake.Dark
		}
		got := roleColors(NewAndroidScheme(lakeHue, lakeChroma, dark))
		if len(got) != len(want) {
			t.Fatalf("dark=%v: %d roles, reference %d", dark, len(got), len(want))
		}
		for role, wantHex := range want {
			if got[role].Hex() != wantHex {
				t.Errorf("dark=%v %s = %s, reference %s", dark, role, got[role].Hex(), wantHex)
			}
		}
	}
	if seed := NewAndroidScheme(lakeHue, lakeChroma, false).Primary.Hex(); seed != lake.Seed {
		t.Errorf("default accent = %s, reference %s", seed, lake.Seed)
	}
}
