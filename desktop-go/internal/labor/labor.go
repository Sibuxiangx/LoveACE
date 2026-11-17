// Package labor is the 劳动俱乐部 page: the labor course's progress, the activities the
// student has joined and can add, and the apply and sign-in details of each.
package labor

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/labor"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
)

// laborGoal is the number of activities the labor course asks for, as the Android
// app counts what is left.
const laborGoal = 10

// laborTone is the colour of a sign-in state, as its chip shows it.
type laborTone int

const (
	laborNeutral laborTone = iota
	laborSuccess
	laborWarning
	laborError
)

// laborAdd is the activities a student can add, in the four groups the Android app
// shows them in.
type laborAdd struct {
	available  []labor.Activity // sign-up is open and a place is left
	notStarted []labor.Activity // sign-up has not opened yet
	full       []labor.Activity // sign-up is open and no place is left
	expired    []labor.Activity // sign-up has closed, the activity has started, or its times do not read
}

// total is the number of activities in every group, as the card's count shows.
func (l laborAdd) total() int {
	return len(l.available) + len(l.notStarted) + len(l.full) + len(l.expired)
}

// groups lists the four groups in the order the page shows them.
func (l laborAdd) groups() [][]labor.Activity {
	return [][]labor.Activity{l.available, l.notStarted, l.full, l.expired}
}

// State is the 劳动俱乐部 page's data. Its reads run one after another on the
// session, and each part is applied as it finishes: the progress, the two lists, then
// each joined activity's place and sign-ins.
type State struct {
	Pending  bool
	Progress read.State[*labor.ProgressInfo]
	Joined   read.State[[]labor.Activity]
	Add      read.State[laborAdd]
	Details  map[string]read.State[*labor.ActivityDetail] // by activity ID
	Signs    map[string]read.State[[]labor.SignItem]      // by activity ID, joined ones
	Selected string                                       // the activity the detail column shows
	Applying bool                                         // an apply is in flight
	// ApplyNote is the result of the last apply, shown for the chosen activity.
	ApplyNote   string
	ApplyFailed bool
}

func (s *State) setDetail(id string, rs read.State[*labor.ActivityDetail]) {
	if s.Details == nil {
		s.Details = map[string]read.State[*labor.ActivityDetail]{}
	}
	s.Details[id] = rs
}

func (s *State) setSigns(id string, rs read.State[[]labor.SignItem]) {
	if s.Signs == nil {
		s.Signs = map[string]read.State[[]labor.SignItem]{}
	}
	s.Signs[id] = rs
}

// choose makes an activity the one the detail column shows, and clears the result of an
// apply to the activity before.
func (s *State) choose(id string) {
	s.Selected = id
	s.ApplyNote, s.ApplyFailed = "", false
}

// isJoined is whether the student has joined the activity.
func (s State) isJoined(id string) bool {
	for _, act := range s.Joined.Value() {
		if act.ID == id {
			return true
		}
	}
	return false
}

// canApply is whether the student can apply to the activity now: it is in the add list's
// 可报名 group.
func (s State) canApply(id string) bool {
	for _, act := range s.Add.Value().available {
		if act.ID == id {
			return true
		}
	}
	return false
}

// selectedActivity finds the chosen activity in the joined list or any add group.
func (s State) selectedActivity() (labor.Activity, bool) {
	for _, list := range append([][]labor.Activity{s.Joined.Value()}, s.Add.Value().groups()...) {
		for _, act := range list {
			if act.ID == s.Selected {
				return act, true
			}
		}
	}
	return labor.Activity{}, false
}

// Feature is the 劳动俱乐部 page.
type Feature struct {
	h  host.Host
	st State
}

// New is the 劳动俱乐部 page for h.
func New(h host.Host) *Feature {
	return &Feature{h: h}
}

// Snapshot is a copy of the page's data, for the other pages.
func (f *Feature) Snapshot() State {
	return f.st
}

// Reset clears the page's data, as signing out does.
func (f *Feature) Reset() {
	f.st = State{}
}

