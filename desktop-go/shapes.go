package main

import (
	"math"

	"github.com/egoist/mygo/ui"
)

// cookie is a lobed outline, the cookie shape of Material 3 Expressive: a
// circle whose radius swings lobe DIPs around radius, lobes times.
func cookie(cx, cy, radius, lobe float32, lobes int) *ui.Path {
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

// ribbonShape is a scallop of the Material 3 Expressive set, as the Android
// app's RibbonShape: r = r0 * (1 + amp*cos(lobes*θ)).
type ribbonShape struct {
	lobes int
	amp   float64
}

var (
	cookie8 = ribbonShape{lobes: 8, amp: 0.065}
	clover4 = ribbonShape{lobes: 4, amp: 0.16}
	flower5 = ribbonShape{lobes: 5, amp: 0.11}
)

// scallop outlines the shape morphing from `from` to `to`, k = 0 for from and
// 1 for to. Both are sampled at the same 240 angles from the top, so the
// morph is continuous and needs no crossfade.
func scallop(cx, cy, radius float32, from, to ribbonShape, k float64) *ui.Path {
	p := &ui.Path{}
	const steps = 240
	for i := range steps + 1 {
		th := 2 * math.Pi * float64(i) / steps
		rFrom := float64(radius) * (1 + from.amp*math.Cos(float64(from.lobes)*th)) / (1 + from.amp)
		rTo := float64(radius) * (1 + to.amp*math.Cos(float64(to.lobes)*th)) / (1 + to.amp)
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
