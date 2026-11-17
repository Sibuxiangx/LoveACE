package login

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"regexp"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/settings"
	"github.com/Sibuxiangx/loveace-desktop/internal/snapshot"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/session"
	"github.com/egoist/mygo/ui"
)

const (
	brandWidth = 340 // the brand pane on the left of the sign-in page
	cardWidth  = 360 // the sign-in card on the right
	fieldWidth = 296 // inside the card's padding
)

var studentID = regexp.MustCompile(`^\d{8}$`)

// Feature is the sign-in page. Its form is kept here; the signed-in account goes
// to onSignedIn, and the remembered password to the settings it shares with the
// settings page.
type Feature struct {
	h          host.Host
	th         *settings.Throttle
	st         *settings.Settings
	onSignedIn func(*account.Account)
	form       loginForm

	// The saved timetables, read from the disk, and the one on show.
	snaps       []snapshot.Entry
	viewing     bool
	snapAccount string
	snapTerm    string
	copied      bool
}

// New makes the sign-in page. st is the settings the app shares: a successful
// sign-in with 记住密码 saves the ID there, and a wrong remembered password drops it.
func New(h host.Host, th *settings.Throttle, st *settings.Settings, onSignedIn func(*account.Account)) *Feature {
	return &Feature{h: h, th: th, st: st, onSignedIn: onSignedIn}
}

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
	pending              *account.Account
}

// Reset clears the form and the snapshot view, and reads the saved timetables again. The
// shell calls it on sign-out.
func (f *Feature) Reset() {
	f.form = loginForm{}
	f.viewing = false
	f.reloadSnapshots()
}

// AutoSignIn signs the remembered account in at launch, with the password from the
// credential store. A captcha or a failure then shows on the sign-in page. The saved
// timetables are read first: they are offered even when no sign-in starts.
func (f *Feature) AutoSignIn() {
	f.reloadSnapshots()
	id := f.st.RememberID
	if id == "" {
		return
	}
	password, ok, err := account.LoadPassword(id)
	if err != nil {
		log.Printf("credentials: load: %v", err)
		return
	}
	if !ok {
		f.st.DropRemembered()
		f.st.Persist()
		return
	}
	fm := &f.form
	fm.id, fm.password, fm.remember = id, password, true
	f.startLogin(account.NewAccount(id, password), "")
}

// View draws the sign-in page.
func (f *Feature) View(c *ui.Context, t *ui.Theme) {
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
			p.FillPath(design.Cookie(r.X+r.W*0.86, r.Y+r.H*0.9, 130, 10, 8), tonal)
		})
		brand.Children(func() {
			design.DragStrip(c)
			// The app's icon, as Android's login screen shows its logo. It lifts
			// while the pointer rests on it.
			logo := ui.Image(c, design.AppIcon).Size(72, 72).Fit(ui.Contain).Radius(20)
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
			ui.Box(c).Height(design.TitleBarHeight).Shrink(0).DragWindow()
			ui.Column(c).Grow(1).Center().Children(func() {
				if f.viewing {
					f.snapshotCard(c, t)
				} else {
					f.card(c, t, fill, fillFocus)
				}
			})
		})
	})
}

