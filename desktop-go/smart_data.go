package main

import (
	"context"
	"errors"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-desktop/internal/snapshot"
	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// errNotSignedIn is what a read returns while no account is signed in.
var errNotSignedIn = errors.New("未登录")

// errPlanChoice is what the plan read returns for a student with more than one plan: the
// webview cannot choose one, so the desktop app's plan page must.
var errPlanChoice = errors.New("这位同学有多个培养方案，请先在培养方案页面选择")

// SmartData is the school data the 智能排课 webview reads, bound as the SmartData service.
// The page holds no school session: every read goes through the signed-in account. The
// account is set on the main thread and read from the service's goroutines, hence atomic.
type SmartData struct {
	acc         atomic.Pointer[account.Account]
	offeringsMu sync.Mutex // one read of the offerings at a time, so a cache is written once
}

// service is the school service of the signed-in account, for a read.
func (d *SmartData) service() (*jwc.Service, error) {
	acc := d.acc.Load()
	if acc == nil {
		return nil, errNotSignedIn
	}
	return acc.Jwc, nil
}

// UserID is the signed-in student's id, "" while no account is signed in.
func (d *SmartData) UserID() string {
	if acc := d.acc.Load(); acc != nil {
		return acc.ID
	}
	return ""
}

// ScheduleTerms returns the terms the course offerings are listed under. They are cached
// like the plan: the page lists them each time it opens.
func (d *SmartData) ScheduleTerms(ctx context.Context) ([]jwc.TermItem, error) {
	acc := d.acc.Load()
	if acc == nil {
		return nil, errNotSignedIn
	}
	return cachedRead(cacheFile("terms", acc.ID, ""), func() ([]jwc.TermItem, error) {
		return read.Retry(ctx, acc.Jwc.CourseScheduleTerms)
	})
}

// CourseSchedule returns the course offerings of a term, reused from the cache while they
// are fresh (cacheTTL) unless forceRefresh asks the school again. A fresh fetch is written
// to the cache; a failed save is logged, since the offerings were still read.
func (d *SmartData) CourseSchedule(ctx context.Context, termCode string, forceRefresh bool) (Offerings, error) {
	acc := d.acc.Load()
	if acc == nil {
		return Offerings{}, errNotSignedIn
	}
	name := offeringsFile(acc.ID, termCode)

	d.offeringsMu.Lock()
	defer d.offeringsMu.Unlock()
	if !forceRefresh {
		if cached, ok := loadOfferings(name); ok && cacheFresh(time.UnixMilli(cached.FetchedAt), time.Now()) {
			return cached, nil
		}
	}
	records, err := read.Retry(ctx, func(ctx context.Context) ([]jwc.CourseScheduleRecord, error) {
		return acc.Jwc.CourseScheduleForTerm(ctx, termCode)
	})
	if err != nil {
		return Offerings{}, err
	}
	fresh := Offerings{FetchedAt: time.Now().UnixMilli(), Records: records}
	if err := userdata.WriteJSON(name, fresh); err != nil {
		log.Printf("smart offerings: save: %v", err)
	}
	return fresh, nil
}

// SaveDraft keeps the simulated picks of a term with the term's saved timetable, so the
// sign-in page's snapshot shows them: added are the offering records of the 模拟选课, removed
// the keys of the 模拟退课. The smart page sends its whole state each time it saves.
func (d *SmartData) SaveDraft(termCode string, added []jwc.CourseScheduleRecord, removed []string) error {
	acc := d.acc.Load()
	if acc == nil {
		return errNotSignedIn
	}
	return snapshot.SaveDraft(acc.ID, termCode, added, removed)
}

// StudentSchedule returns the student's own timetable for a term. A successful read is kept
// as the term's snapshot, which the sign-in page shows when the school cannot be reached.
func (d *SmartData) StudentSchedule(ctx context.Context, termCode string) (*jwc.StudentScheduleResponse, error) {
	acc := d.acc.Load()
	if acc == nil {
		return nil, errNotSignedIn
	}
	resp, err := read.Retry(ctx, func(ctx context.Context) (*jwc.StudentScheduleResponse, error) {
		return acc.Jwc.StudentSchedule(ctx, termCode)
	})
	if err != nil {
		return nil, err
	}
	if resp != nil {
		saved := snapshot.Entry{
			AccountID: acc.ID,
			TermCode:  termCode,
			TermName:  termName(acc.ID, termCode),
			SavedAt:   time.Now().UnixMilli(),
			Courses:   resp.Courses(),
		}
		if err := snapshot.Save(saved); err != nil {
			log.Printf("smart snapshot: save: %v", err)
		}
	}
	return resp, nil
}

// termName is the name the school lists termCode under, from the account's cached terms, or
// termCode itself while the terms were never read.
func termName(accountID, termCode string) string {
	var terms stamped[[]jwc.TermItem]
	if err := userdata.ReadJSON(cacheFile("terms", accountID, ""), &terms); err == nil {
		for _, term := range terms.Value {
			if term.TermCode == termCode && term.TermName != "" {
				return term.TermName
			}
		}
	}
	return termCode
}

// PlanCompletion returns the training plan and its completion. planID is nil for the
// student's plan; a student with several plans gets an error. The plan is cached like the
// offerings: it changes rarely, and the page reads it each time it opens.
func (d *SmartData) PlanCompletion(ctx context.Context, planID *string) (jwc.PlanCompletionInfo, error) {
	acc := d.acc.Load()
	if acc == nil {
		return jwc.PlanCompletionInfo{}, errNotSignedIn
	}
	key := "own"
	if planID != nil {
		key = "plan\x00" + *planID
	}
	return cachedRead(cacheFile("plan", acc.ID, key), func() (jwc.PlanCompletionInfo, error) {
		outcome, err := read.Retry(ctx, func(ctx context.Context) (*jwc.PlanCompletionOutcome, error) {
			return acc.Jwc.PlanCompletion(ctx, planID)
		})
		if err != nil {
			return jwc.PlanCompletionInfo{}, err
		}
		if outcome == nil || outcome.Info == nil {
			return jwc.PlanCompletionInfo{}, errPlanChoice
		}
		return *outcome.Info, nil
	})
}

// ClassTerms returns the terms the class curriculum is listed under.
func (d *SmartData) ClassTerms(ctx context.Context) ([]jwc.TermItem, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, sv.ClassCurriculumTerms)
}

