package main

import (
	"errors"
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/labor"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
)

// laborNow is a moment between the sign-up windows the tests use.
var laborNow = time.Date(2026, 11, 17, 12, 0, 0, 0, timeutil.Shanghai)

func laborAct(id, signStart, signEnd, start string, member, people int64) labor.Activity {
	return labor.Activity{
		ID: id, SignUpStartTime: signStart, SignUpEndTime: signEnd, StartTime: start,
		MemberNum: member, PeopleNum: people,
	}
}

func laborIDs(acts []labor.Activity) []string {
	ids := make([]string, 0, len(acts))
	for _, act := range acts {
		ids = append(ids, act.ID)
	}
	return ids
}

func sameIDs(got []labor.Activity, want []string) bool {
	ids := laborIDs(got)
	if len(ids) != len(want) {
		return false
	}
	for i := range ids {
		if ids[i] != want[i] {
			return false
		}
	}
	return true
}

// The add card's four groups follow the Android app's rules. An activity the student has
// joined is in none of them, and each activity is listed once.
func TestCategorizeAdd(t *testing.T) {
	const (
		signOpen  = "2026-11-10 08:00:00"
		signClose = "2026-11-20 18:00:00"
		start     = "2026-11-25 14:00:00"
	)
	joined := laborAct("joined", signOpen, signClose, start, 3, 10)
	all := []labor.Activity{
		laborAct("available", signOpen, signClose, start, 3, 10),
		laborAct("full", signOpen, signClose, start, 10, 10),
		laborAct("nsLate", "2026-11-19 08:00:00", signClose, start, 3, 10),
		laborAct("nsEarly", "2026-11-18 08:00:00", signClose, start, 3, 10),
		laborAct("signEnded", signOpen, "2026-11-16 18:00:00", start, 3, 10),
		laborAct("activityStarted", signOpen, signClose, "2026-11-16 09:00:00", 3, 10),
		laborAct("broken", "坏时间", signClose, start, 3, 10),
		joined,
	}
	got := categorizeAdd(all, []labor.Activity{joined}, laborNow)
	checks := []struct {
		name string
		got  []labor.Activity
		want []string
	}{
		{"可报名", got.available, []string{"available"}},
		{"未开始报名, earliest sign-up first", got.notStarted, []string{"nsEarly", "nsLate"}},
		{"已满员", got.full, []string{"full"}},
		{"已过期", got.expired, []string{"signEnded", "activityStarted", "broken"}},
	}
	for _, c := range checks {
		if !sameIDs(c.got, c.want) {
			t.Errorf("%s = %v, want %v", c.name, laborIDs(c.got), c.want)
		}
	}
	if total := got.total(); total != 7 {
		t.Errorf("total = %d, want 7 (joined excluded)", total)
	}
}

// Only an activity in the 可报名 group can be applied to from the page.
func TestLaborCanApply(t *testing.T) {
	s := laborState{add: readState[laborAdd]{loaded: true, v: laborAdd{
		available: []labor.Activity{{ID: "open"}},
		full:      []labor.Activity{{ID: "full"}},
	}}}
	if !s.canApply("open") {
		t.Error("open activity: canApply = false, want true")
	}
	if s.canApply("full") {
		t.Error("full activity: canApply = true, want false")
	}
	if s.canApply("gone") {
		t.Error("unknown activity: canApply = true, want false")
	}
}

// The result of an apply is the school's own words when it gives some, and says a
// possibly-applied result is unknown rather than failed.
func TestLaborApplyText(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want string
	}{
		{"applied", nil, "报名成功"},
		{"school says full", errs.NewServer(1, "人数已满"), "人数已满"},
		{"result unknown", errs.NewOutcomeUnknown("write outcome uncertain"), "报名结果未知，请刷新确认是否已报名"},
		{"network", errs.NewNetwork("down"), "连不上学校的教务系统，请检查网络后再试"},
		{"login gone", errs.NewInvalidCredentials(), "学校登录已失效，请退出后重新登录"},
		{"other", errors.New("boom"), "报名失败，请稍后再试"},
	}
	for _, c := range cases {
		if got := laborApplyText(c.err); got != c.want {
			t.Errorf("%s: laborApplyText = %q, want %q", c.name, got, c.want)
		}
	}
}

// The sign-in state reads as the Android app reads it, with its tone.
func TestLaborSignSummary(t *testing.T) {
	const ended, future = "2026-11-16 18:00:00", "2026-11-17 18:00:00"
	cases := []struct {
		name  string
		signs []labor.SignItem
		text  string
		tone  laborTone
	}{
		{"no sign-in items", nil, "默认签到", laborNeutral},
		{"one signed", []labor.SignItem{{IsSign: true, EndTime: future}}, "已签到", laborSuccess},
		{"one missed after its end", []labor.SignItem{{EndTime: ended}}, "未签到", laborError},
		{"one still open", []labor.SignItem{{EndTime: future}}, "待签到", laborWarning},
		{"all signed", []labor.SignItem{{IsSign: true}, {IsSign: true}}, "已完成签到 (2/2)", laborSuccess},
		{"some signed", []labor.SignItem{{IsSign: true}, {}}, "部分签到 (1/2)", laborWarning},
		{"none signed", []labor.SignItem{{}, {}}, "未签到 (0/2)", laborWarning},
	}
	for _, c := range cases {
		text, tone := laborSignSummary(c.signs, laborNow)
		if text != c.text || tone != c.tone {
			t.Errorf("%s: got (%q, %v), want (%q, %v)", c.name, text, tone, c.text, c.tone)
		}
	}
}

// The place is the form field the school names as the address; none when the form has no
// such field.
func TestLaborLocation(t *testing.T) {
	d := &labor.ActivityDetail{FormData: []labor.FormField{
		{Name: "备注", Value: "带水杯"},
		{Name: "活动地址", Value: " 通慧楼 XJTH3-205 "},
	}}
	if got := laborLocation(d); got != "通慧楼 XJTH3-205" {
		t.Errorf("laborLocation = %q, want %q", got, "通慧楼 XJTH3-205")
	}
	none := &labor.ActivityDetail{FormData: []labor.FormField{{Name: "备注", Value: "带水杯"}}}
	if got := laborLocation(none); got != "" {
		t.Errorf("laborLocation without a place field = %q, want empty", got)
	}
	if got := laborLocation(nil); got != "" {
		t.Errorf("laborLocation(nil) = %q, want empty", got)
	}
}
