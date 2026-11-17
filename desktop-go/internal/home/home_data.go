package home

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/config"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/common"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/Sibuxiangx/loveace-go/core/session"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/Sibuxiangx/loveace-go/core/transport"
)

// weekdayNames are the school's day names; classDay 1 is 周一.
var weekdayNames = [...]string{"周一", "周二", "周三", "周四", "周五", "周六", "周日"}

// homeClass is one class of today, as the school's schedule gives it.
type homeClass struct {
	from   int64 // first session, for ordering
	name   string
	time   string // 第3-4节
	detail string // place · teacher
}

// homeExam is one upcoming exam, as the school's exam info gives it.
type homeExam struct {
	name   string
	when   string // date and time
	detail string // exam type · location
}

// semesterPhase says where today falls in a term.
type semesterPhase int

const (
	beforeTerm    semesterPhase = iota // before the term's first day
	teaching                           // in the teaching weeks
	afterTeaching                      // after the teaching weeks: exam week or holiday
)

// semesterInfo is the school's current term: where today falls in it, and the
// next term once the teaching weeks are over.
type semesterInfo struct {
	termCode string
	name     string
	phase    semesterPhase
	week     int       // 1-based teaching week, when teaching
	weeks    int       // teaching weeks of the term
	start    time.Time // first day of the term, Shanghai midnight
	next     *upcomingSemester
}

// upcomingSemester is a later term of the manifest.
type upcomingSemester struct {
	name  string
	start time.Time
}

// academicInfo is the academic overview: GPA and course counts from jwc, and
// the average score and its rank.
type academicInfo struct {
	gpa                        float64
	pending, completed, failed int64
	score                      float64 // 均分, 百分制
	rank, rankTotal            int64   // 均分排名, and the students ranked
}

// Load reads the home page's data in the background. A load that is already
// running is not started again.
func (f *Feature) Load() {
	acc := f.h.Account()
	if acc == nil || f.st.Pending > 0 {
		return
	}
	f.st.Pending = 3
	// finish counts one read as done; the last one stamps the page.
	finish := func(apply func(func())) {
		apply(func() {
			f.st.Pending--
			if f.st.Pending == 0 {
				f.st.Stamp = time.Now()
			}
		})
	}
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		defer finish(apply)
		now := timeutil.NowShanghai()
		sem, semErr := read.Retry(ctx, func(ctx context.Context) (semesterInfo, error) {
			return loadSemester(ctx, acc.Jwc, shanghaiToday(now))
		})
		apply(func() {
			f.st.Semester = read.Done(sem, read.ErrText(semErr))
		})
		if semErr != nil || sem.phase != teaching {
			apply(func() {
				f.st.Today = read.Done([]homeClass(nil), read.ErrText(semErr))
			})
			return
		}
		classes, err := read.Retry(ctx, func(ctx context.Context) ([]homeClass, error) {
			return loadToday(ctx, acc.Jwc, sem.termCode, sem.week, now)
		})
		apply(func() {
			f.st.Today = read.Done(classes, read.ErrText(err))
		})
	})
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		defer finish(apply)
		exams, err := read.Retry(ctx, func(ctx context.Context) ([]homeExam, error) {
			return loadExams(ctx, acc.Jwc, timeutil.FormatYMD(timeutil.NowShanghai()))
		})
		apply(func() {
			f.st.Exams = read.Done(exams, read.ErrText(err))
		})
	})
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		defer finish(apply)
		info, err := read.Retry(ctx, func(ctx context.Context) (academicInfo, error) {
			return loadAcademic(ctx, acc)
		})
		apply(func() {
			f.st.Academic = read.Done(info, read.ErrText(err))
		})
	})
}

// Refresh reads the home page's data again, with the campus card's balance the
// wallet tile shows.
func (f *Feature) Refresh() {
	f.Load()
	f.card.Load()
}

// shanghaiToday is the Shanghai midnight of the day of now: the school's days
// start there.
func shanghaiToday(now time.Time) time.Time {
	n := now.In(timeutil.Shanghai)
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, timeutil.Shanghai)
}

