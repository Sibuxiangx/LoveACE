package repair

import (
	"strings"
	"testing"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	repairsvc "github.com/Sibuxiangx/loveace-go/core/services/repair"
)

// fakeHost has no account, so the page starts no read.
type fakeHost struct{}

func (fakeHost) Account() *account.Account { return nil }
func (fakeHost) Update(fn func())          { fn() }
func (fakeHost) Open(host.Page)            {}

// formData is the school's form with one area and one project, as the form gives them.
var formData = repairsvc.FormData{
	Areas:    []repairsvc.Group{{GroupName: "宿舍", Items: []repairsvc.Item{{ItemID: "a1", Name: "明德楼"}}}},
	Projects: []repairsvc.Group{{GroupName: "水电", Items: []repairsvc.Item{{ItemID: "p1", Name: "水龙头"}}}},
}

func completeDraft() Draft {
	return Draft{Area: "a1", Project: "p1", Phone: "13800000000", Address: "301", Description: "漏水"}
}

func TestDraftRequestSendsACompleteReport(t *testing.T) {
	req, missing := completeDraft().request(formData)
	if missing != "" {
		t.Fatalf("complete draft reported missing %q", missing)
	}
	if req.AreaName != "明德楼" || req.ProjectName != "水龙头" || req.Phone != "13800000000" {
		t.Fatalf("request = %+v", req)
	}
}

func TestDraftRequestNamesWhatIsMissing(t *testing.T) {
	cases := []struct {
		name string
		edit func(d *Draft)
		want string
	}{
		{"no area", func(d *Draft) { d.Area = "" }, "请选择故障区域"},
		{"unknown area", func(d *Draft) { d.Area = "zz" }, "请选择故障区域"},
		{"no project", func(d *Draft) { d.Project = "" }, "请选择维修项目"},
		{"no phone", func(d *Draft) { d.Phone = "  " }, "请填写联系电话"},
		{"long phone", func(d *Draft) { d.Phone = "138000000001" }, "联系电话最多 11 位"},
		{"no address", func(d *Draft) { d.Address = "" }, "请填写故障的详细地址"},
		{"no description", func(d *Draft) { d.Description = "" }, "请填写故障详情"},
		{"long description", func(d *Draft) { d.Description = strings.Repeat("字", 201) }, "故障详情最多 200 字"},
	}
	for _, tc := range cases {
		d := completeDraft()
		tc.edit(&d)
		req, missing := d.request(formData)
		if req != nil || missing != tc.want {
			t.Errorf("%s: missing %q (request nil %v), want %q", tc.name, missing, req == nil, tc.want)
		}
	}
}

func TestDescriptionLimitCountsCharacters(t *testing.T) {
	d := completeDraft()
	d.Description = strings.Repeat("字", 200)
	if _, missing := d.request(formData); missing != "" {
		t.Fatalf("200 characters reported %q", missing)
	}
}

func TestSubmitTextTellsAnUnknownOutcomeToCheckFirst(t *testing.T) {
	got := SubmitText(errs.NewOutcomeUnknown("connection lost"))
	if !strings.Contains(got, "提交结果未知") {
		t.Fatalf("unknown outcome text = %q", got)
	}
}

func TestSubmitTextShowsTheSchoolsMessage(t *testing.T) {
	if got := SubmitText(errs.NewServer(-1, "人数已满")); got != "人数已满" {
		t.Fatalf("server text = %q, want the school's 人数已满", got)
	}
}

func TestSubmitTextForANetworkFailure(t *testing.T) {
	if got := SubmitText(errs.NewNetwork("reset")); got != "连不上学校的教务系统，请检查网络后刷新" {
		t.Fatalf("network text = %q", got)
	}
}

func TestCloseFormKeepsTheDraft(t *testing.T) {
	f := New(fakeHost{})
	f.st.Form = true
	f.st.Draft = completeDraft()
	f.CloseForm()
	if f.st.Form || f.st.Draft.Description != "漏水" {
		t.Fatalf("close lost the draft or left the form open: form %v draft %+v", f.st.Form, f.st.Draft)
	}
}
