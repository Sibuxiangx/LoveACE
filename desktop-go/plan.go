package main

import (
	"context"

	"github.com/Sibuxiangx/loveace-go/core/errs"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// planState is the 培养方案 page's data. A student with several plans is first
// sent the list by the school; the page then reads one plan at a time.
type planState struct {
	pending  bool
	info     readState[jwc.PlanCompletionInfo]
	options  []jwc.PlanOption // the student's plans; empty for a single plan
	planID   string           // the plan the page shows; "" for a single plan
	selected string           // the category ID the right column shows
}

// loadPlan reads the plan with planID, or the first plan when planID is "". A load
// already running is not started again.
func (a *app) loadPlan(planID string) {
	if a.acc == nil || a.plan.pending {
		return
	}
	acc := a.acc
	a.plan.pending = true
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		info, options, id, err := readPlan(ctx, acc.jwc, planID)
		apply(func(x *app) {
			x.plan.pending = false
			x.plan.info = readState[jwc.PlanCompletionInfo]{loaded: true, err: readErrText(err), v: info}
			if options != nil {
				x.plan.options = options
			}
			if id != x.plan.planID {
				x.plan.selected = ""
			}
			x.plan.planID = id
		})
	})
}

// planCompletion reads one plan's completion, retried as readRetry does.
func planCompletion(ctx context.Context, sv *jwc.Service, planID *string) (*jwc.PlanCompletionOutcome, error) {
	return readRetry(ctx, func(ctx context.Context) (*jwc.PlanCompletionOutcome, error) {
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
func (p planState) current() *jwc.PlanCategory {
	if !p.info.loaded || p.info.err != "" || len(p.info.v.Categories) == 0 {
		return nil
	}
	if c := findPlanCategory(p.info.v.Categories, p.selected); c != nil {
		return c
	}
	return &p.info.v.Categories[0]
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
