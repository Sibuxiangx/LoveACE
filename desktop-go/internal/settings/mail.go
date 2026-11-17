package settings

import (
	"context"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	portalsvc "github.com/Sibuxiangx/loveace-go/core/services/portal"
	"github.com/egoist/mygo/ui"
)

// mailPassword is the enterprise-mail initial password the account row shows. It is a plain
// school value: it is read only when asked, kept in memory, shown only when asked again, and
// forgotten when the settings page is left or the account signs out. It is never logged and
// never written to disk.
type mailPassword struct {
	// gen is bumped by each read and each forget. A read that lands with an older gen is
	// dropped, so a password read before the page was left never comes back.
	gen     int
	loading bool
	loaded  bool
	// got is nil when the portal has no row for the account.
	got *portalsvc.MailInitialPassword
	// err is the wording of a failed read.
	err   string
	shown bool
}

// Leave forgets the mail password. The settings page calls it when the page is left and when
// the account signs out. A read still running is dropped when it lands.
func (p *Page) Leave() {
	p.mail = mailPassword{gen: p.mail.gen + 1}
}

// loadMail reads the password from the portal in the background. A read already running is
// not started again.
func (p *Page) loadMail() {
	acc := p.h.Account()
	if acc == nil || p.mail.loading {
		return
	}
	p.mail.gen++
	p.mail.loading, p.mail.err = true, ""
	gen := p.mail.gen
	host.Start(p.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, portalsvc.New(acc.Sess).MailInitialPassword)
		apply(func() { p.takeMail(gen, got, err) })
	})
}

// takeMail applies the result of the read under generation gen, on the main thread.
func (p *Page) takeMail(gen int, got *portalsvc.MailInitialPassword, err error) {
	if gen != p.mail.gen {
		return
	}
	p.mail.loading = false
	if err != nil {
		p.mail.err = read.ErrText(err)
		return
	}
	p.mail.loaded, p.mail.got, p.mail.err = true, got, ""
}

// mailRow is the enterprise-mail initial password, under the remembered password. It reads the
// portal only when the user asks, and shows the password only when the user asks again.
func (p *Page) mailRow(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	m := p.mail
	fill, fg := design.UIColor(s.SurfaceContainerHigh), t.Text
	caption := "学校门户里的企业邮箱初始密码，需要时才读取"
	var trailing func()
	switch {
	case m.loading:
		caption = "正在读取"
		trailing = func() { design.ShapeLoader(c, t.Accent, 28) }
	case m.err != "":
		caption = "读取没有成功，可以重试"
		trailing = func() {
			ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
				design.Note(c, m.err, t.Danger)
				design.PillButton(c, "mail-retry", design.IconRefresh, "重试", fill, fg, p.loadMail)
			})
		}
	case m.loaded && m.got == nil:
		caption = "门户里没有这个账号的记录"
	case m.loaded:
		caption = "门户没有给出登录名"
		if m.got.LoginID != "" {
			caption = "登录名 " + m.got.LoginID
		}
		trailing = func() {
			ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
				passwordChip(c, s, m)
				if m.shown {
					design.PillButton(c, "mail-hide", design.IconVisibilityOff, "隐藏", fill, fg, func() { p.mail.shown = false })
				} else {
					design.PillButton(c, "mail-show", design.IconVisibility, "显示", fill, fg, func() { p.mail.shown = true })
				}
			})
		}
	default:
		trailing = func() {
			design.PillButton(c, "mail-view", design.IconVisibility, "查看", fill, fg, p.loadMail)
		}
	}
	design.ListRow(c, t, "mail-password", design.RowBadge{Shape: design.Flower5, Icon: design.IconLock, Fill: t.Accent, Tint: t.AccentText},
		"企业邮箱初始密码", caption, trailing, nil)
}

// passwordText is the password as the row shows it: the text when shown, dots otherwise. It is
// called only once a password was read.
func passwordText(m mailPassword) string {
	if m.shown {
		return m.got.Password
	}
	return "••••••••"
}

// passwordChip is the password in a chip, drawn as design.Chip draws one. Shown, its text can
// be selected and copied; hidden, it is dots, which are not worth copying.
func passwordChip(c *ui.Context, s palette.Scheme, m mailPassword) {
	fill, fg := design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer)
	ui.Row(c).Children(func() {
		ui.Row(c).Background(fill).Radius(999).Padding(4, 12).Gap(6).AlignItems(ui.Center).Children(func() {
			label := ui.Text(c, passwordText(m)).FontSize(12).Bold().TextColor(fg)
			if m.shown {
				label = label.Selectable()
			}
		})
	})
}
