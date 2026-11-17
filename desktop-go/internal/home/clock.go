package home

import (
	"fmt"
	"math"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/egoist/mygo/ui"
)

// The clock is the cookie clock of end-4/dots-hyprland (quickshell,
// modules/ii/background/widgets/clock/CookieClock.qml) with its defaults: a
// 14-sided cookie, a full dial of minute and hour marks, the hour and minute in
// the middle, a filled hour hand, a medium minute hand, a dot second hand, and
// a centre dot the colour of the cookie.
//
// The source draws on a 230 dial, and its sizes are given here in those units
// (the dial's radius is 115), scaled to the dial the card draws.
const (
	clockSize   = 128.0 // the dial's box, in dp
	clockSource = 115.0 // the source dial's radius, in its units

	clockSides  = 14
	clockCorner = 1.5 / clockSides // the cookie's corner rounding, relative to its radius
	clockInner  = 0.8              // the cookie's inner radius, relative to its outer one

	// Marks ride the rim: the hour marks run from 103 to 85, the minute marks from
	// 103 to 96, and an hour mark replaces the minute mark at its place.
	clockMarkOuter     = 103.0
	clockHourMarkInner = 85.0
	clockMinuteInner   = 96.0
	clockHourMarkW     = 4.0
	clockMinuteMarkW   = 2.0

	// The numbers in the middle: the hour above the minute, 68 high, 16 apart.
	clockNumber    = 68.0
	clockNumberGap = -16.0

	// The hands run from behind the centre to their tips. The hour hand is 20 wide
	// and reaches 62, the minute hand is 12 wide and reaches 89.
	clockHourTail   = 10.0
	clockHourTip    = 62.0
	clockHourW      = 20.0
	clockMinuteTail = 6.0
	clockMinuteTip  = 89.0
	clockMinuteW    = 12.0

	// The second dot is 20 across, centred 75 from the middle, and the centre dot is 6 across.
	clockSecondDist = 75.0
	clockSecondR    = 10.0
	clockCentreR    = 3.0
)

// homeClock is the clock card: the cookie dial, with the date and the weekday
// beside it. The hands and the second dot move once a second, so the card asks
// for the frame of the next second.
func homeClock(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	now := timeutil.NowShanghai()
	c.After(time.Second)
	ui.Row(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(14).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Children(func() {
		ui.Box(c).Size(clockSize, clockSize).Draw(func(p *ui.Painter, r ui.Rect) {
			drawCookieClock(p, r, now, s)
		})
		ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
			ui.Text(c, weekdayNames[classDay(now)-1]).FontSize(14).Bold().TextColor(t.Text)
			ui.Text(c, fmt.Sprintf("%d月%d日", int(now.Month()), now.Day())).FontSize(12).TextColor(t.TextMuted)
		})
	})
}

// clockFractions is where the three hands of now point, each as a fraction of a
// full turn from twelve o'clock, clockwise: the hour hand over twelve hours, the
// minute and second hands over sixty.
func clockFractions(now time.Time) (hour, minute, second float64) {
	s := float64(now.Second())
	m := float64(now.Minute()) + s/60
	h := float64(now.Hour()%12) + m/60
	return h / 12, m / 60, s / 60
}