// card is the form: the fields, the captcha when the school asks for one, the
// button and the loader of the wait. It rises and fades in on first show.
func (f *Feature) card(c *ui.Context, t *ui.Theme, fill, fillFocus ui.Color) {
	fm := &f.form
	locked := fm.loading || fm.pending != nil
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
				ui.Icon(c, design.IconPerson).TextColor(t.TextMuted)
				in := ui.TextInputBase(c, &fm.id).Label("学号").Placeholder("8 位学号").
					Disabled(locked).Width(fieldWidth - 56)
				idFocused = in.Focused()
			})
		})
		switch {
		case fm.idErr != "":
			idBox.Border(2, t.Danger).Background(fill)
		case idFocused:
			idBox.Border(2, t.Accent).Background(fillFocus)
		default:
			idBox.Border(2, ui.Transparent).Background(fill)
		}
		if fm.idErr != "" {
			ui.Text(c, fm.idErr).FontSize(12).TextColor(t.Danger)
		}

		pwBox := ui.Column(c).Width(fieldWidth).Radius(20).Padding(10, 16)
		pwFocused := false
		pwBox.Children(func() {
			ui.Row(c).Height(32).Gap(12).AlignItems(ui.Center).Children(func() {
				ui.Icon(c, design.IconLock).TextColor(t.TextMuted)
				in := ui.TextInputBase(c, &fm.password).Label("密码").Placeholder("教务系统密码").
					Disabled(locked).Width(fieldWidth - 96).OnSubmit(f.submit)
				if !fm.showPwd {
					// Password hides the text in the frames that call it: an
					// eye button that shows it simply stops calling it.
					in.Password()
				}
				pwFocused = in.Focused()
				eye := ui.ButtonBase(c.Key("eye")).Size(32, 32).Radius(16).Center().
					Label(map[bool]string{true: "隐藏密码", false: "显示密码"}[fm.showPwd]).
					Tooltip(map[bool]string{true: "隐藏密码", false: "显示密码"}[fm.showPwd])
				if eye.Hovered() {
					eye.Background(t.SurfaceHover)
				}
				eye.Children(func() {
					if fm.showPwd {
						ui.Icon(c, design.IconVisibilityOff).TextColor(t.TextMuted)
					} else {
						ui.Icon(c, design.IconVisibility).TextColor(t.TextMuted)
					}
				})
				if eye.Clicked() {
					fm.showPwd = !fm.showPwd
				}
			})
		})
		switch {
		case fm.pwErr != "":
			pwBox.Border(2, t.Danger).Background(fill)
		case pwFocused:
			pwBox.Border(2, t.Accent).Background(fillFocus)
		default:
			pwBox.Border(2, ui.Transparent).Background(fill)
		}
		if fm.pwErr != "" {
			ui.Text(c, fm.pwErr).FontSize(12).TextColor(t.Danger)
		}

		if fm.captcha != nil {
			f.captchaRow(c, t, fill, fillFocus)
		}

		ui.Checkbox(c, &fm.remember, "记住密码（保存在系统钥匙串）")

		label := "登录"
		switch {
		case fm.loading:
			label = "登录中"
		case fm.captcha != nil:
			label = "提交验证码"
		}
		btn := ui.PrimaryButton(c, "").Size(fieldWidth, 56).Radius(28).Disabled(fm.loading)
		btn.Children(func() {
			ui.Icon(c, design.IconLogin)
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
		btn.OnClick(f.submit)

		// A slot of fixed height, centered across the card, so the loader
		// neither moves the layout nor sits off to one side.
		slot := ui.Column(c).Width(fieldWidth).Height(72).Center()
		slot.Children(func() {
			if fm.loading {
				design.ShapeLoader(c, t.Accent, 56)
			}
		})

		if fm.status != "" {
			ui.Text(c, fm.status).FontSize(13).TextColor(t.TextMuted).TextAlign(ui.Center).Width(fieldWidth)
		}

		if len(f.snaps) > 0 {
			open := ui.ButtonBase(c.Key("open-snapshot")).Width(fieldWidth).Height(44).Radius(22).Center()
			if open.Hovered() {
				open.Background(t.SurfaceHover)
			}
			open.Children(func() {
				ui.Text(c, "查看选课快照（离线）").FontSize(14).TextColor(t.Accent)
			})
			if open.Clicked() {
				f.openSnapshots()
			}
		}
	})
}

// captchaRow shows the school's captcha. A click on the image asks for another
// one; the code is typed beside it; 取消 drops the captcha and unlocks the form.
func (f *Feature) captchaRow(c *ui.Context, t *ui.Theme, fill, fillFocus ui.Color) {
	fm := &f.form
	ui.Row(c).Width(fieldWidth).Gap(12).AlignItems(ui.Center).Children(func() {
		image := ui.ButtonBase(c.Key("captcha")).Size(104, 40).Radius(12).Center().
			Tooltip("点击换一张")
		image.Children(func() {
			ui.Image(c, fm.captcha).Size(96, 32).Fit(ui.Contain)
		})
		if image.Clicked() {
			f.refreshCaptcha()
		}

		codeBox := ui.Column(c).Grow(1).Radius(20).Padding(10, 16)
		codeFocused := false
		codeBox.Children(func() {
			in := ui.TextInputBase(c, &fm.code).Label("验证码").Placeholder("图中字符").
				Disabled(fm.loading).OnSubmit(f.submit)
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
			f.cancelCaptcha()
		}
	})
}

// submit starts a sign-in with the typed credentials, or sends the captcha
// code of the pending sign-in. It checks the form and the cooldown first, and
// sends nothing the checks reject.
func (f *Feature) submit() {
	fm := &f.form
	fm.idErr, fm.pwErr, fm.status = "", "", ""
	if !studentID.MatchString(fm.id) {
		fm.idErr = "学号应为 8 位数字"
	}
	if fm.password == "" {
		fm.pwErr = "请输入密码"
	}
	if fm.pending != nil && fm.code == "" {
		fm.status = "请输入验证码"
	}
	if fm.idErr != "" || fm.pwErr != "" || fm.status != "" {
		return
	}
	if err := session.ValidateCredentials(fm.id, fm.password, fm.password); err != nil {
		fm.pwErr = "学号或密码含全角字符，请切换到英文输入法"
		return
	}
	if wait := f.th.Remaining(fm.id, time.Now()); wait > 0 {
		fm.status = fmt.Sprintf("密码错误次数过多，请 %s 后再试", formatWait(wait))
		return
	}
	acc := fm.pending
	if acc == nil {
		acc = account.NewAccount(fm.id, fm.password)
	}
	f.startLogin(acc, fm.code)
}

// startLogin runs one sign-in step in the background and applies its outcome
// on the main thread.
func (f *Feature) startLogin(acc *account.Account, code string) {
	f.form.loading = true
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		err := acc.Login(ctx, code)
		f.h.Update(func() { f.finishLogin(acc, err) })
	}()
}

