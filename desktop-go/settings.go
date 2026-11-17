package main

import (
	"slices"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// appVersion is the version the about row shows. It matches mygo.json.
const appVersion = "0.1.0"

// darkModes are the choices of the dark mode, in the order of the segments.
var darkModes = []string{darkSystem, darkLight, darkDark}

// settingsView is the settings page, in two columns: the appearance on the left,
// the account and the about on the right. It is a destination of the navigation
// rail, so there is no way back to pop: the rail is always there. Each choice
// applies at once, as the view reads the settings and the account every frame.
// The page is shown only when signed in, so a.acc is set.
func (a *app) settingsView(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		ui.Column(c).FillWidth().Padding(8, homeSide, 16, homeSide).Gap(2).Children(func() {
			ui.Text(c, "设置").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "外观、账号与关于").FontSize(13).TextColor(t.TextMuted)
		})
		ui.Row(c).Grow(1).Gap(20).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(20).Children(func() {
					settingsSection(c, t, "外观", func() {
						for i := 0; i < len(presets); i += 3 {
							ui.Row(c).FillWidth().Justify(ui.SpaceBetween).Children(func() {
								for _, p := range presets[i:min(i+3, len(presets))] {
									a.settingsSwatch(c, t, p)
								}
							})
						}
						listRow(c, t, "dark-mode", rowBadge{flower5, iconDarkMode, t.Accent, t.AccentText},
							"深浅色", "跟随系统、浅色或深色", func() {
								// The segment is the position of the mode in darkModes, read
								// anew each frame, so a choice made here is the one shown.
								idx := max(0, slices.Index(darkModes, a.settings.DarkMode))
								seg := ui.Segmented(c, &idx, "跟随系统", "浅色", "深色").Label("深浅色")
								if seg.Changed() {
									a.settings.DarkMode = darkModes[idx]
									a.saveSettings()
								}
							}, nil)
					})
				})
			})

			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(20).Children(func() {
					settingsSection(c, t, "账号", func() {
						// Signing out is the one control that clears the account, so it
						// sits on the account's own row.
						listRow(c, t, "account", rowBadge{cookie8, iconAccount, t.Accent, t.AccentText},
							a.acc.id, "当前登录的教务系统账号", func() {
								pillButton(c, "settings-sign-out", iconLogout, "退出登录",
									uiColor(s.ErrorContainer), uiColor(s.OnErrorContainer), a.signOut)
							}, nil)

						// The password is kept only when signing in asked for it, so there
						// is no switch here: the row shows what is remembered and forgets it.
						caption := "登录时勾选“记住密码”即可保存"
						var remember func()
						if a.settings.RememberID != "" {
							caption = "密码保存在系统钥匙串，仅本机可用"
							remember = func() {
								ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
									chip(c, "已记住", iconLock, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer))
									pillButton(c, "settings-forget", iconCancel, "忘记密码", t.SurfaceHover, t.Text, func() {
										a.dropRemembered()
										a.saveSettings()
									})
								})
							}
						}
						listRow(c, t, "remember", rowBadge{clover4, iconLock, t.Accent, t.AccentText},
							"记住密码", caption, remember, nil)
					})

					settingsSection(c, t, "关于", func() {
						listRow(c, t, "about", rowBadge{cookie12, iconInfo, t.Accent, t.AccentText},
							"彩带小工具", "版本 "+appVersion, nil, nil)
					})
				})
			})
		})
	})
}

// settingsSection is a caption over a card of the settings page, holding the
// rows of the section.
func settingsSection(c *ui.Context, t *ui.Theme, title string, body func()) {
	ui.Column(c).FillWidth().Gap(8).Children(func() {
		sectionTitle(c, t, title)
		surface(c, t.Surface, 28, 20, body)
	})
}

// settingsSwatch is one accent: a scallop in the preset's own accent, ringed
// when it is the chosen one, with its name under it.
func (a *app) settingsSwatch(c *ui.Context, t *ui.Theme, p preset) {
	on := a.settings.Preset == p.id
	// The accent is the one the appearance in use gives the preset, so the
	// swatch shows the colors the app would take.
	sc := schemeOf(p, t.Dark)
	accent := uiColor(sc.Primary)
	onAccent := uiColor(sc.OnPrimary)

	btn := ui.ButtonBase(c.Key(p.id)).Size(72, 96).Radius(t.Radius).Padding(8, 4)
	if btn.Hovered() {
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Column(c).Gap(6).AlignItems(ui.Center).Children(func() {
			ui.Box(c).Size(44, 44).Draw(func(pt *ui.Painter, r ui.Rect) {
				cx, cy := r.X+r.W/2, r.Y+r.H/2
				// The scallop is drawn inside the box, as shapeBadge does, so the ring
				// below stays within it.
				radius := min(r.W, r.H) / 2 * 47 / 50
				pt.FillPath(scallop(cx, cy, radius, cookie12, cookie12, 0), accent)
				if on {
					pt.StrokePath(scallop(cx, cy, radius, cookie12, cookie12, 0), 3, t.Text)
					pt.Icon(iconCheck, ui.Rect{X: cx - 8, Y: cy - 8, W: 16, H: 16}, onAccent)
				}
			})
			name := ui.Text(c, p.name).FontSize(13)
			if on {
				name.Bold().TextColor(t.Text)
			} else {
				name.TextColor(t.TextMuted)
			}
		})
	})
	if btn.Clicked() && !on {
		a.settings.Preset = p.id
		a.saveSettings()
	}
}
