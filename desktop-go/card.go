package main

import (
	"context"
	"sort"
	"strconv"
	"strings"

	"github.com/Sibuxiangx/loveace-go/core/services/portal"
	"github.com/Sibuxiangx/loveace-go/core/services/ykt"
	"github.com/Sibuxiangx/loveace-go/core/session"
)

// maxConsumptionPages caps the portal pages one load reads. The portal gives 100
// rows a page, and a month of campus-card rows is far below the cap.
const maxConsumptionPages = 10

// cardState is the 一卡通 page's data, and the balance the home page's wallet tile
// shows, so the school is asked once for both. The balance is the campus card's;
// the rows are the portal's, which lists this month only and gives neither a
// balance nor an income sign for a row.
type cardState struct {
	pending int // reads in flight
	balance readState[float64]
	rows    readState[portal.ConsumptionPage]
}

// loadCard reads the balance and this month's rows in the background. A load
// already running is not started again.
func (a *app) loadCard() {
	if a.acc == nil || a.card.pending > 0 {
		return
	}
	acc := a.acc
	a.card.pending = 2
	// done counts one read as finished.
	done := func(apply applyFn) {
		apply(func(x *app) { x.card.pending-- })
	}
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		defer done(apply)
		balance, err := readRetry(ctx, ykt.New(acc.sess).Balance)
		var v float64
		if err == nil {
			v = balance.Balance
		}
		apply(func(x *app) {
			x.card.balance = readState[float64]{loaded: true, err: readErrText(err), v: v}
		})
	})
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		defer done(apply)
		rows, err := loadConsumption(ctx, acc.sess)
		apply(func(x *app) {
			x.card.rows = readState[portal.ConsumptionPage]{loaded: true, err: readErrText(err), v: rows}
		})
	})
}

// loadConsumption reads every page of this month's rows, newest first.
func loadConsumption(ctx context.Context, sess *session.Session) (portal.ConsumptionPage, error) {
	sv := portal.New(sess)
	var out portal.ConsumptionPage
	for page := 1; page <= maxConsumptionPages; page++ {
		got, err := readRetry(ctx, func(ctx context.Context) (*portal.ConsumptionPage, error) {
			return sv.ConsumptionRecords(ctx, page)
		})
		if err != nil {
			return portal.ConsumptionPage{}, err
		}
		out.Total = got.Total
		out.Records = append(out.Records, got.Records...)
		if len(got.Records) == 0 || len(out.Records) >= got.Total {
			break
		}
	}
	sort.SliceStable(out.Records, func(i, j int) bool {
		x, y := out.Records[i], out.Records[j]
		return x.Date+x.Time > y.Date+y.Time
	})
	return out, nil
}

// cardArea is one place of this month's consumption: its rows and their total.
type cardArea struct {
	name   string
	count  int
	amount float64
}

// consumptionTotals adds up the rows and groups them by place, largest first. A
// row whose amount does not read as a number counts as a row and adds nothing.
// The portal gives no sign, and a consumption row is a payment, so every amount
// adds up as spending.
func consumptionTotals(rows []portal.ConsumptionRecord) (total float64, areas []cardArea) {
	index := map[string]int{}
	for _, r := range rows {
		amount, err := strconv.ParseFloat(strings.TrimSpace(r.Amount), 64)
		if err != nil {
			amount = 0
		}
		total += amount
		i, ok := index[r.Area]
		if !ok {
			i = len(areas)
			index[r.Area] = i
			areas = append(areas, cardArea{name: r.Area})
		}
		areas[i].count++
		areas[i].amount += amount
	}
	sort.SliceStable(areas, func(i, j int) bool { return areas[i].amount > areas[j].amount })
	return total, areas
}
