package settings

import (
	"errors"
	"testing"

	portalsvc "github.com/Sibuxiangx/loveace-go/core/services/portal"
)

// A read that lands after the page was left is dropped: the password does not come back.
func TestMailResultAfterLeaveIsDropped(t *testing.T) {
	p := &Page{}
	p.mail.gen = 1
	p.mail.loading = true
	p.Leave()

	p.takeMail(1, &portalsvc.MailInitialPassword{Password: "x"}, nil)

	if p.mail.loaded || p.mail.got != nil {
		t.Fatal("a read from before the page was left landed")
	}
}

// Leaving the page forgets a password that was on screen, and moves the generation on.
func TestLeaveForgetsThePassword(t *testing.T) {
	p := &Page{}
	p.takeMail(p.mail.gen, &portalsvc.MailInitialPassword{LoginID: "id", Password: "x"}, nil)
	p.mail.shown = true
	before := p.mail.gen

	p.Leave()

	if p.mail.loaded || p.mail.got != nil || p.mail.shown {
		t.Fatal("the password was not forgotten when the page was left")
	}
	if p.mail.gen != before+1 {
		t.Fatalf("generation did not move on: %d -> %d", before, p.mail.gen)
	}
}

// A failed read shows its wording and keeps no password.
func TestFailedMailReadKeepsNoPassword(t *testing.T) {
	p := &Page{}
	p.mail.loading = true

	p.takeMail(p.mail.gen, nil, errors.New("boom"))

	if p.mail.loading || p.mail.loaded || p.mail.got != nil {
		t.Fatal("a failed read left the page loading or holding a password")
	}
	if p.mail.err == "" {
		t.Fatal("the failure was not shown")
	}
}
