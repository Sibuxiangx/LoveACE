package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"regexp"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/session"
	"github.com/egoist/mygo/ui"
)

var studentID = regexp.MustCompile(`^\d{8}$`)

// loginForm is the state of the sign-in page. While the school asks for a
// captcha, captcha is its image and pending is the account that asked. The
// account and password fields stay locked until the captcha is answered or
// cancelled, because the pending session belongs to those credentials.
type loginForm struct {
	id, password, code   string
	idErr, pwErr, status string
	remember, showPwd    bool
	loading              bool
	captcha              *ui.Bitmap
	pending              *account
}

func (a *app) loginView(c *ui.Context, t *ui.Theme) {
	// The brand pane draws the window's material where it shows through, as a
	// sidebar does, and the card sits in the pane on the right.
	vibrant := c.Vibrancy()
	if vibrant {
		c.Root().Background(ui.Transparent)
	}

	tonal := t.Accent.Alpha(0.14)  // a container tone of the accent
	fill := t.Text.Alpha(0.06)     // a filled field
	fillFocus := t.Text.Alpha(0.1) // a filled field with the keyboard or pointer in it

	ui.Row(c).Fill().AlignItems(ui.Stretch).Children(func() {
		// The brand pane runs to the top of the window. The window controls
		// sit over it, so its content starts below them.
		brand := ui.Column(c).Width(brandWidth).Shrink(0).Clip().
			Padding(0, 28, 32, 28).Gap(20)
		if !vibrant {
			brand.Background(t.Surface)
		}
		brand.Draw(func(p *ui.Painter, r ui.Rect) {
			p.FillPath(cookie(r.X+r.W*0.86, r.Y+r.H*0.9, 130, 10, 8), tonal)
		})
		brand.Children(func() {
			dragStrip(c)
			// The app's icon, as Android's login screen shows its logo. It lifts
			// while the pointer rests on it.
			logo := ui.Image(c, appIcon).Size(72, 72).Fit(ui.Contain).Radius(20)
			press := ui.Pose{}
			if logo.Hovered() {
				press = ui.Pose{Y: -2, Scale: 1.04}
			}
			logo.AnimatePose(press, ui.Bouncy)

			ui.Column(c).Gap(6).Children(func() {
				ui.Text(c, "彩带小工具").FontSize(32).Bold().TextColor(t.Text)
				ui.Text(c, "使用教务系统账号登录").FontSize(15).TextColor(t.TextMuted)
			})
		})

		ui.Box(c).Width(1).Background(t.Border)

		// The right pane keeps a strip at the top to drag the window from,
		// and centers the card under it.
		pane := ui.Column(c).Grow(1).MinWidth(0).Background(t.Background)
		pane.Children(func() {
			ui.Box(c).Height(titleBarHeight).Shrink(0).DragWindow()
			ui.Column(c).Grow(1).Center().Children(func() {
				a.loginCard(c, t, fill, fillFocus)
			})
		})
	})
}

