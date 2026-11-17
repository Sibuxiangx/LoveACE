package main

import (
	_ "embed"

	"github.com/egoist/mygo/ui"
)

// The icons of the pages: Material Symbols (Rounded, 24px), each a file of
// assets/icons. The outlined ones are the default; the filled ones show a
// destination that is chosen, as Kazumi's rail does. They are parsed once, when
// the program starts.
var (
	//go:embed assets/icons/person.svg
	personSVG []byte
	//go:embed assets/icons/lock.svg
	lockSVG []byte
	//go:embed assets/icons/visibility.svg
	visibilitySVG []byte
	//go:embed assets/icons/visibility_off.svg
	visibilityOffSVG []byte
	//go:embed assets/icons/login.svg
	loginSVG []byte
	//go:embed assets/icons/refresh.svg
	refreshSVG []byte
	//go:embed assets/icons/home.svg
	homeSVG []byte
	//go:embed assets/icons/home_fill.svg
	homeFillSVG []byte
	//go:embed assets/icons/settings.svg
	settingsSVG []byte
	//go:embed assets/icons/settings_fill.svg
	settingsFillSVG []byte
	//go:embed assets/icons/school.svg
	schoolSVG []byte
	//go:embed assets/icons/beach_access.svg
	vacationSVG []byte
	//go:embed assets/icons/quiz.svg
	examSVG []byte
	//go:embed assets/icons/menu_book.svg
	courseSVG []byte
	//go:embed assets/icons/menu_book_fill.svg
	courseFillSVG []byte
	//go:embed assets/icons/credit_card_fill.svg
	creditCardFillSVG []byte
	//go:embed assets/icons/schedule.svg
	scheduleSVG []byte
	//go:embed assets/icons/calendar_today.svg
	calendarSVG []byte
	//go:embed assets/icons/grade.svg
	gradeSVG []byte
	//go:embed assets/icons/credit_card.svg
	cardSVG []byte
	//go:embed assets/icons/volunteer_activism.svg
	volunteerSVG []byte
	//go:embed assets/icons/volunteer_activism_fill.svg
	volunteerFillSVG []byte
	//go:embed assets/icons/check_circle.svg
	checkSVG []byte
	//go:embed assets/icons/cancel.svg
	cancelSVG []byte
	//go:embed assets/icons/warning.svg
	warningSVG []byte
	//go:embed assets/icons/info.svg
	infoSVG []byte
	//go:embed assets/icons/dark_mode.svg
	darkModeSVG []byte
	//go:embed assets/icons/account_circle.svg
	accountSVG []byte
	//go:embed assets/icons/logout.svg
	logoutSVG []byte
	//go:embed assets/icons/chevron_right.svg
	chevronSVG []byte
	//go:embed assets/icons/emoji_events.svg
	eventsSVG []byte
	//go:embed assets/icons/groups.svg
	groupsSVG []byte
	//go:embed assets/icons/workspace_premium.svg
	premiumSVG []byte
	//go:embed assets/icons/auto_awesome.svg
	autoSVG []byte
	//go:embed assets/icons/task_alt.svg
	taskAltSVG []byte
	//go:embed assets/icons/folder_open.svg
	folderSVG []byte
	//go:embed assets/icons/category.svg
	categorySVG []byte
	//go:embed assets/icons/library_books.svg
	librarySVG []byte
	//go:embed assets/icons/handyman.svg
	laborSVG []byte
	//go:embed assets/icons/handyman_fill.svg
	laborFillSVG []byte
	//go:embed assets/icons/location_on.svg
	locationSVG []byte
	//go:embed assets/icons/add_task.svg
	addTaskSVG []byte
	//go:embed assets/icons/calendar_view_week.svg
	weekViewSVG []byte
	//go:embed assets/icons/calendar_view_week_fill.svg
	weekViewFillSVG []byte
)

var (
	iconPerson        = ui.MustParseSVG(personSVG)
	iconLock          = ui.MustParseSVG(lockSVG)
	iconVisibility    = ui.MustParseSVG(visibilitySVG)
	iconVisibilityOff = ui.MustParseSVG(visibilityOffSVG)
	iconLogin         = ui.MustParseSVG(loginSVG)
	iconRefresh       = ui.MustParseSVG(refreshSVG)
	iconHome          = ui.MustParseSVG(homeSVG)
	iconHomeFill      = ui.MustParseSVG(homeFillSVG)
	iconSettings      = ui.MustParseSVG(settingsSVG)
	iconSettingsFill  = ui.MustParseSVG(settingsFillSVG)
	iconSchool        = ui.MustParseSVG(schoolSVG)
	iconVacation      = ui.MustParseSVG(vacationSVG)
	iconExam          = ui.MustParseSVG(examSVG)
	iconCourse        = ui.MustParseSVG(courseSVG)
	iconCourseFill    = ui.MustParseSVG(courseFillSVG)
	iconSchedule      = ui.MustParseSVG(scheduleSVG)
	iconCalendar      = ui.MustParseSVG(calendarSVG)
	iconGrade         = ui.MustParseSVG(gradeSVG)
	iconCard          = ui.MustParseSVG(cardSVG)
	iconCardFill      = ui.MustParseSVG(creditCardFillSVG)
	iconVolunteer     = ui.MustParseSVG(volunteerSVG)
	iconVolunteerFill = ui.MustParseSVG(volunteerFillSVG)
	iconCheck         = ui.MustParseSVG(checkSVG)
	iconCancel        = ui.MustParseSVG(cancelSVG)
	iconWarning       = ui.MustParseSVG(warningSVG)
	iconInfo          = ui.MustParseSVG(infoSVG)
	iconDarkMode      = ui.MustParseSVG(darkModeSVG)
	iconAccount       = ui.MustParseSVG(accountSVG)
	iconLogout        = ui.MustParseSVG(logoutSVG)
	iconChevron       = ui.MustParseSVG(chevronSVG)
	iconEvents        = ui.MustParseSVG(eventsSVG)
	iconGroups        = ui.MustParseSVG(groupsSVG)
	iconPremium       = ui.MustParseSVG(premiumSVG)
	iconAuto          = ui.MustParseSVG(autoSVG)
	iconTaskAlt       = ui.MustParseSVG(taskAltSVG)
	iconFolder        = ui.MustParseSVG(folderSVG)
	iconCategory      = ui.MustParseSVG(categorySVG)
	iconLibrary       = ui.MustParseSVG(librarySVG)
	iconLabor         = ui.MustParseSVG(laborSVG)
	iconLaborFill     = ui.MustParseSVG(laborFillSVG)
	iconLocation      = ui.MustParseSVG(locationSVG)
	iconAddTask       = ui.MustParseSVG(addTaskSVG)
	iconWeekView      = ui.MustParseSVG(weekViewSVG)
	iconWeekViewFill  = ui.MustParseSVG(weekViewFillSVG)
)
