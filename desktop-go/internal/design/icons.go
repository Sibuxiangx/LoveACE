package design

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
	//go:embed assets/icons/bolt.svg
	boltSVG []byte
	//go:embed assets/icons/bolt_fill.svg
	boltFillSVG []byte
	//go:embed assets/icons/build.svg
	buildSVG []byte
	//go:embed assets/icons/build_fill.svg
	buildFillSVG []byte
	//go:embed assets/icons/add_a_photo.svg
	addPhotoSVG []byte
	//go:embed assets/icons/close.svg
	closeSVG []byte
	//go:embed assets/icons/file_download.svg
	fileDownloadSVG []byte
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
	IconPerson        = ui.MustParseSVG(personSVG)
	IconLock          = ui.MustParseSVG(lockSVG)
	IconVisibility    = ui.MustParseSVG(visibilitySVG)
	IconVisibilityOff = ui.MustParseSVG(visibilityOffSVG)
	IconLogin         = ui.MustParseSVG(loginSVG)
	IconRefresh       = ui.MustParseSVG(refreshSVG)
	IconHome          = ui.MustParseSVG(homeSVG)
	IconHomeFill      = ui.MustParseSVG(homeFillSVG)
	IconSettings      = ui.MustParseSVG(settingsSVG)
	IconSettingsFill  = ui.MustParseSVG(settingsFillSVG)
	IconSchool        = ui.MustParseSVG(schoolSVG)
	IconVacation      = ui.MustParseSVG(vacationSVG)
	IconExam          = ui.MustParseSVG(examSVG)
	IconCourse        = ui.MustParseSVG(courseSVG)
	IconCourseFill    = ui.MustParseSVG(courseFillSVG)
	IconSchedule      = ui.MustParseSVG(scheduleSVG)
	IconCalendar      = ui.MustParseSVG(calendarSVG)
	IconGrade         = ui.MustParseSVG(gradeSVG)
	IconCard          = ui.MustParseSVG(cardSVG)
	IconCardFill      = ui.MustParseSVG(creditCardFillSVG)
	IconVolunteer     = ui.MustParseSVG(volunteerSVG)
	IconVolunteerFill = ui.MustParseSVG(volunteerFillSVG)
	IconCheck         = ui.MustParseSVG(checkSVG)
	IconCancel        = ui.MustParseSVG(cancelSVG)
	IconWarning       = ui.MustParseSVG(warningSVG)
	IconInfo          = ui.MustParseSVG(infoSVG)
	IconDarkMode      = ui.MustParseSVG(darkModeSVG)
	IconAccount       = ui.MustParseSVG(accountSVG)
	IconLogout        = ui.MustParseSVG(logoutSVG)
	IconChevron       = ui.MustParseSVG(chevronSVG)
	IconEvents        = ui.MustParseSVG(eventsSVG)
	IconGroups        = ui.MustParseSVG(groupsSVG)
	IconPremium       = ui.MustParseSVG(premiumSVG)
	IconAuto          = ui.MustParseSVG(autoSVG)
	IconTaskAlt       = ui.MustParseSVG(taskAltSVG)
	IconFolder        = ui.MustParseSVG(folderSVG)
	IconCategory      = ui.MustParseSVG(categorySVG)
	IconLibrary       = ui.MustParseSVG(librarySVG)
	IconLabor         = ui.MustParseSVG(laborSVG)
	IconLaborFill     = ui.MustParseSVG(laborFillSVG)
	IconLocation      = ui.MustParseSVG(locationSVG)
	IconBolt          = ui.MustParseSVG(boltSVG)
	IconBoltFill      = ui.MustParseSVG(boltFillSVG)
	IconBuild         = ui.MustParseSVG(buildSVG)
	IconBuildFill     = ui.MustParseSVG(buildFillSVG)
	IconAddTask       = ui.MustParseSVG(addTaskSVG)
	IconWeekView      = ui.MustParseSVG(weekViewSVG)
	IconWeekViewFill  = ui.MustParseSVG(weekViewFillSVG)
	IconAddPhoto      = ui.MustParseSVG(addPhotoSVG)
	IconClose         = ui.MustParseSVG(closeSVG)
	IconFileDownload  = ui.MustParseSVG(fileDownloadSVG)
)
