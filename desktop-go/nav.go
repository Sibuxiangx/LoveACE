package main

import (
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// The rail is a fixed column: each destination shows its icon over its label.
const (
	railWidth     = 88
	railIndicator = 56.0 // the square each destination's indicator is drawn in
	railBlob      = 24.0 // the indicator's radius once its destination is chosen
)

// A chosen destination's indicator grows out of a circle into one of railShapes.
// The shape is chosen by the destination's place in the rail, so neighbours never
// share one, and a new destination takes the next shape without a change here.
var (
	railCircle = ribbonShape{lobes: 0}
	railShapes = []ribbonShape{cookie8, flower5, clover4, cookie12}
)

// railShapeAt is the shape of the n-th destination of the rail, counting from the
// top, across the groups and the footer.
func railShapeAt(n int) ribbonShape {
	return railShapes[n%len(railShapes)]
}

// navDest is a destination of the rail: the page it opens, or the launch that opens its
// window instead, its label and icons, and, when set, whether it wants attention, which
// its indicator shows as a dot.
type navDest struct {
	page      page
	id, label string
	icon      *ui.SVG // outlined, as the destination rests
	selected  *ui.SVG // filled, as it is chosen
	attention func(a *app) bool
	launch    func(a *app) // when set, the destination launches its window instead of opening a page
}

// navGroups are the destinations above the footer, in runs. A rule separates the
// runs. A new page is a constant in app.go, a case in app.view, and a destination
// here or in navFooter.
var navGroups = [][]navDest{
	{
		{pageHome, "nav-home", "首页", iconHome, iconHomeFill, nil, nil},
		{pageAAC, "nav-aac", "爱安财", iconVolunteer, iconVolunteerFill, aacNeedsAttention, nil},
		{pageLabor, "nav-labor", "劳动俱乐部", iconLabor, iconLaborFill, nil, nil},
	},
	{
		{pagePlan, "nav-plan", "培养方案", iconCourse, iconCourseFill, nil, nil},
		{pageCard, "nav-card", "一卡通", iconCard, iconCardFill, nil, nil},
		{id: "nav-smart", label: "智能排课", icon: iconWeekView, selected: iconWeekViewFill, launch: (*app).openSmartWindow},
	},
}

// navFooter is pinned to the bottom of the rail, below the scrolling groups.
var navFooter = []navDest{
	{pageSettings, "nav-settings", "设置", iconSettings, iconSettingsFill, nil, nil},
}

// aacNeedsAttention is whether the graduation total is short of the school's
// requirement, which the 爱安财 destination marks with a dot.
func aacNeedsAttention(a *app) bool {
	return a.aac.loaded && a.aac.infoErr == "" && a.aac.info != nil && !a.aac.info.IsTypeAdopt
}

// navRail is the left column of a signed-in window: the app's mark, the groups
// of destinations, which scroll when they run past the window's height, and the
// footer at the bottom. Its strip at the top is the room the window controls
// leave, so it drags the window.
func (a *app) navRail(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	n := 0 // the shape index of the next destination, counted down the rail
	ui.Column(c).Width(railWidth).Shrink(0).AlignItems(ui.Center).Background(uiColor(s.SurfaceContainerLow)).Children(func() {
		dragStrip(c)
		railMark(c)
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().AlignItems(ui.Center).Gap(6).Children(func() {
				for i, group := range navGroups {
					if i > 0 {
						railRule(c, t)
					}
					for _, d := range group {
						a.navItem(c, t, s, d, railShapeAt(n))
						n++
					}
				}
			})
		})
		ui.Column(c).FillWidth().AlignItems(ui.Center).Gap(6).Padding(0, 0, 14, 0).Children(func() {
			railRule(c, t)
			for _, d := range navFooter {
				a.navItem(c, t, s, d, railShapeAt(n))
				n++
			}
		})
	})
}

// railMark is the app's mark at the top of the rail. It leans when the pointer
// rests on it, as the sign-in page's logo does.
func railMark(c *ui.Context) {
	ui.Column(c).FillWidth().AlignItems(ui.Center).Padding(4, 0, 12, 0).Children(func() {
		logo := ui.Image(c, appIcon).Size(40, 40).Fit(ui.Contain).Radius(14)
		pose := ui.Pose{}
		if logo.Hovered() {
			pose = ui.Pose{Rotate: 8, Scale: 1.06}
		}
		logo.AnimatePose(pose, ui.Bouncy)
	})
}

