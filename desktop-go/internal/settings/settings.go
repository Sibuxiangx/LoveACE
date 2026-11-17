package settings

import (
	"slices"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// appVersion is the version the about row shows. It matches mygo.json.
const appVersion = "0.1.0"

// darkModes are the choices of the dark mode, in the order of the segments.
var darkModes = []string{DarkSystem, DarkLight, DarkDark}

// Page is the settings page. It owns the settings the app reads: the shell's
// appearance and the sign-in page read the same value through Settings.
type Page struct {
	h         host.Host
	onSignOut func()
	st        *Settings
}

// New reads the settings and makes the page. onSignOut is called after the
// account is signed out from the page, so the shell can drop its state.
func New(h host.Host, onSignOut func()) *Page {
	st := Load()
	return &Page{h: h, onSignOut: onSignOut, st: &st}
}

// Settings is the settings the page changes. The same value is shared with
// every other part of the app that reads or saves settings.
func (p *Page) Settings() *Settings { return p.st }

// signOut forgets the remembered password, as the sign-out always did, and
// hands the account over to the shell.
func (p *Page) signOut() {
	p.st.DropRemembered()
	p.st.Persist()
	p.onSignOut()
}

// View draws the settings page, in two columns: the appearance on the left,
// the account and the about on the right. It is a destination of the navigation
// rail, so there is no way back to pop: the rail is always there. Each choice
// applies at once, as the view reads the settings and the account every frame.
// The page is shown only when signed in, so the account is set.
func (p *Page) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		ui.Column(c).FillWidth().Padding(8, design.PageSide, 16, design.PageSide).Gap(2).Children(func() {
			ui.Text(c, "设置").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "外观、账号与关于").FontSize(13).TextColor(t.TextMuted)
		})
		ui.Row(c).Grow(1).Gap(20).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(20).Children(func() {
					section(c, t, "外观", func() {
						for i := 0; i < len(design.Presets); i += 3 {
							ui.Row(c).FillWidth().Justify(ui.SpaceBetween).Children(func() {
								for _, pr := range design.Presets[i:min(i+3, len(design.Presets))] {
									p.swatch(c, t, pr)
								}
							})
						}
						design.ListRow(c, t, "dark-mode", design.RowBadge{Shape: design.Flower5, Icon: design.IconDarkMode, Fill: t.Accent, Tint: t.AccentText},
							"深浅色", "跟随系统、浅色或深色", func() {
								// The segment is the position of the mode in darkModes, read
								// anew each frame, so a choice made here is the one shown.
								idx := max(0, slices.Index(darkModes, p.st.DarkMode))
								seg := ui.Segmented(c, &idx, "跟随系统", "浅色", "深色").Label("深浅色")
								if seg.Changed() {
									p.st.DarkMode = darkModes[idx]
									p.st.Persist()
								}
							}, nil)
					})
				})
			})

			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(20).Children(func() {
					section(c, t, "账号", func() {
						// Signing out is the one control that clears the account, so it
						// sits on the account's own row.
						design.ListRow(c, t, "account", design.RowBadge{Shape: design.Cookie8, Icon: design.IconAccount, Fill: t.Accent, Tint: t.AccentText},
							p.h.Account().ID, "当前登录的教务系统账号", func() {
								design.PillButton(c, "settings-sign-out", design.IconLogout, "退出登录",
									design.UIColor(s.ErrorContainer), design.UIColor(s.OnErrorContainer), p.signOut)
							}, nil)

						// The password is kept only when signing in asked for it, so there
						// is no switch here: the row shows what is remembered and forgets it.
						caption := "登录时勾选“记住密码”即可保存"
						var remember func()
						if p.st.RememberID != "" {
							caption = "密码保存在系统钥匙串，仅本机可用"
							remember = func() {
								ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
									design.Chip(c, "已记住", design.IconLock, design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer))
									design.PillButton(c, "settings-forget", design.IconCancel, "忘记密码", t.SurfaceHover, t.Text, func() {
										p.st.DropRemembered()
										p.st.Persist()
									})
								})
							}
						}
						design.ListRow(c, t, "remember", design.RowBadge{Shape: design.Clover4, Icon: design.IconLock, Fill: t.Accent, Tint: t.AccentText},
							"记住密码", caption, remember, nil)
					})

					section(c, t, "关于", func() {
						design.ListRow(c, t, "about", design.RowBadge{Shape: design.Cookie12, Icon: design.IconInfo, Fill: t.Accent, Tint: t.AccentText},
							"彩带小工具", "版本 "+appVersion, nil, nil)
					})
				})
			})
		})
	})
}

// section is a caption over a card of the settings page, holding the rows of
// the section.
func section(c *ui.Context, t *ui.Theme, title string, body func()) {
	ui.Column(c).FillWidth().Gap(8).Children(func() {
		design.SectionTitle(c, t, title)
		design.Surface(c, t.Surface, 28, 20, body)
	})
}

// swatch is one accent: a scallop in the preset's own accent, ringed when it is
// the chosen one, with its name under it.
func (p *Page) swatch(c *ui.Context, t *ui.Theme, pr design.Preset) {
	on := p.st.Preset == pr.ID
	// The accent is the one the appearance in use gives the preset, so the
	// swatch shows the colors the app would take.
	sc := design.SchemeOf(pr, t.Dark)
	accent := design.UIColor(sc.Primary)
	onAccent := design.UIColor(sc.OnPrimary)

	btn := ui.ButtonBase(c.Key(pr.ID)).Size(72, 96).Radius(t.Radius).Padding(8, 4)
	if btn.Hovered() {
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Column(c).Gap(6).AlignItems(ui.Center).Children(func() {
			ui.Box(c).Size(44, 44).Draw(func(pt *ui.Painter, r ui.Rect) {
				cx, cy := r.X+r.W/2, r.Y+r.H/2
				// The scallop is drawn inside the box, as ShapeBadge does, so the ring
				// below stays within it.
				radius := min(r.W, r.H) / 2 * 47 / 50
				pt.FillPath(design.Scallop(cx, cy, radius, design.Cookie12, design.Cookie12, 0), accent)
				if on {
					pt.StrokePath(design.Scallop(cx, cy, radius, design.Cookie12, design.Cookie12, 0), 3, t.Text)
					pt.Icon(design.IconCheck, ui.Rect{X: cx - 8, Y: cy - 8, W: 16, H: 16}, onAccent)
				}
			})
			name := ui.Text(c, pr.Name).FontSize(13)
			if on {
				name.Bold().TextColor(t.Text)
			} else {
				name.TextColor(t.TextMuted)
			}
		})
	})
	if btn.Clicked() && !on {
		p.st.Preset = pr.ID
		p.st.Persist()
	}
}
