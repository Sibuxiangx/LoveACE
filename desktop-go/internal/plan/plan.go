package plan

import (
	"context"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// State is the 培养方案 page's data. A student with several plans is first
// sent the list by the school; the page then reads one plan at a time.
type State struct {
	Pending  bool
	Info     read.State[jwc.PlanCompletionInfo]
	Options  []jwc.PlanOption // the student's plans; empty for a single plan
	PlanID   string           // the plan the page shows; "" for a single plan
	Selected string           // the category ID the right column shows
}

// Feature is the 培养方案 page: its state and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the 培养方案 page, reading through h.
func New(h host.Host) *Feature {
	return &Feature{h: h}
}

// Reset clears the page, as signing out does.
func (f *Feature) Reset() {
	f.st = State{}
}

// Snapshot is a read-only copy of the page's data, for the home page and navigation.
func (f *Feature) Snapshot() State {
	return f.st
}

// Load reads the plan with planID, or the first plan when planID is "". A load
// already running is not started again.
func (f *Feature) Load(planID string) {
	acc := f.h.Account()
	if acc == nil || f.st.Pending {
		return
	}
	f.st.Pending = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		info, options, id, err := readPlan(ctx, acc.Jwc, planID)
		apply(func() {
			f.st.Pending = false
			f.st.Info = read.Done(info, read.ErrText(err))
			if options != nil {
				f.st.Options = options
			}
			if id != f.st.PlanID {
				f.st.Selected = ""
			}
			f.st.PlanID = id
		})
	})
}

// planCompletion reads one plan's completion, retried as read.Retry does.
func planCompletion(ctx context.Context, sv *jwc.Service, planID *string) (*jwc.PlanCompletionOutcome, error) {
	return read.Retry(ctx, func(ctx context.Context) (*jwc.PlanCompletionOutcome, error) {
		return sv.PlanCompletion(ctx, planID)
	})
}

// readPlan reads one plan. A student with several plans is first answered with the
// list; the first plan on it is then read, as the Android app does.
func readPlan(ctx context.Context, sv *jwc.Service, planID string) (jwc.PlanCompletionInfo, []jwc.PlanOption, string, error) {
	var req *string
	if planID != "" {
		req = &planID
	}
	out, err := planCompletion(ctx, sv, req)
	if err != nil {
		return jwc.PlanCompletionInfo{}, nil, planID, err
	}
	var options []jwc.PlanOption
	if out.Kind == jwc.OutcomeNeedsSelection {
		if planID != "" || out.Selection == nil || len(out.Selection.Options) == 0 {
			return jwc.PlanCompletionInfo{}, nil, planID, errs.NewParse("planCompletion: no plan to read")
		}
		options = out.Selection.Options
		planID = options[0].PlanID
		out, err = planCompletion(ctx, sv, &planID)
		if err != nil {
			return jwc.PlanCompletionInfo{}, options, planID, err
		}
	}
	if out.Info == nil {
		return jwc.PlanCompletionInfo{}, options, planID, errs.NewParse("planCompletion: no plan info")
	}
	return *out.Info, options, planID, nil
}

// planCategoryRow is one category of the flattened tree, with its depth.
type planCategoryRow struct {
	cat   jwc.PlanCategory
	depth int
}

// flattenPlan lists the categories depth first, each with its depth.
func flattenPlan(cats []jwc.PlanCategory, depth int) []planCategoryRow {
	var rows []planCategoryRow
	for _, c := range cats {
		rows = append(rows, planCategoryRow{c, depth})
		rows = append(rows, flattenPlan(c.Subcategories, depth+1)...)
	}
	return rows
}

// findPlanCategory returns the category with id, searching the whole tree.
func findPlanCategory(cats []jwc.PlanCategory, id string) *jwc.PlanCategory {
	for i := range cats {
		if cats[i].CategoryID == id {
			return &cats[i]
		}
		if c := findPlanCategory(cats[i].Subcategories, id); c != nil {
			return c
		}
	}
	return nil
}

// current is the category the right column shows: the chosen one, or the first
// top-level category when the chosen one is not in this plan.
func (s State) current() *jwc.PlanCategory {
	if !s.Info.Loaded() || s.Info.Err() != "" || len(s.Info.Value().Categories) == 0 {
		return nil
	}
	if c := findPlanCategory(s.Info.Value().Categories, s.Selected); c != nil {
		return c
	}
	return &s.Info.Value().Categories[0]
}

// planTotals are the overview's numbers, counted as the Android app counts them:
// the credits held are the top categories' sums, the credits a graduate needs and
// the missing required courses are the leaf categories' sums.
type planTotals struct {
	credits float64
	need    float64
	missing int64
}

func planTotalsOf(cats []jwc.PlanCategory) planTotals {
	var t planTotals
	for _, c := range cats {
		t.credits += c.CompletedCredits
	}
	var walk func(cats []jwc.PlanCategory)
	walk = func(cats []jwc.PlanCategory) {
		for _, c := range cats {
			if len(c.Subcategories) == 0 {
				t.need += c.MinCredits
				t.missing += c.MissingRequiredCourses
			} else {
				walk(c.Subcategories)
			}
		}
	}
	walk(cats)
	return t
}
