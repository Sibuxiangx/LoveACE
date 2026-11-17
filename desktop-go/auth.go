package main

import (
	"context"
	"errors"

	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/Sibuxiangx/loveace-go/core/session"
	"github.com/Sibuxiangx/loveace-go/core/transport"
	"github.com/egoist/mygo"
)

// account is one school session: the sign-in through the school's gateway and
// identity provider, and the JWC reads made over it. The password is kept only
// here and, when remembered, in the system's credential store.
type account struct {
	id   string
	sess *session.Session
	jwc  *jwc.Service
}

// captchaNeeded is what login returns when the gateway asks for a captcha.
// image is the captcha (a GIF); rejected says the code just sent was wrong.
type captchaNeeded struct {
	image    []byte
	rejected bool
}

func (captchaNeeded) Error() string { return "the school asks for a captcha" }

// newAccount prepares a session for a student. The school is reached directly,
// with no proxy.
func newAccount(id, password string) *account {
	s := session.New(id, password, password, transport.NewHTTPTransport(6))
	return &account{id: id, sess: s, jwc: jwc.New(s)}
}

// login signs the account in. With code empty it runs the whole sign-in, and
// when the gateway asks for a captcha it returns captchaNeeded. With code set
// it answers the captcha that the last captchaNeeded asked for.
func (a *account) login(ctx context.Context, code string) error {
	if code == "" {
		err := a.sess.Login(ctx)
		if !hasCode(err, errs.InteractionRequired) {
			return err
		}
		return a.fetchCaptcha(ctx, false)
	}
	st := a.sess.ECLoginWithCaptcha(ctx, code)
	switch st.Outcome {
	case session.ECSuccess:
		return a.sess.CompleteCaptchaLogin(ctx)
	case session.ECCaptchaInvalid:
		return a.fetchCaptcha(ctx, true)
	case session.ECCaptchaRequired:
		return a.fetchCaptcha(ctx, false)
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

// fetchCaptcha asks the gateway for its captcha. If the gateway no longer asks
// for one, it returns the sign-in's own error, and the caller sends the user
// to sign in again.
func (a *account) fetchCaptcha(ctx context.Context, rejected bool) error {
	c, err := a.sess.EcCaptcha(ctx)
	if err != nil {
		return err
	}
	if !c.Required {
		return a.sess.Login(ctx)
	}
	return captchaNeeded{image: c.Image, rejected: rejected}
}

// hasCode reports whether err is a session error with the given code.
func hasCode(err error, code errs.Code) bool {
	var e *errs.Error
	return errors.As(err, &e) && e.Code == code
}

// The school password is kept in the system's credential store, under the key
// "school-password:<student ID>".
const secretPrefix = "school-password:"

// savePassword stores the password of id in the credential store.
func savePassword(id, password string) error {
	return mygo.Secrets.Set(secretPrefix+id, []byte(password))
}

// loadPassword returns the password of id, and false when none is stored.
func loadPassword(id string) (string, bool, error) {
	b, err := mygo.Secrets.Get(secretPrefix + id)
	if errors.Is(err, mygo.ErrSecretNotFound) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return string(b), true, nil
}

// forgetPassword removes the stored password of id. Removing one that is not
// there is not an error.
func forgetPassword(id string) error {
	err := mygo.Secrets.Delete(secretPrefix + id)
	if errors.Is(err, mygo.ErrSecretNotFound) {
		return nil
	}
	return err
}