// Load reads the 劳动俱乐部 page in the background, one request at a time. A load
// already running is not started again.
func (f *Feature) Load() {
	acc := f.h.Account()
	if acc == nil || f.st.Pending {
		return
	}
	f.st.Pending = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		defer apply(func() { f.st.Pending = false })
		sv := labor.New(acc.Sess)
		now := timeutil.NowShanghai()

		progress, err := read.Retry(ctx, sv.Progress)
		apply(func() {
			f.st.Progress = read.Done(progress, read.ErrText(err))
		})

		joined, joinErr := read.Retry(ctx, sv.JoinedActivities)
		apply(func() {
			f.st.Joined = read.Done(joined, read.ErrText(joinErr))
			f.st.Details = map[string]read.State[*labor.ActivityDetail]{}
			f.st.Signs = map[string]read.State[[]labor.SignItem]{}
		})

		// Without the joined list the add list cannot leave out what is joined, so it is
		// not read.
		add, addErr := laborAdd{}, joinErr
		if joinErr == nil {
			add, addErr = readAddActivities(ctx, sv, joined, now)
		}
		apply(func() {
			f.st.Add = read.Done(add, read.ErrText(addErr))
		})

		// The place and the sign-ins of each joined activity.
		for _, act := range joined {
			detail, err := read.Retry(ctx, func(ctx context.Context) (*labor.ActivityDetail, error) {
				return sv.ActivityDetail(ctx, act.ID)
			})
			apply(func() {
				f.st.setDetail(act.ID, read.Done(detail, read.ErrText(err)))
			})
			signs, err := read.Retry(ctx, func(ctx context.Context) ([]labor.SignItem, error) {
				return sv.SignList(ctx, act.ID, 1, 1, 100)
			})
			apply(func() {
				f.st.setSigns(act.ID, read.Done(signs, read.ErrText(err)))
			})
		}
	})
}

// loadLaborDetail reads one activity's detail when it is chosen. A detail that is being
// read, or that was read, is not read again; one that failed is.
func (f *Feature) loadLaborDetail(id string) {
	acc := f.h.Account()
	if acc == nil {
		return
	}
	if rs, ok := f.st.Details[id]; ok && (!rs.Loaded() || rs.Err() == "") {
		return
	}
	f.st.setDetail(id, read.State[*labor.ActivityDetail]{})
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		detail, err := read.Retry(ctx, func(ctx context.Context) (*labor.ActivityDetail, error) {
			return labor.New(acc.Sess).ActivityDetail(ctx, id)
		})
		apply(func() {
			f.st.setDetail(id, read.Done(detail, read.ErrText(err)))
		})
	})
}

// applyLabor applies to an activity the student can join. It is a write, so it is sent
// once and never through read.Retry: a repeat could apply twice. Its result shows on the
// chosen activity, and the lists are read again.
func (f *Feature) applyLabor(id string) {
	acc := f.h.Account()
	if acc == nil || f.st.Applying {
		return
	}
	f.st.Applying = true
	f.st.ApplyNote, f.st.ApplyFailed = "", false
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		_, err := labor.New(acc.Sess).ApplyActivity(ctx, id, "")
		if err != nil {
			log.Printf("labor apply: %v", errs.CodeOf(err))
		}
		apply(func() {
			f.st.Applying = false
			f.st.ApplyFailed = err != nil
			if f.st.Selected == id {
				f.st.ApplyNote = laborApplyText(err)
			}
			f.Load()
		})
	})
}

// laborApplyText is what the student reads after an apply. The school's own message, such
// as a full activity or a closed sign-up, is shown as the school gives it. An apply whose
// result is unknown says so, since it may have gone through.
func laborApplyText(err error) string {
	if err == nil {
		return "报名成功"
	}
	var e *errs.Error
	if !errors.As(err, &e) {
		return "报名失败，请稍后再试"
	}
	switch e.Code {
	case errs.Server:
		if e.Msg != "" {
			return e.Msg
		}
	case errs.OutcomeUnknown:
		return "报名结果未知，请刷新确认是否已报名"
	case errs.Network, errs.Timeout, errs.HTTP, errs.Throttled, errs.TemporarilyUnavailable:
		return "连不上学校的教务系统，请检查网络后再试"
	case errs.InvalidCredentials, errs.AuthRequired, errs.MaybeAttacked, errs.InteractionRequired, errs.PasswordChangeRequired:
		return "学校登录已失效，请退出后重新登录"
	}
	return "报名失败，请稍后再试"
}

// readAddActivities reads every joined club's activities and sorts out the ones the
// student has not joined.
func readAddActivities(ctx context.Context, sv *labor.Service, joined []labor.Activity, now time.Time) (laborAdd, error) {
	clubs, err := read.Retry(ctx, sv.JoinedClubs)
	if err != nil {
		return laborAdd{}, err
	}
	var all []labor.Activity
	for _, club := range clubs {
		acts, err := read.Retry(ctx, func(ctx context.Context) ([]labor.Activity, error) {
			return sv.ClubActivities(ctx, club.ID, 1, 100)
		})
		if err != nil {
			return laborAdd{}, err
		}
		all = append(all, acts...)
	}
	return categorizeAdd(all, joined, now), nil
}

