package main

import (
	"math"
	"time"

	"github.com/egoist/mygo/ui"
)

// The components of the pages that mygo does not have: Material 3 Expressive's
// scallop badges, the gauge ring, the wavy and pill bars, the card heads and
// chips every page shares, and the rows of a list. DESIGN.md says where each
// one goes.

// The rhythm of a page. Every card has one radius and one padding, and cards are
// set apart by cardGap in both directions.
const (
	cardRadius = 28 // a card
	tileRadius = 16 // a tile inside a card, and a row's highlight
	cardPad    = 20 // a card's padding
	cardGap    = 16 // between cards, and between the parts of a large card
)

// cookie12 is the twelve-lobed cookie of Material 3 Expressive, the shape of
// the app's identity and of the vacation.
var cookie12 = ribbonShape{lobes: 12, amp: 0.05}

// shapeBadge is an icon inside a scallop, as the Android app's ShapeBadge. The
// icon fills half the badge; a nil icon leaves the scallop alone.
func shapeBadge(c *ui.Context, shape ribbonShape, size float32, fill ui.Color, icon *ui.SVG, tint ui.Color) {
	ui.Box(c).Size(size, size).Draw(func(p *ui.Painter, r ui.Rect) {
		cx, cy := r.X+r.W/2, r.Y+r.H/2
		radius := min(r.W, r.H) / 2 * 47 / 50
		p.FillPath(scallop(cx, cy, radius, shape, shape, 0), fill)
		if icon != nil {
			s := r.W / 2
			p.Icon(icon, ui.Rect{X: cx - s/2, Y: cy - s/2, W: s, H: s}, tint)
		}
	})
}

// drawGauge paints a ring that fills clockwise from the top to value (0 to 1)
// inside r: the GPA gauge and the graduation requirements. The rest of the ring
// is the track.
func drawGauge(p *ui.Painter, r ui.Rect, width float32, value float64, fill, track ui.Color) {
	cx, cy := r.X+r.W/2, r.Y+r.H/2
	radius := min(r.W, r.H)/2 - width/2
	p.StrokePath((&ui.Path{}).Circle(cx, cy, radius), width, track)
	if value <= 0 {
		return
	}
	const steps = 120
	sweep := 2 * math.Pi * math.Min(value, 1)
	arc := &ui.Path{}
	for i := 0; i <= steps; i++ {
		th := -math.Pi/2 + sweep*float64(i)/steps
		x := cx + radius*float32(math.Cos(th))
		y := cy + radius*float32(math.Sin(th))
		if i == 0 {
			arc.MoveTo(x, y)
		} else {
			arc.LineTo(x, y)
		}
	}
	p.StrokePath(arc, width, fill)
}

// wavyBar is a progress bar whose done part waves, as Material 3 Expressive's
// wavy indicator. The wave moves while the frame asks for it, and holds still
// when the system asks for less motion. The track is the part the wave has not
// reached, so the two never share a span.
func wavyBar(c *ui.Context, value float64, fill, track ui.Color) {
	const (
		stroke     = 4
		amp        = 3
		wavelength = 26
		period     = 2.4 // seconds per cycle of the wave
	)
	box := ui.Box(c).Height(16).FillWidth()
	start := ui.Local(box, "start", func() time.Time { return c.Now() })
	phase := 0.0
	if !c.Preferences().ReduceMotion {
		phase = 2 * math.Pi * math.Mod(c.Now().Sub(*start).Seconds(), period) / period
		c.After(time.Second / 30)
	}
	v := float32(math.Min(math.Max(value, 0), 1))
	box.Draw(func(p *ui.Painter, r ui.Rect) {
		y := r.Y + r.H/2
		end := r.X + v*r.W
		// A gap keeps the wave's round end off the track.
		const gap = 8
		trackFrom := r.X
		if v > 0 {
			trackFrom = end + gap
		}
		if trackFrom < r.X+r.W {
			p.StrokePolyline([][2]float32{{trackFrom, y}, {r.X + r.W, y}}, stroke, track)
		}
		if v <= 0 {
			return
		}
		var pts [][2]float32
		for x := r.X; ; x += 2 {
			if x > end {
				x = end
			}
			dy := amp * math.Sin(2*math.Pi*float64(x-r.X)/wavelength-phase)
			pts = append(pts, [2]float32{x, y + float32(dy)})
			if x >= end {
				break
			}
		}
		p.StrokePolyline(pts, stroke, fill)
	})
}

// pillBar is a straight progress bar with round ends. It fills the width its
// column gives it.
func pillBar(c *ui.Context, height float32, value float64, fill, track ui.Color) {
	v := float32(math.Min(math.Max(value, 0), 1))
	ui.Box(c).Height(height).FillWidth().Draw(func(p *ui.Painter, r ui.Rect) {
		p.Fill(r, track, r.H/2)
		if v > 0 {
			p.Fill(ui.Rect{X: r.X, Y: r.Y, W: r.W * v, H: r.H}, fill, r.H/2)
		}
	})
}

// surface is a rounded container of color fill that holds body. It takes the
// height of its content: the settings sections use it inside a scrolling column.
func surface(c *ui.Context, fill ui.Color, radius, pad float32, body func()) {
	ui.Column(c).Background(fill).Radius(radius).Padding(pad).Gap(12).Children(body)
}

