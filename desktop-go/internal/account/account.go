package account

import (
	"context"
	"errors"

	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/Sibuxiangx/loveace-go/core/session"
	"github.com/Sibuxiangx/loveace-go/core/transport"
	"github.com/egoist/mygo"
)

// Account is one school session: the sign-in through the school's gateway and
// identity provider, and the JWC reads made over it. The password is kept only
// here and, when remembered, in the system's credential store.
type Account struct {
	ID   string
	Sess *session.Session
	Jwc  *jwc.Service
}

// CaptchaNeeded is what login returns when the gateway asks for a captcha.
// image is the captcha (a GIF); rejected says the code just sent was wrong.
type CaptchaNeeded struct {
	Image    []byte
	Rejected bool
}

func (CaptchaNeeded) Error() string { return "the school asks for a captcha" }

// NewAccount prepares a session for a student. The school is reached directly,
// with no proxy.
func NewAccount(id, password string) *Account {
	// The session permits writes. The app writes only when the user presses a button for it:
	// submitting or uploading a repair, applying for an activity.
	cfg := session.DefaultConfig()
	cfg.AllowWrites = true
	s := session.NewWithConfig(id, password, password, transport.NewHTTPTransport(6), cfg)
	return &Account{ID: id, Sess: s, Jwc: jwc.New(s)}
}

// Login signs the account in. With code empty it runs the whole sign-in, and
// when the gateway asks for a captcha it returns captchaNeeded. With code set
// it answers the captcha that the last captchaNeeded asked for.
func (a *Account) Login(ctx context.Context, code string) error {
	if code == "" {
		err := a.Sess.Login(ctx)
		if !HasCode(err, errs.InteractionRequired) {
			return err
		}
		return a.FetchCaptcha(ctx, false)
	}
	st := a.Sess.ECLoginWithCaptcha(ctx, code)
	switch st.Outcome {
	case session.ECSuccess:
		return a.Sess.CompleteCaptchaLogin(ctx)
	case session.ECCaptchaInvalid:
		return a.FetchCaptcha(ctx, true)
	case session.ECCaptchaRequired:
		return a.FetchCaptcha(ctx, false)
	case session.ECInvalidCredentials:
		return errs.NewInvalidCredentials()
	case session.ECMaybeAttacked:
		return errs.NewMaybeAttacked()
	case session.ECNetworkError:
		return errs.NewNetwork("gateway unreachable")
	default:
		return errs.NewTemporarilyUnavailable("gateway login failed: " + string(st.Outcome))
	}
}

// FetchCaptcha asks the gateway for its captcha. If the gateway no longer asks
// for one, it returns the sign-in's own error, and the caller sends the user
// to sign in again.
func (a *Account) FetchCaptcha(ctx context.Context, rejected bool) error {
	c, err := a.Sess.EcCaptcha(ctx)
	if err != nil {
		return err
	}
	if !c.Required {
		return a.Sess.Login(ctx)
	}
	return CaptchaNeeded{Image: c.Image, Rejected: rejected}
}

// HasCode reports whether err is a session error with the given code.
func HasCode(err error, code errs.Code) bool {
	var e *errs.Error
	return errors.As(err, &e) && e.Code == code
}

// The school password is kept in the system's credential store, under the key
// "school-password:<student ID>".
const secretPrefix = "school-password:"

// SavePassword stores the password of id in the credential store.
func SavePassword(id, password string) error {
	return mygo.Secrets.Set(secretPrefix+id, []byte(password))
}

// LoadPassword returns the password of id, and false when none is stored.
func LoadPassword(id string) (string, bool, error) {
	b, err := mygo.Secrets.Get(secretPrefix + id)
	if errors.Is(err, mygo.ErrSecretNotFound) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return string(b), true, nil
}

// ForgetPassword removes the stored password of id. Removing one that is not
// there is not an error.
func ForgetPassword(id string) error {
	err := mygo.Secrets.Delete(secretPrefix + id)
	if errors.Is(err, mygo.ErrSecretNotFound) {
		return nil
	}
	return err
}