// loginCard is the form: the fields, the captcha when the school asks for one,
// the button and the loader of the wait. It rises and fades in on first show.
func (a *app) loginCard(c *ui.Context, t *ui.Theme, fill, fillFocus ui.Color) {
	f := &a.login
	locked := f.loading || f.pending != nil
	card := ui.Column(c).Width(cardWidth).Padding(32).Gap(20).Radius(32).Background(t.Surface).
		Shadow(0, 1, 2, 0, ui.RGBA(0, 0, 0, 0.10)).
		Shadow(0, 8, 24, 0, ui.RGBA(0, 0, 0, 0.12))
	entered := ui.Local(card, "entered", func() bool { return false })
	pose := ui.Pose{}
	if !*entered {
		// Pose it below, then let it settle at its place in the next build,
		// as MyGo's pose docs describe.
		pose, *entered = ui.Pose{Y: 24, Fade: 1}, true
		c.Invalidate()
	}
	card.AnimatePose(pose, ui.Snappy)

	card.Children(func() {
		ui.Text(c, "欢迎回来").FontSize(24).Bold().TextColor(t.Text)

		idBox := ui.Column(c).Width(fieldWidth).Radius(20).Padding(10, 16)
		idFocused := false
		idBox.Children(func() {
			ui.Row(c).Height(32).Gap(12).AlignItems(ui.Center).Children(func() {
				ui.Icon(c, iconPerson).TextColor(t.TextMuted)
				in := ui.TextInputBase(c, &f.id).Label("学号").Placeholder("8 位学号").
					Disabled(locked).Width(fieldWidth - 56)
				idFocused = in.Focused()
			})
		})
		switch {
		case f.idErr != "":
			idBox.Border(2, t.Danger).Background(fill)
		case idFocused:
			idBox.Border(2, t.Accent).Background(fillFocus)
		default:
			idBox.Border(2, ui.Transparent).Background(fill)
		}
		if f.idErr != "" {
			ui.Text(c, f.idErr).FontSize(12).TextColor(t.Danger)
		}

		pwBox := ui.Column(c).Width(fieldWidth).Radius(20).Padding(10, 16)
		pwFocused := false
		pwBox.Children(func() {
			ui.Row(c).Height(32).Gap(12).AlignItems(ui.Center).Children(func() {
				ui.Icon(c, iconLock).TextColor(t.TextMuted)
				in := ui.TextInputBase(c, &f.password).Label("密码").Placeholder("教务系统密码").
					Disabled(locked).Width(fieldWidth - 96).OnSubmit(a.submit)
				if !f.showPwd {
					// Password hides the text in the frames that call it: an
					// eye button that shows it simply stops calling it.
					in.Password()
				}
				pwFocused = in.Focused()
				eye := ui.ButtonBase(c.Key("eye")).Size(32, 32).Radius(16).Center().
					Label(map[bool]string{true: "隐藏密码", false: "显示密码"}[f.showPwd]).
					Tooltip(map[bool]string{true: "隐藏密码", false: "显示密码"}[f.showPwd])
				if eye.Hovered() {
					eye.Background(t.SurfaceHover)
				}
				eye.Children(func() {
					if f.showPwd {
						ui.Icon(c, iconVisibilityOff).TextColor(t.TextMuted)
					} else {
						ui.Icon(c, iconVisibility).TextColor(t.TextMuted)
					}
				})
				if eye.Clicked() {
					f.showPwd = !f.showPwd
				}
			})
		})
		switch {
		case f.pwErr != "":
			pwBox.Border(2, t.Danger).Background(fill)
		case pwFocused:
			pwBox.Border(2, t.Accent).Background(fillFocus)
		default:
			pwBox.Border(2, ui.Transparent).Background(fill)
		}
		if f.pwErr != "" {
			ui.Text(c, f.pwErr).FontSize(12).TextColor(t.Danger)
		}

		if f.captcha != nil {
			a.captchaRow(c, t, fill, fillFocus)
		}

		ui.Checkbox(c, &f.remember, "记住密码（保存在系统钥匙串）")

		label := "登录"
		switch {
		case f.loading:
			label = "登录中"
		case f.captcha != nil:
			label = "提交验证码"
		}
		btn := ui.PrimaryButton(c, "").Size(fieldWidth, 56).Radius(28).Disabled(f.loading)
		btn.Children(func() {
			ui.Icon(c, iconLogin)
			ui.Text(c, label).SingleLine()
		})
		// Pressing squeezes the button; hovering lifts it. Springs carry both.
		press := ui.Pose{}
		switch {
		case btn.Pressed():
			press = ui.Pose{Scale: 0.96}
		case btn.Hovered():
			press = ui.Pose{Y: -2, Scale: 1.02}
		}
		btn.AnimatePose(press, ui.Bouncy)
		btn.OnClick(a.submit)

		// A slot of fixed height, centered across the card, so the loader
		// neither moves the layout nor sits off to one side.
		slot := ui.Column(c).Width(fieldWidth).Height(72).Center()
		slot.Children(func() {
			if f.loading {
				shapeLoader(c, t.Accent, 56)
			}
		})

		if f.status != "" {
			ui.Text(c, f.status).FontSize(13).TextColor(t.TextMuted).TextAlign(ui.Center).Width(fieldWidth)
		}
	})
}