// categorizeAdd sorts the activities the student has not joined into the four groups the
// Android app shows them in, by the Android app's rules. An activity whose times do not
// read, whose sign-up has closed, or that has started is expired. Each activity is listed
// once, and the not-started group is in the order the sign-up opens.
func categorizeAdd(all, joined []labor.Activity, now time.Time) laborAdd {
	taken := map[string]bool{}
	for _, act := range joined {
		taken[act.ID] = true
	}
	seen := map[string]bool{}
	var out laborAdd
	for _, act := range all {
		if taken[act.ID] || seen[act.ID] {
			continue
		}
		seen[act.ID] = true
		signStart, ok1 := parseLaborTime(act.SignUpStartTime)
		signEnd, ok2 := parseLaborTime(act.SignUpEndTime)
		start, ok3 := parseLaborTime(act.StartTime)
		switch {
		case !ok1 || !ok2 || !ok3:
			out.expired = append(out.expired, act)
		case signStart.After(now):
			out.notStarted = append(out.notStarted, act)
		case signEnd.Before(now) && start.Before(now):
			out.expired = append(out.expired, act)
		case signStart.Before(now) && signEnd.After(now) && start.After(now):
			if act.MemberNum >= act.PeopleNum {
				out.full = append(out.full, act)
			} else {
				out.available = append(out.available, act)
			}
		default:
			out.expired = append(out.expired, act)
		}
	}
	sort.SliceStable(out.notStarted, func(i, j int) bool {
		from, _ := parseLaborTime(out.notStarted[i].SignUpStartTime)
		to, _ := parseLaborTime(out.notStarted[j].SignUpStartTime)
		return from.Before(to)
	})
	return out
}

// laborTimeLayouts are the forms the school writes its times in.
var laborTimeLayouts = []string{"2006-01-02 15:04:05", "2006-01-02 15:04", "2006-01-02T15:04:05"}

// parseLaborTime reads a school time, which is in Shanghai.
func parseLaborTime(s string) (time.Time, bool) {
	for _, layout := range laborTimeLayouts {
		if t, err := time.ParseInLocation(layout, strings.TrimSpace(s), timeutil.Shanghai); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// laborEnded is whether a sign-in's end time has passed. A time that does not parse has
// not passed.
func laborEnded(end string, now time.Time) bool {
	t, ok := parseLaborTime(end)
	return ok && now.After(t)
}

// laborSignSummary is the sign-in state of an activity, worded as the Android app words
// it: one sign-in reads as signed, pending, or missed once it has ended; several read as
// how many are signed.
func laborSignSummary(signs []labor.SignItem, now time.Time) (string, laborTone) {
	if len(signs) == 0 {
		return "默认签到", laborNeutral
	}
	if len(signs) == 1 {
		return laborItemStatus(signs[0], now)
	}
	signed := 0
	for _, s := range signs {
		if s.IsSign {
			signed++
		}
	}
	n := len(signs)
	switch {
	case signed == n:
		return laborCount("已完成签到", signed, n), laborSuccess
	case signed > 0:
		return laborCount("部分签到", signed, n), laborWarning
	default:
		return laborCount("未签到", signed, n), laborWarning
	}
}

// laborCount is a sign-in summary with its count, as "已完成签到 (2/2)".
func laborCount(text string, signed, n int) string {
	return fmt.Sprintf("%s (%d/%d)", text, signed, n)
}

// laborItemStatus is one sign-in: signed, missed once it has ended, or pending.
func laborItemStatus(s labor.SignItem, now time.Time) (string, laborTone) {
	switch {
	case s.IsSign:
		return "已签到", laborSuccess
	case laborEnded(s.EndTime, now):
		return "未签到", laborError
	default:
		return "待签到", laborWarning
	}
}

// laborLocation is the place of an activity: the form field the school names as its
// address, as the Android app reads it. Empty when the form has none.
func laborLocation(d *labor.ActivityDetail) string {
	if d == nil {
		return ""
	}
	for _, f := range d.FormData {
		switch f.Name {
		case "活动地址", "Location", "地点", "活动地点":
			return strings.TrimSpace(f.Value)
		}
	}
	return ""
}

// laborRange joins a start and an end time, or whichever of them is there.
func laborRange(from, to string) string {
	switch {
	case from != "" && to != "":
		return from + " 至 " + to
	case from != "":
		return from
	default:
		return to
	}
}