// cardHeader is the head of a card: its badge, its title in fg, and whatever
// trailing draws at the end of the row. A nil trailing draws nothing there.
func cardHeader(c *ui.Context, badge rowBadge, title string, fg ui.Color, trailing func()) {
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
		shapeBadge(c, badge.shape, 36, badge.fill, badge.icon, badge.tint)
		ui.Text(c, title).FontSize(16).Bold().TextColor(fg)
		ui.Spacer(c)
		if trailing != nil {
			trailing()
		}
	})
}

// chip is a short label on a full-rounded pill, with an optional icon. It keeps
// the width of its text: it sits in a row, which a stretching column does not
// stretch.
func chip(c *ui.Context, text string, icon *ui.SVG, fill, fg ui.Color) {
	ui.Row(c).Children(func() {
		ui.Row(c).Background(fill).Radius(999).Padding(4, 12).Gap(6).AlignItems(ui.Center).Children(func() {
			if icon != nil {
				ui.Icon(c, icon).FontSize(14).TextColor(fg)
			}
			ui.Text(c, text).FontSize(12).Bold().TextColor(fg)
		})
	})
}

// rowBadge is the badge at the start of a card head or a list row.
type rowBadge struct {
	shape      ribbonShape
	icon       *ui.SVG
	fill, tint ui.Color
}

// listRow is a row of a list: a badge, a title, a caption, and whatever
// trailing draws at its end. With onClick the row is a button.
func listRow(c *ui.Context, t *ui.Theme, key string, badge rowBadge, title, caption string, trailing func(), onClick func()) {
	body := func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(14).Children(func() {
			shapeBadge(c, badge.shape, 44, badge.fill, badge.icon, badge.tint)
			ui.Column(c).Grow(1).Gap(2).Children(func() {
				ui.Text(c, title).FontSize(14).Bold().TextColor(t.Text)
				if caption != "" {
					ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
				}
			})
			if trailing != nil {
				trailing()
			}
		})
	}
	if onClick == nil {
		body()
		return
	}
	btn := ui.ButtonBase(c.Key(key)).FillWidth().Radius(20).Padding(8, 10)
	if btn.Hovered() {
		btn.Background(t.SurfaceHover)
	}
	btn.Children(body)
	if btn.Clicked() {
		onClick()
	}
}

// pillButton is a full-rounded action with an icon and a label.
func pillButton(c *ui.Context, key string, icon *ui.SVG, label string, fill, fg ui.Color, onClick func()) {
	btn := ui.ButtonBase(c.Key(key)).Radius(999).Padding(10, 16)
	btn.Background(fill)
	btn.Children(func() {
		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Icon(c, icon).FontSize(18).TextColor(fg)
			ui.Text(c, label).FontSize(14).Bold().TextColor(fg)
		})
	})
	if btn.Clicked() {
		onClick()
	}
}

// sectionTitle is the caption that heads a group of cards.
func sectionTitle(c *ui.Context, t *ui.Theme, text string) {
	ui.Text(c, text).FontSize(13).Bold().TextColor(t.TextMuted)
}

// dragStrip is the top of a page that drags the window. The title bar is
// hidden, so the strip is the room it leaves: the full width of its column, as
// tall as the title bar. Controls never go on it.
func dragStrip(c *ui.Context) {
	ui.Box(c).FillWidth().Height(titleBarHeight).Shrink(0).DragWindow()
}

// iconButton is a round control with an icon, lit while the pointer is on it.
func iconButton(c *ui.Context, t *ui.Theme, icon *ui.SVG, label string, onClick func()) {
	button := ui.ButtonBase(c)
	fill := t.Surface
	if button.Hovered() {
		fill = t.SurfaceHover
	}
	button.Size(40, 40).Radius(20).Background(fill).Label(label).Tooltip(label).
		Justify(ui.Center).AlignItems(ui.Center).OnClick(onClick).Children(func() {
		ui.Icon(c, icon).FontSize(22).TextColor(t.Text)
	})
}

// shapeLoader is the loading indicator of every read: the M3E shape loader of
// the Android app. A cookie-8 morphs through clover-4 and flower-5 back to
// cookie-8 every 3.6 s, turning once a cycle and breathing twice in it. It is
// drawn in fill, the color of the text beside it, so it reads on any card. It
// keeps asking for frames while it shows, and stops with its element.
func shapeLoader(c *ui.Context, fill ui.Color, size float32) {
	const period = 3.6 // seconds per cycle
	box := ui.Box(c).Size(size, size)
	start := ui.Local(box, "start", func() time.Time { return c.Now() })
	phase := math.Mod(c.Now().Sub(*start).Seconds(), period) / period

	angle := float32(360 * phase) // degrees, clockwise
	scale := float32(1 - 0.14*math.Abs(math.Sin(phase*2*math.Pi)))

	seq := []ribbonShape{cookie8, clover4, flower5}
	pos := phase * float64(len(seq))
	index := int(math.Floor(pos)) % len(seq)
	next := (index + 1) % len(seq)
	frac := pos - math.Floor(pos)
	k := frac * frac * (3 - 2*frac) // smoothstep: the morph eases at each shape

	box.Draw(func(p *ui.Painter, r ui.Rect) {
		cx, cy := r.X+r.W/2, r.Y+r.H/2
		radius := min(r.W, r.H) / 2 * 47 / 50
		shape := scallop(cx, cy, radius, seq[index], seq[next], k)
		p.Transform(ui.Scaling(scale, scale).Then(ui.Rotation(angle)), cx, cy, func() {
			p.FillPath(shape, fill)
		})
	})
	c.After(time.Second / 60)
}
