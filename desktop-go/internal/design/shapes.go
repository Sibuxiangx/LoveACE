package design

import (
	"math"

	"github.com/egoist/mygo/ui"
)

// Cookie is a lobed outline, the Cookie shape of Material 3 Expressive: a
// circle whose radius swings lobe DIPs around radius, lobes times.
func Cookie(cx, cy, radius, lobe float32, lobes int) *ui.Path {
	p := &ui.Path{}
	const steps = 240
	for i := range steps + 1 {
		th := 2 * math.Pi * float64(i) / steps
		r := float64(radius) + float64(lobe)*math.Cos(float64(lobes)*th)
		x := cx + float32(r*math.Cos(th))
		y := cy + float32(r*math.Sin(th))
		if i == 0 {
			p.MoveTo(x, y)
		} else {
			p.LineTo(x, y)
		}
	}
	return p
}

// RibbonShape is a scallop of the Material 3 Expressive set, as the Android
// app's RibbonShape: r = r0 * (1 + amp*cos(lobes*θ)).
type RibbonShape struct {
	Lobes int
	Amp   float64
}

var (
	Cookie8 = RibbonShape{Lobes: 8, Amp: 0.065}
	Clover4 = RibbonShape{Lobes: 4, Amp: 0.16}
	Flower5 = RibbonShape{Lobes: 5, Amp: 0.11}
)

// Scallop outlines the shape morphing from `from` to `to`, k = 0 for from and
// 1 for to. Both are sampled at the same 240 angles from the top, so the
// morph is continuous and needs no crossfade.
func Scallop(cx, cy, radius float32, from, to RibbonShape, k float64) *ui.Path {
	p := &ui.Path{}
	const steps = 240
	for i := range steps + 1 {
		th := 2 * math.Pi * float64(i) / steps
		rFrom := float64(radius) * (1 + from.Amp*math.Cos(float64(from.Lobes)*th)) / (1 + from.Amp)
		rTo := float64(radius) * (1 + to.Amp*math.Cos(float64(to.Lobes)*th)) / (1 + to.Amp)
		r := rFrom + (rTo-rFrom)*k
		x := cx + float32(r*math.Sin(th))
		y := cy - float32(r*math.Cos(th))
		if i == 0 {
			p.MoveTo(x, y)
		} else {
			p.LineTo(x, y)
		}
	}
	return p
}