// loadSemester reads the school's current term from the term list and places
// today in it, using the manifest's dates.
func loadSemester(ctx context.Context, sv *jwc.Service, today time.Time) (semesterInfo, error) {
	terms, err := sv.Terms(ctx)
	if err != nil {
		return semesterInfo{}, err
	}
	var code, name string
	for _, term := range terms {
		if term.IsCurrent {
			code, name = term.TermCode, term.TermName
			break
		}
	}
	if code == "" {
		return semesterInfo{}, errs.NewParse("the school marks no current term")
	}
	semesters, err := fetchSemesters(ctx)
	if err != nil {
		return semesterInfo{}, err
	}
	return semesterFor(semesters, code, name, today)
}

// semesterFor places today in the term of the school's term code. The manifest
// entry matches the code, or starts it: the school's "2026-2027-1-1" is the
// manifest's "2026-2027-1". Its name is the manifest's, or the school's when
// the manifest has none.
func semesterFor(semesters []manifestSemester, termCode, termName string, today time.Time) (semesterInfo, error) {
	var cur *manifestSemester
	for i := range semesters {
		if termCode == semesters[i].Code || strings.HasPrefix(termCode, semesters[i].Code+"-") {
			cur = &semesters[i]
			break
		}
	}
	if cur == nil {
		return semesterInfo{}, read.ErrNoTermStart
	}
	start, err := time.ParseInLocation("2006-01-02", cur.StartDate, timeutil.Shanghai)
	if err != nil {
		return semesterInfo{}, err
	}
	info := semesterInfo{termCode: termCode, name: cur.Name, start: start, weeks: cur.Weeks}
	if info.name == "" {
		info.name = termName
	}
	// Both instants are Shanghai midnights, so the division is exact.
	days := int(today.Sub(start) / (24 * time.Hour))
	switch {
	case days < 0:
		info.phase = beforeTerm
	case days < cur.Weeks*7:
		info.phase = teaching
		info.week = days/7 + 1
	default:
		info.phase = afterTeaching
		info.next = nextUpcoming(semesters, today)
	}
	return info, nil
}

// nextUpcoming is the earliest term of the manifest that starts after today.
func nextUpcoming(semesters []manifestSemester, today time.Time) *upcomingSemester {
	var next *upcomingSemester
	for _, s := range semesters {
		start, err := time.ParseInLocation("2006-01-02", s.StartDate, timeutil.Shanghai)
		if err != nil || !start.After(today) {
			continue
		}
		if next == nil || start.Before(next.start) {
			next = &upcomingSemester{name: s.Name, start: start}
		}
	}
	return next
}

// loadToday reads the classes of today in the teaching week, sorted by their
// first session.
func loadToday(ctx context.Context, sv *jwc.Service, termCode string, week int, now time.Time) ([]homeClass, error) {
	schedule, err := sv.StudentSchedule(ctx, termCode)
	if err != nil {
		return nil, err
	}
	day := classDay(now)
	var classes []homeClass
	for _, course := range schedule.Courses() {
		for _, slot := range course.TimeAndPlaceList {
			if slot.ClassDay != day || !jwc.WeekMatches(slot.ClassWeek, week) {
				continue
			}
			name := course.CourseName
			if name == "" {
				name = slot.CoureName
			}
			sessionTime := fmt.Sprintf("第%d节", slot.ClassSessions)
			if end := slot.EndSession(); end > slot.ClassSessions {
				sessionTime = fmt.Sprintf("第%d-%d节", slot.ClassSessions, end)
			}
			var parts []string
			if place := strings.Join(strings.Fields(slot.LocationDescription()), " "); place != "" {
				parts = append(parts, place)
			}
			if course.AttendClassTeacher != "" {
				parts = append(parts, course.AttendClassTeacher)
			}
			classes = append(classes, homeClass{
				from:   slot.ClassSessions,
				name:   name,
				time:   sessionTime,
				detail: strings.Join(parts, " · "),
			})
		}
	}
	sort.SliceStable(classes, func(i, j int) bool { return classes[i].from < classes[j].from })
	return classes, nil
}