// Departments returns the departments of the class curriculum.
func (d *SmartData) Departments(ctx context.Context) ([]jwc.ClassCurriculumOption, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, sv.ClassCurriculumDepartments)
}

// Subjects returns the subjects of a department.
func (d *SmartData) Subjects(ctx context.Context, departmentCode string) ([]jwc.ClassCurriculumOption, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, func(ctx context.Context) ([]jwc.ClassCurriculumOption, error) {
		return sv.ClassCurriculumSubjects(ctx, departmentCode)
	})
}

// Classes returns the classes of a plan under a department, and of one subject when
// subjectCode is set.
func (d *SmartData) Classes(ctx context.Context, planCode, departmentCode string, subjectCode *string) ([]jwc.ClassCurriculumClassOption, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, func(ctx context.Context) ([]jwc.ClassCurriculumClassOption, error) {
		return sv.ClassCurriculumClasses(ctx, planCode, departmentCode, subjectCode)
	})
}

// ClassCurriculum returns the course schedule of one class.
func (d *SmartData) ClassCurriculum(ctx context.Context, planCode, classCode string) ([]jwc.CourseScheduleRecord, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, func(ctx context.Context) ([]jwc.CourseScheduleRecord, error) {
		return sv.ClassCurriculum(ctx, planCode, classCode)
	})
}
