package account

import "testing"

// The desktop writes to the school only when the user presses a button for it: a repair, its
// picture, an activity's sign-up. loveace-go refuses writes unless the session permits them, so
// the account's session must.
func TestNewAccountPermitsWrites(t *testing.T) {
	a := NewAccount("20240001", "pw")
	if !a.Sess.WritesAllowed() {
		t.Fatalf("the account's session refuses writes: a repair picture or a sign-up would fail before it is sent")
	}
}
