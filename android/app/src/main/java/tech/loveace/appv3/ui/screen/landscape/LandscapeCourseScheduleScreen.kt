package tech.loveace.appv3.ui.screen.landscape

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.ui.screen.CourseScheduleScaffold
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.CourseScheduleViewModel

/** 横屏开课查询：与竖屏同一页面（筛选 sheet + 结果列表），结果区限制最大宽度。 */
@Composable
fun LandscapeCourseScheduleScreen(
    authViewModel: AuthViewModel,
    vm: CourseScheduleViewModel = viewModel(),
) {
    CourseScheduleScaffold(authViewModel = authViewModel, vm = vm, onBack = null)
}