// drawCookieClock paints the dial in the box r, in the source's order: the
// cookie, the marks, the numbers, the hands, the second dot, and the centre dot.
func drawCookieClock(p *ui.Painter, r ui.Rect, now time.Time, s palette.Scheme) {
	cx, cy := r.X+r.W/2, r.Y+r.H/2
	k := float64(r.W/2) / clockSource // px per source unit
	pc := design.UIColor(s.PrimaryContainer)
	primary := design.UIColor(s.Primary)

	// The colours are the source's mixes: the marks are 15% secondary, the numbers
	// 55% primary, over the primary container.
	marks := pc.Mix(design.UIColor(s.Secondary), 0.15)
	info := pc.Mix(primary, 0.55)

	p.FillPath(cookiePath(cx, cy, r.W/2), pc)

	// at is the point a distance from the middle along the direction of a fraction
	// of a turn from twelve o'clock, in source units.
	at := func(frac, units float64) (float32, float32) {
		th := frac * 2 * math.Pi
		return cx + float32(units*k*math.Sin(th)), cy - float32(units*k*math.Cos(th))
	}
	for i := range 60 {
		frac := float64(i) / 60
		x0, y0 := at(frac, clockMarkOuter)
		if i%5 == 0 {
			x1, y1 := at(frac, clockHourMarkInner)
			p.StrokePath((&ui.Path{}).MoveTo(x0, y0).LineTo(x1, y1), float32(clockHourMarkW*k), marks)
		} else {
			x1, y1 := at(frac, clockMinuteInner)
			p.StrokePath((&ui.Path{}).MoveTo(x0, y0).LineTo(x1, y1), float32(clockMinuteMarkW*k), marks)
		}
	}

	drawClockNumbers(p, cx, cy, k, now, info)

	hour, minute, second := clockFractions(now)
	hand := func(frac, tail, tip, width float64, col ui.Color) {
		x0, y0 := at(frac, -tail)
		x1, y1 := at(frac, tip)
		p.StrokePath((&ui.Path{}).MoveTo(x0, y0).LineTo(x1, y1), float32(width*k), col)
	}
	hand(hour, clockHourTail, clockHourTip, clockHourW, primary)
	hand(minute, clockMinuteTail, clockMinuteTip, clockMinuteW, design.UIColor(s.Tertiary))

	dx, dy := at(second, clockSecondDist)
	rad := float32(clockSecondR * k)
	p.Fill(ui.Rect{X: dx - rad, Y: dy - rad, W: 2 * rad, H: 2 * rad}, primary, rad)

	rad = float32(clockCentreR * k)
	p.Fill(ui.Rect{X: cx - rad, Y: cy - rad, W: 2 * rad, H: 2 * rad}, pc, rad)
}

// drawClockNumbers sets the hour above the minute in the middle of the dial, in
// the source's bold 68, with its negative gap between the two.
func drawClockNumbers(p *ui.Painter, cx, cy float32, k float64, now time.Time, col ui.Color) {
	size := float32(clockNumber * k)
	gap := float32(clockNumberGap * k)
	hour := ui.Span{Text: fmt.Sprintf("%02d", now.Hour()), Font: "MiSans", Size: size, Weight: 700, Color: col}
	minute := ui.Span{Text: fmt.Sprintf("%02d", now.Minute()), Font: "MiSans", Size: size, Weight: 700, Color: col}
	hw, hh := p.MeasureText(0, hour)
	mw, mh := p.MeasureText(0, minute)
	top := cy - (hh+gap+mh)/2
	p.RichText(cx-hw/2, top, 0, hour)
	p.RichText(cx-mw/2, top+hh+gap, 0, minute)
}

// cookiePath is the cookie of the dial: a star of clockSides points on a circle
// of radius, with each tip rounded. Material's rounded polygon draws the tips as
// arcs; a quadratic curve through each tip, joining the edges where the arc
// would start, is the same shape at this size.
func cookiePath(cx, cy, radius float32) *ui.Path {
	n := clockSides * 2
	type vertex struct{ x, y float64 }
	verts := make([]vertex, n)
	for i := range verts {
		rr := 1.0
		if i%2 == 1 {
			rr = clockInner
		}
		th := -math.Pi/2 + float64(i)*math.Pi/clockSides
		verts[i] = vertex{
			x: float64(cx) + float64(radius)*rr*math.Cos(th),
			y: float64(cy) + float64(radius)*rr*math.Sin(th),
		}
	}
	// corner is the radius of each tip's rounding, in px.
	corner := clockCorner * float64(radius)
	path := &ui.Path{}
	for i, v := range verts {
		prev, next := verts[(i-1+n)%n], verts[(i+1)%n]
		ux, uy := prev.x-v.x, prev.y-v.y
		wx, wy := next.x-v.x, next.y-v.y
		lu, lw := math.Hypot(ux, uy), math.Hypot(wx, wy)
		// The interior angle at the tip sets how far back the rounding starts along
		// each edge; no further back than half the shorter edge.
		cos := (ux*wx + uy*wy) / (lu * lw)
		angle := math.Acos(math.Max(-1, math.Min(1, cos)))
		d := math.Min(corner/math.Tan(angle/2), math.Min(lu, lw)/2)
		startX, startY := float32(v.x+ux/lu*d), float32(v.y+uy/lu*d)
		endX, endY := float32(v.x+wx/lw*d), float32(v.y+wy/lw*d)
		if i == 0 {
			path.MoveTo(startX, startY)
		} else {
			path.LineTo(startX, startY)
		}
		path.QuadTo(float32(v.x), float32(v.y), endX, endY)
	}
	return path.Close()
}
