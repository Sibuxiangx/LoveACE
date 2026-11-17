package main

import (
	"context"
	"errors"
	"sync/atomic"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
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
	acc atomic.Pointer[account.Account]
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

// ScheduleTerms returns the terms the course offerings are listed under.
func (d *SmartData) ScheduleTerms(ctx context.Context) ([]jwc.TermItem, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, sv.CourseScheduleTerms)
}

// CourseSchedule returns every course offering of a term.
func (d *SmartData) CourseSchedule(ctx context.Context, termCode string) ([]jwc.CourseScheduleRecord, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, func(ctx context.Context) ([]jwc.CourseScheduleRecord, error) {
		return sv.CourseScheduleForTerm(ctx, termCode)
	})
}

// StudentSchedule returns the student's own timetable for a term.
func (d *SmartData) StudentSchedule(ctx context.Context, termCode string) (*jwc.StudentScheduleResponse, error) {
	sv, err := d.service()
	if err != nil {
		return nil, err
	}
	return read.Retry(ctx, func(ctx context.Context) (*jwc.StudentScheduleResponse, error) {
		return sv.StudentSchedule(ctx, termCode)
	})
}

// PlanCompletion returns the training plan and its completion. planID is nil for the
// student's plan; a student with several plans gets an error.
func (d *SmartData) PlanCompletion(ctx context.Context, planID *string) (jwc.PlanCompletionInfo, error) {
	sv, err := d.service()
	if err != nil {
		return jwc.PlanCompletionInfo{}, err
	}
	outcome, err := read.Retry(ctx, func(ctx context.Context) (*jwc.PlanCompletionOutcome, error) {
		return sv.PlanCompletion(ctx, planID)
	})
	if err != nil {
		return jwc.PlanCompletionInfo{}, err
	}
	if outcome == nil || outcome.Info == nil {
		return jwc.PlanCompletionInfo{}, errPlanChoice
	}
	return *outcome.Info, nil
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
