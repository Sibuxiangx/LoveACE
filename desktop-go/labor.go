package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

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

// laborState is the 劳动俱乐部 page's data. Its reads run one after another on the
// session, and each part is applied as it finishes: the progress, the two lists, then
// each joined activity's place and sign-ins.
type laborState struct {
	pending  bool
	progress readState[*labor.ProgressInfo]
	joined   readState[[]labor.Activity]
	add      readState[laborAdd]
	details  map[string]readState[*labor.ActivityDetail] // by activity ID
	signs    map[string]readState[[]labor.SignItem]      // by activity ID, joined ones
	selected string                                      // the activity the detail column shows
	applying bool                                        // an apply is in flight
	// applyNote is the result of the last apply, shown for the chosen activity.
	applyNote   string
	applyFailed bool
}

func (s *laborState) setDetail(id string, rs readState[*labor.ActivityDetail]) {
	if s.details == nil {
		s.details = map[string]readState[*labor.ActivityDetail]{}
	}
	s.details[id] = rs
}

func (s *laborState) setSigns(id string, rs readState[[]labor.SignItem]) {
	if s.signs == nil {
		s.signs = map[string]readState[[]labor.SignItem]{}
	}
	s.signs[id] = rs
}

// choose makes an activity the one the detail column shows, and clears the result of an
// apply to the activity before.
func (s *laborState) choose(id string) {
	s.selected = id
	s.applyNote, s.applyFailed = "", false
}

// isJoined is whether the student has joined the activity.
func (s laborState) isJoined(id string) bool {
	for _, act := range s.joined.v {
		if act.ID == id {
			return true
		}
	}
	return false
}

// canApply is whether the student can apply to the activity now: it is in the add list's
// 可报名 group.
func (s laborState) canApply(id string) bool {
	for _, act := range s.add.v.available {
		if act.ID == id {
			return true
		}
	}
	return false
}

// selectedActivity finds the chosen activity in the joined list or any add group.
func (s laborState) selectedActivity() (labor.Activity, bool) {
	for _, list := range append([][]labor.Activity{s.joined.v}, s.add.v.groups()...) {
		for _, act := range list {
			if act.ID == s.selected {
				return act, true
			}
		}
	}
	return labor.Activity{}, false
}

// loadLabor reads the 劳动俱乐部 page in the background, one request at a time. A load
// already running is not started again.
func (a *app) loadLabor() {
	if a.acc == nil || a.labor.pending {
		return
	}
	acc := a.acc
	a.labor.pending = true
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		defer apply(func(x *app) { x.labor.pending = false })
		sv := labor.New(acc.sess)
		now := timeutil.NowShanghai()

		progress, err := readRetry(ctx, sv.Progress)
		apply(func(x *app) {
			x.labor.progress = readState[*labor.ProgressInfo]{loaded: true, err: readErrText(err), v: progress}
		})

		joined, joinErr := readRetry(ctx, sv.JoinedActivities)
		apply(func(x *app) {
			x.labor.joined = readState[[]labor.Activity]{loaded: true, err: readErrText(joinErr), v: joined}
			x.labor.details = map[string]readState[*labor.ActivityDetail]{}
			x.labor.signs = map[string]readState[[]labor.SignItem]{}
		})

		// Without the joined list the add list cannot leave out what is joined, so it is
		// not read.
		add, addErr := laborAdd{}, joinErr
		if joinErr == nil {
			add, addErr = readAddActivities(ctx, sv, joined, now)
		}
		apply(func(x *app) {
			x.labor.add = readState[laborAdd]{loaded: true, err: readErrText(addErr), v: add}
		})

		// The place and the sign-ins of each joined activity.
		for _, act := range joined {
			detail, err := readRetry(ctx, func(ctx context.Context) (*labor.ActivityDetail, error) {
				return sv.ActivityDetail(ctx, act.ID)
			})
			apply(func(x *app) {
				x.labor.setDetail(act.ID, readState[*labor.ActivityDetail]{loaded: true, err: readErrText(err), v: detail})
			})
			signs, err := readRetry(ctx, func(ctx context.Context) ([]labor.SignItem, error) {
				return sv.SignList(ctx, act.ID, 1, 1, 100)
			})
			apply(func(x *app) {
				x.labor.setSigns(act.ID, readState[[]labor.SignItem]{loaded: true, err: readErrText(err), v: signs})
			})
		}
	})
}

// loadLaborDetail reads one activity's detail when it is chosen. A detail that is being
// read, or that was read, is not read again; one that failed is.
func (a *app) loadLaborDetail(id string) {
	if a.acc == nil {
		return
	}
	if rs, ok := a.labor.details[id]; ok && (!rs.loaded || rs.err == "") {
		return
	}
	acc := a.acc
	a.labor.setDetail(id, readState[*labor.ActivityDetail]{})
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		detail, err := readRetry(ctx, func(ctx context.Context) (*labor.ActivityDetail, error) {
			return labor.New(acc.sess).ActivityDetail(ctx, id)
		})
		apply(func(x *app) {
			x.labor.setDetail(id, readState[*labor.ActivityDetail]{loaded: true, err: readErrText(err), v: detail})
		})
	})
}

// applyLabor applies to an activity the student can join. It is a write, so it is sent
// once and never through readRetry: a repeat could apply twice. Its result shows on the
// chosen activity, and the lists are read again.
func (a *app) applyLabor(id string) {
	if a.acc == nil || a.labor.applying {
		return
	}
	acc := a.acc
	a.labor.applying = true
	a.labor.applyNote, a.labor.applyFailed = "", false
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		_, err := labor.New(acc.sess).ApplyActivity(ctx, id, "")
		if err != nil {
			log.Printf("labor apply: %v", errs.CodeOf(err))
		}
		apply(func(x *app) {
			x.labor.applying = false
			x.labor.applyFailed = err != nil
			if x.labor.selected == id {
				x.labor.applyNote = laborApplyText(err)
			}
			x.loadLabor()
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
	clubs, err := readRetry(ctx, sv.JoinedClubs)
	if err != nil {
		return laborAdd{}, err
	}
	var all []labor.Activity
	for _, club := range clubs {
		acts, err := readRetry(ctx, func(ctx context.Context) ([]labor.Activity, error) {
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