// captchaRow shows the school's captcha. A click on the image asks for another
// one; the code is typed beside it; 取消 drops the captcha and unlocks the form.
func (a *app) captchaRow(c *ui.Context, t *ui.Theme, fill, fillFocus ui.Color) {
	f := &a.login
	ui.Row(c).Width(fieldWidth).Gap(12).AlignItems(ui.Center).Children(func() {
		image := ui.ButtonBase(c.Key("captcha")).Size(104, 40).Radius(12).Center().
			Tooltip("点击换一张")
		image.Children(func() {
			ui.Image(c, f.captcha).Size(96, 32).Fit(ui.Contain)
		})
		if image.Clicked() {
			a.refreshCaptcha()
		}

		codeBox := ui.Column(c).Grow(1).Radius(20).Padding(10, 16)
		codeFocused := false
		codeBox.Children(func() {
			in := ui.TextInputBase(c, &f.code).Label("验证码").Placeholder("图中字符").
				Disabled(f.loading).OnSubmit(a.submit)
			codeFocused = in.Focused()
		})
		if codeFocused {
			codeBox.Border(2, t.Accent).Background(fillFocus)
		} else {
			codeBox.Border(2, ui.Transparent).Background(fill)
		}

		cancel := ui.ButtonBase(c.Key("cancel-captcha")).Size(44, 40).Radius(12).Center().
			Label("取消").Tooltip("取消验证码")
		if cancel.Hovered() {
			cancel.Background(t.SurfaceHover)
		}
		cancel.Children(func() {
			ui.Text(c, "取消").FontSize(13).TextColor(t.TextMuted)
		})
		if cancel.Clicked() {
			a.cancelCaptcha()
		}
	})
}

// submit starts a sign-in with the typed credentials, or sends the captcha
// code of the pending sign-in. It checks the form and the cooldown first, and
// sends nothing the checks reject.
func (a *app) submit() {
	f := &a.login
	f.idErr, f.pwErr, f.status = "", "", ""
	if !studentID.MatchString(f.id) {
		f.idErr = "学号应为 8 位数字"
	}
	if f.password == "" {
		f.pwErr = "请输入密码"
	}
	if f.pending != nil && f.code == "" {
		f.status = "请输入验证码"
	}
	if f.idErr != "" || f.pwErr != "" || f.status != "" {
		return
	}
	if err := session.ValidateCredentials(f.id, f.password, f.password); err != nil {
		f.pwErr = "学号或密码含全角字符，请切换到英文输入法"
		return
	}
	if wait := a.throttle.remaining(f.id, time.Now()); wait > 0 {
		f.status = fmt.Sprintf("密码错误次数过多，请 %s 后再试", formatWait(wait))
		return
	}
	acc := f.pending
	if acc == nil {
		acc = newAccount(f.id, f.password)
	}
	a.startLogin(acc, f.code)
}

// startLogin runs one sign-in step in the background and applies its outcome
// on the main thread.
func (a *app) startLogin(acc *account, code string) {
	a.login.loading = true
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		err := acc.login(ctx, code)
		a.win.Update(func() { a.finishLogin(acc, err) })
	}()
}

// finishLogin applies the outcome of one sign-in step. It runs on the main
// thread.
func (a *app) finishLogin(acc *account, err error) {
	f := &a.login
	f.loading = false
	var need captchaNeeded
	switch {
	case err == nil:
		password := f.password
		a.throttle.clear(acc.id)
		a.keepCredentials(acc.id, password)
		*f = loginForm{}
		a.signedIn(acc)
	case errors.As(err, &need):
		image, decodeErr := ui.DecodeBitmap(need.image)
		f.pending, f.captcha, f.code, f.status = nil, nil, "", ""
		if decodeErr != nil {
			log.Printf("captcha: %v", decodeErr)
			f.status = "验证码图片无法显示，请重试"
			return
		}
		f.pending, f.captcha = acc, image
		if need.rejected {
			f.status = a.countFailure(acc.id, "验证码错误")
		}
	case hasCode(err, errs.InvalidCredentials):
		f.pending, f.captcha, f.code = nil, nil, ""
		if a.settings.RememberID == acc.id {
			// The remembered password is wrong now; drop it so the next launch
			// shows the form instead of failing again.
			a.dropRemembered()
			a.saveSettings()
		}
		f.status = a.countFailure(acc.id, "学号或密码错误")
	default:
		log.Printf("sign-in failed: %v", errs.CodeOf(err))
		f.pending, f.captcha, f.code = nil, nil, ""
		f.status = signInMessage(err)
	}
}