// railRule is the line between two runs of destinations.
func railRule(c *ui.Context, t *ui.Theme) {
	ui.Column(c).FillWidth().Padding(6, 22).Children(func() {
		ui.Box(c).FillWidth().Height(1).Background(t.Border)
	})
}

// navItem is one destination. Its indicator grows from a circle into shape when
// the destination is chosen, and its icon crossfades from outline to filled; the
// hover tint, the press squeeze and the label's weight move on springs too. Its
// key is its id, so its animated values follow it through the rebuilds of each
// frame.
func (a *app) navItem(c *ui.Context, t *ui.Theme, s palette.Scheme, d navDest, shape ribbonShape) {
	on := d.launch == nil && a.page == d.page
	btn := ui.ButtonBase(c.Key(d.id)).Width(railWidth-16).Radius(20).Padding(4, 0).Label(d.label)
	// sel overshoots when it springs, which the indicator's bounce wants; hover is
	// the tint under the pointer.
	sel := btn.AnimateTo("sel", flag01(on), ui.Bouncy)
	hover := btn.AnimateTo("hover", flag01(btn.Hovered()), ui.Smooth)
	press := ui.Pose{}
	if btn.Pressed() {
		press = ui.Pose{Scale: 0.94}
	}
	btn.AnimatePose(press, ui.Bouncy)
	btn.Background(t.SurfaceHover.Alpha(clamp01(hover)))
	if btn.Clicked() {
		if d.launch != nil {
			d.launch(a)
		} else {
			a.openPage(d.page)
		}
	}

	needs := d.attention != nil && d.attention(a)
	btn.Children(func() {
		ui.Column(c).FillWidth().AlignItems(ui.Center).Gap(2).Children(func() {
			navIndicator(c, t, s, d, shape, sel, needs)
			label := ui.Text(c, d.label).FontSize(12).TextColor(t.TextMuted.Mix(t.Text, clamp01(sel))).SingleLine()
			if on {
				label.Bold()
			}
		})
	})
}

// navIndicator draws a destination's indicator: the blob behind its icon, the
// icon crossfading from outline to filled, and the dot that asks for attention.
// The blob starts as a circle and morphs into the destination's shape while it
// turns into place.
func navIndicator(c *ui.Context, t *ui.Theme, s palette.Scheme, d navDest, shape ribbonShape, sel float32, needs bool) {
	ind := ui.Box(c.Key(d.id+"-indicator")).Size(railIndicator, railIndicator)
	attn := ind.AnimateTo("attention", flag01(needs), ui.Bouncy)
	m := clamp01(sel)
	grow := max(sel, 0) // a spring can overshoot below rest, which has no blob
	ind.Draw(func(p *ui.Painter, r ui.Rect) {
		cx, cy := r.X+r.W/2, r.Y+r.H/2
		if grow > 0 {
			blob := scallop(cx, cy, railBlob*grow, railCircle, shape, float64(m))
			p.Transform(ui.Rotation((1-grow)*-72), cx, cy, func() {
				p.FillPath(blob, uiColor(s.SecondaryContainer))
			})
		}
		icon := ui.Rect{X: cx - 12, Y: cy - 12, W: 24, H: 24}
		p.Icon(d.icon, icon, t.TextMuted.Alpha(1-m))
		p.Icon(d.selected, icon, uiColor(s.OnSecondaryContainer).Alpha(m))
		if attn > 0 {
			rad := 4 * attn
			p.Fill(ui.Rect{X: cx + 11 - rad, Y: cy - 15 - rad, W: 2 * rad, H: 2 * rad}, t.Danger, rad)
		}
	})
}

// flag01 is 1 for a true flag and 0 for a false one, the target of a spring.
func flag01(on bool) float32 {
	if on {
		return 1
	}
	return 0
}

// clamp01 keeps a spring's value in the range of a fraction.
func clamp01(v float32) float32 {
	return max(0, min(1, v))
}