// loadExams reads the school's exams from today on. JWC sorts them by date and
// time, earliest first.
func loadExams(ctx context.Context, sv *jwc.Service, today string) ([]homeExam, error) {
	info, err := sv.ExamInfo(ctx)
	if err != nil {
		return nil, err
	}
	var exams []homeExam
	for _, e := range info.Exams {
		// ExamDate starts with YYYY-MM-DD, so string order is date order.
		if e.ExamDate < today {
			continue
		}
		var parts []string
		for _, part := range []string{e.ExamType, e.ExamLocation} {
			if part != "" {
				parts = append(parts, part)
			}
		}
		exams = append(exams, homeExam{
			name:   e.CourseName,
			when:   strings.TrimSpace(e.ExamDate + " " + e.ExamTime),
			detail: strings.Join(parts, " · "),
		})
	}
	return exams, nil
}

// loadAcademic reads the academic overview. jwc.AcademicInfo gives the GPA and
// the course counts; the average score and its rank come from academicAverage.
func loadAcademic(ctx context.Context, acc *account.Account) (academicInfo, error) {
	base, err := acc.Jwc.AcademicInfo(ctx)
	if err != nil {
		return academicInfo{}, err
	}
	score, rank, total, err := academicAverage(ctx, acc.Sess)
	if err != nil {
		return academicInfo{}, err
	}
	return academicInfo{
		gpa:       base.GPA,
		pending:   base.PendingCourses,
		completed: base.CompletedCourses,
		failed:    base.FailedCourses,
		score:     score,
		rank:      rank,
		rankTotal: total,
	}, nil
}

// academicAverage reads the average score and its rank from the academic
// overview, the same response jwc.AcademicInfo reads. loveace-go keeps only
// the GPA and the course counts from it, so the three fields are read here.
func academicAverage(ctx context.Context, s *session.Session) (float64, int64, int64, error) {
	if err := s.AwaitServiceCallback(ctx); err != nil {
		return 0, 0, 0, err
	}
	cfg := s.Config()
	request := transport.NewRequest(transport.Post, config.JoinURL(cfg.JWCBase, "/main/academicInfo?sf_request_type=ajax")).
		Header("Content-Type", "application/x-www-form-urlencoded").
		WithBody([]byte(config.FormEncode(nil)))
	request.Headers = append(request.Headers, [2]string{"Referer", config.JoinURL(cfg.JWCBase, "/index.jsp")})
	response, err := s.SendRead(ctx, request)
	if err != nil {
		return 0, 0, 0, err
	}
	value, err := common.ParseJSON(response.BodyText())
	if err != nil {
		return 0, 0, 0, err
	}
	items := common.ArrayItems(value)
	if len(items) == 0 {
		return 0, 0, 0, errs.NewParse("academicInfo: expected non-empty array")
	}
	first := items[0]
	return common.JSONF64(first, "sspjf_jd"), common.JSONI64(first, "sspjf_pm"), common.JSONI64(first, "sspjf_rs"), nil
}

// classDay is the school's weekday number of now: 周一 is 1, 周日 is 7.
func classDay(now time.Time) int64 {
	if d := int64(now.Weekday()); d != 0 {
		return d
	}
	return 7
}

// manifestSemester is one term of the manifest's semester table.
type manifestSemester struct {
	Code      string `json:"code"`
	Name      string `json:"name"`
	StartDate string `json:"start_date"`
	Weeks     int    `json:"weeks"`
}

// manifestDoc is the part of manifest v2 that dates the terms.
type manifestDoc struct {
	Semester struct {
		Semesters []manifestSemester `json:"semesters"`
	} `json:"semester"`
}

// fetchSemesters reads the semester table of manifest v2, trying each URL in
// turn. The manifest is a public file: no sign-in is needed.
func fetchSemesters(ctx context.Context) ([]manifestSemester, error) {
	var lastErr error
	for _, rawURL := range []string{config.ManifestURLPrimary, config.ManifestURLFallback} {
		semesters, err := fetchManifestSemesters(ctx, rawURL)
		if err == nil {
			return semesters, nil
		}
		lastErr = err
	}
	return nil, lastErr
}

func fetchManifestSemesters(ctx context.Context, rawURL string) ([]manifestSemester, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, errs.NewNetwork("manifest unreachable")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, errs.NewNetwork("manifest unavailable")
	}
	var doc manifestDoc
	if err := json.NewDecoder(response.Body).Decode(&doc); err != nil {
		return nil, errs.NewParse("manifest: bad JSON")
	}
	return doc.Semester.Semesters, nil
}