// finishLogin applies the outcome of one sign-in step. It runs on the main
// thread.
func (f *Feature) finishLogin(acc *account.Account, err error) {
	fm := &f.form
	fm.loading = false
	var need account.CaptchaNeeded
	switch {
	case err == nil:
		password := fm.password
		f.th.Clear(acc.ID)
		f.keepCredentials(acc.ID, password)
		*fm = loginForm{}
		f.onSignedIn(acc)
	case errors.As(err, &need):
		image, decodeErr := ui.DecodeBitmap(need.Image)
		fm.pending, fm.captcha, fm.code, fm.status = nil, nil, "", ""
		if decodeErr != nil {
			log.Printf("captcha: %v", decodeErr)
			fm.status = "验证码图片无法显示，请重试"
			return
		}
		fm.pending, fm.captcha = acc, image
		if need.Rejected {
			fm.status = f.countFailure(acc.ID, "验证码错误")
		}
	case account.HasCode(err, errs.InvalidCredentials):
		fm.pending, fm.captcha, fm.code = nil, nil, ""
		if f.st.RememberID == acc.ID {
			// The remembered password is wrong now; drop it so the next launch
			// shows the form instead of failing again.
			f.st.DropRemembered()
			f.st.Persist()
		}
		fm.status = f.countFailure(acc.ID, "学号或密码错误")
	default:
		log.Printf("sign-in failed: %v", errs.CodeOf(err))
		fm.pending, fm.captcha, fm.code = nil, nil, ""
		fm.status = signInMessage(err)
	}
}

// refreshCaptcha asks the school for a new captcha for the pending sign-in. The
// gateway answers the request with a captcha, not a sign-in, so no password is
// sent again.
func (f *Feature) refreshCaptcha() {
	if f.form.pending == nil || f.form.loading {
		return
	}
	f.form.code = ""
	f.startLogin(f.form.pending, "")
}

// cancelCaptcha drops the captcha and unlocks the form.
func (f *Feature) cancelCaptcha() {
	if f.form.loading {
		return
	}
	f.form.pending, f.form.captcha, f.form.code, f.form.status = nil, nil, "", ""
}

// countFailure counts a wrong password or captcha against id, and returns the
// status text: base, plus the wait when a cooldown starts.
func (f *Feature) countFailure(id, base string) string {
	cool := f.th.Fail(id, time.Now())
	if cool == 0 {
		return base
	}
	return fmt.Sprintf("%s，请 %s 后再试", base, formatWait(cool))
}

// keepCredentials stores the password of a successful sign-in when the user
// asked to be remembered, and drops the remembered password of anyone else. The
// password goes to the credential store; settings.json keeps only the ID.
func (f *Feature) keepCredentials(id, password string) {
	switch {
	case f.form.remember:
		if old := f.st.RememberID; old != "" && old != id {
			f.st.DropRemembered()
		}
		if err := account.SavePassword(id, password); err != nil {
			log.Printf("credentials: save: %v", err)
			return
		}
		f.st.RememberID = id
	case f.st.RememberID == id:
		f.st.DropRemembered()
	}
	f.st.Persist()
}

// signInMessage is the text for a sign-in that failed for a reason other than a
// wrong password or captcha.
func signInMessage(err error) string {
	switch {
	case account.HasCode(err, errs.NonAsciiCredential):
		return "学号或密码含全角字符，请切换到英文输入法"
	case account.HasCode(err, errs.MaybeAttacked), account.HasCode(err, errs.Throttled):
		return "学校限制了登录，请稍后再试"
	case account.HasCode(err, errs.PasswordChangeRequired):
		return "学校要求先修改密码，请在教务系统完成修改后再登录"
	case account.HasCode(err, errs.Network), account.HasCode(err, errs.Timeout), account.HasCode(err, errs.TemporarilyUnavailable):
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