// refreshCaptcha asks the school for a new captcha for the pending sign-in. The
// gateway answers the request with a captcha, not a sign-in, so no password is
// sent again.
func (a *app) refreshCaptcha() {
	if a.login.pending == nil || a.login.loading {
		return
	}
	a.login.code = ""
	a.startLogin(a.login.pending, "")
}

// cancelCaptcha drops the captcha and unlocks the form.
func (a *app) cancelCaptcha() {
	if a.login.loading {
		return
	}
	a.login.pending, a.login.captcha, a.login.code, a.login.status = nil, nil, "", ""
}

// countFailure counts a wrong password or captcha against id, and returns the
// status text: base, plus the wait when a cooldown starts.
func (a *app) countFailure(id, base string) string {
	cool := a.throttle.fail(id, time.Now())
	if cool == 0 {
		return base
	}
	return fmt.Sprintf("%s，请 %s 后再试", base, formatWait(cool))
}

// keepCredentials stores the password of a successful sign-in when the user
// asked to be remembered, and drops the remembered password of anyone else. The
// password goes to the credential store; settings.json keeps only the ID.
func (a *app) keepCredentials(id, password string) {
	switch {
	case a.login.remember:
		if old := a.settings.RememberID; old != "" && old != id {
			a.dropRemembered()
		}
		if err := savePassword(id, password); err != nil {
			log.Printf("credentials: save: %v", err)
			return
		}
		a.settings.RememberID = id
	case a.settings.RememberID == id:
		a.dropRemembered()
	}
	a.saveSettings()
}

// dropRemembered forgets the remembered account's password and ID. The caller
// saves the settings.
func (a *app) dropRemembered() {
	if a.settings.RememberID == "" {
		return
	}
	if err := forgetPassword(a.settings.RememberID); err != nil {
		log.Printf("credentials: forget: %v", err)
	}
	a.settings.RememberID = ""
}

// autoSignIn signs the remembered account in at launch, with the password from
// the credential store. A captcha or a failure then shows on the sign-in page.
func (a *app) autoSignIn() {
	id := a.settings.RememberID
	if id == "" {
		return
	}
	password, ok, err := loadPassword(id)
	if err != nil {
		log.Printf("credentials: load: %v", err)
		return
	}
	if !ok {
		a.dropRemembered()
		a.saveSettings()
		return
	}
	a.login.id, a.login.password, a.login.remember = id, password, true
	a.startLogin(newAccount(id, password), "")
}

// signInMessage is the text for a sign-in that failed for a reason other than a
// wrong password or captcha.
func signInMessage(err error) string {
	switch {
	case hasCode(err, errs.NonAsciiCredential):
		return "学号或密码含全角字符，请切换到英文输入法"
	case hasCode(err, errs.MaybeAttacked), hasCode(err, errs.Throttled):
		return "学校限制了登录，请稍后再试"
	case hasCode(err, errs.PasswordChangeRequired):
		return "学校要求先修改密码，请在教务系统完成修改后再登录"
	case hasCode(err, errs.Network), hasCode(err, errs.Timeout), hasCode(err, errs.TemporarilyUnavailable):
		return "网络异常或学校系统暂不可用，请稍后再试"
	default:
		return "登录失败，请稍后再试"
	}
}

// formatWait writes a cooldown for the user: seconds below a minute, minutes
// from then on, rounded up.
func formatWait(d time.Duration) string {
	if d >= time.Minute {
		return fmt.Sprintf("%d 分钟", int(math.Ceil(d.Minutes())))
	}
	return fmt.Sprintf("%d 秒", int(math.Ceil(d.Seconds())))
}
