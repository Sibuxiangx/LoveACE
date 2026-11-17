package design

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
// set apart by CardGap in both directions.
const (
	CardRadius = 28 // a card
	TileRadius = 16 // a tile inside a card, and a row's highlight
	CardPad    = 20 // a card's padding
	CardGap    = 16 // between cards, and between the parts of a large card
)

// The window's shared layout: the title bar's room, the side margin of a page, and the
// padding of a compact strip. Every page uses these, so they live here.
const (
	TitleBarHeight = 52 // the room of the title bar the view draws
	PageSide       = 28 // the side margin of a page, which the header and the cards share
	CompactPad     = 16 // the vertical padding of the wallet and 爱安财 strips
)

// Cookie12 is the twelve-lobed cookie of Material 3 Expressive, the shape of
// the app's identity and of the vacation.
var Cookie12 = RibbonShape{Lobes: 12, Amp: 0.05}

// ShapeBadge is an icon inside a scallop, as the Android app's ShapeBadge. The
// icon fills half the badge; a nil icon leaves the scallop alone.
func ShapeBadge(c *ui.Context, shape RibbonShape, size float32, fill ui.Color, icon *ui.SVG, tint ui.Color) {
	ui.Box(c).Size(size, size).Draw(func(p *ui.Painter, r ui.Rect) {
		cx, cy := r.X+r.W/2, r.Y+r.H/2
		radius := min(r.W, r.H) / 2 * 47 / 50
		p.FillPath(Scallop(cx, cy, radius, shape, shape, 0), fill)
		if icon != nil {
			s := r.W / 2
			p.Icon(icon, ui.Rect{X: cx - s/2, Y: cy - s/2, W: s, H: s}, tint)
		}
	})
}

// DrawGauge paints a ring that fills clockwise from the top to value (0 to 1)
// inside r: the GPA gauge and the graduation requirements. The rest of the ring
// is the track.
func DrawGauge(p *ui.Painter, r ui.Rect, width float32, value float64, fill, track ui.Color) {
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

// WavyBar is a progress bar whose done part waves, as Material 3 Expressive's
// wavy indicator. The wave moves while the frame asks for it, and holds still
// when the system asks for less motion. The track is the part the wave has not
// reached, so the two never share a span.
func WavyBar(c *ui.Context, value float64, fill, track ui.Color) {
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

// PillBar is a straight progress bar with round ends. It fills the width its
// column gives it.
func PillBar(c *ui.Context, height float32, value float64, fill, track ui.Color) {
	v := float32(math.Min(math.Max(value, 0), 1))
	ui.Box(c).Height(height).FillWidth().Draw(func(p *ui.Painter, r ui.Rect) {
		p.Fill(r, track, r.H/2)
		if v > 0 {
			p.Fill(ui.Rect{X: r.X, Y: r.Y, W: r.W * v, H: r.H}, fill, r.H/2)
		}
	})
}

// Surface is a rounded container of color fill that holds body. It takes the
// height of its content: the settings sections use it inside a scrolling column.
func Surface(c *ui.Context, fill ui.Color, radius, pad float32, body func()) {
	ui.Column(c).Background(fill).Radius(radius).Padding(pad).Gap(12).Children(body)
}

// CardHeader is the head of a card: its badge, its title in fg, and whatever
// trailing draws at the end of the row. A nil trailing draws nothing there.
func CardHeader(c *ui.Context, badge RowBadge, title string, fg ui.Color, trailing func()) {
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
		ShapeBadge(c, badge.Shape, 36, badge.Fill, badge.Icon, badge.Tint)
		ui.Text(c, title).FontSize(16).Bold().TextColor(fg)
		ui.Spacer(c)
		if trailing != nil {
			trailing()
		}
	})
}

// Chip is a short label on a full-rounded pill, with an optional icon. It keeps
// the width of its text: it sits in a row, which a stretching column does not
// stretch.
func Chip(c *ui.Context, text string, icon *ui.SVG, fill, fg ui.Color) {
	ui.Row(c).Children(func() {
		ui.Row(c).Background(fill).Radius(999).Padding(4, 12).Gap(6).AlignItems(ui.Center).Children(func() {
			if icon != nil {
				ui.Icon(c, icon).FontSize(14).TextColor(fg)
			}
			ui.Text(c, text).FontSize(12).Bold().TextColor(fg)
		})
	})
}

// RowBadge is the badge at the start of a card head or a list row.
type RowBadge struct {
	Shape      RibbonShape
	Icon       *ui.SVG
	Fill, Tint ui.Color
}

// ListRow is a row of a list: a badge, a title, a caption, and whatever
// trailing draws at its end. With onClick the row is a button.
func ListRow(c *ui.Context, t *ui.Theme, key string, badge RowBadge, title, caption string, trailing func(), onClick func()) {
	body := func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(14).Children(func() {
			ShapeBadge(c, badge.Shape, 44, badge.Fill, badge.Icon, badge.Tint)
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

// PillButton is a full-rounded action with an icon and a label.
func PillButton(c *ui.Context, key string, icon *ui.SVG, label string, fill, fg ui.Color, onClick func()) {
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

// SectionTitle is the caption that heads a group of cards.
func SectionTitle(c *ui.Context, t *ui.Theme, text string) {
	ui.Text(c, text).FontSize(13).Bold().TextColor(t.TextMuted)
}

// DragStrip is the top of a page that drags the window. The title bar is
// hidden, so the strip is the room it leaves: the full width of its column, as
// tall as the title bar. Controls never go on it.
func DragStrip(c *ui.Context) {
	ui.Box(c).FillWidth().Height(TitleBarHeight).Shrink(0).DragWindow()
}

// IconButton is a round control with an icon, lit while the pointer is on it.
func IconButton(c *ui.Context, t *ui.Theme, icon *ui.SVG, label string, onClick func()) {
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

// ShapeLoader is the loading indicator of every read: the M3E shape loader of
// the Android app. A cookie-8 morphs through clover-4 and flower-5 back to
// cookie-8 every 3.6 s, turning once a cycle and breathing twice in it. It is
// drawn in fill, the color of the text beside it, so it reads on any card. It
// keeps asking for frames while it shows, and stops with its element.
func ShapeLoader(c *ui.Context, fill ui.Color, size float32) {
	const period = 3.6 // seconds per cycle
	box := ui.Box(c).Size(size, size)
	start := ui.Local(box, "start", func() time.Time { return c.Now() })
	phase := math.Mod(c.Now().Sub(*start).Seconds(), period) / period

	angle := float32(360 * phase) // degrees, clockwise
	scale := float32(1 - 0.14*math.Abs(math.Sin(phase*2*math.Pi)))

	seq := []RibbonShape{Cookie8, Clover4, Flower5}
	pos := phase * float64(len(seq))
	index := int(math.Floor(pos)) % len(seq)
	next := (index + 1) % len(seq)
	frac := pos - math.Floor(pos)
	k := frac * frac * (3 - 2*frac) // smoothstep: the morph eases at each shape

	box.Draw(func(p *ui.Painter, r ui.Rect) {
		cx, cy := r.X+r.W/2, r.Y+r.H/2
		radius := min(r.W, r.H) / 2 * 47 / 50
		shape := Scallop(cx, cy, radius, seq[index], seq[next], k)
		p.Transform(ui.Scaling(scale, scale).Then(ui.Rotation(angle)), cx, cy, func() {
			p.FillPath(shape, fill)
		})
	})
	c.After(time.Second / 60)
}
