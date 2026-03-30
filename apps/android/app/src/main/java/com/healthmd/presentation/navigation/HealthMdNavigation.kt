package com.healthmd.presentation.navigation

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.healthmd.presentation.export.ExportScreen
import com.healthmd.presentation.history.HistoryScreen
import com.healthmd.presentation.schedule.ScheduleScreen
import com.healthmd.presentation.settings.SettingsScreen
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun HealthMdNavigation() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        // Content
        NavHost(
            navController = navController,
            startDestination = NavDestination.EXPORT.route,
            modifier = Modifier
                .fillMaxSize()
                .padding(bottom = 88.dp), // space for floating nav
        ) {
            composable(NavDestination.EXPORT.route) { ExportScreen() }
            composable(NavDestination.SCHEDULE.route) { ScheduleScreen() }
            composable(NavDestination.HISTORY.route) { HistoryScreen() }
            composable(NavDestination.SETTINGS.route) { SettingsScreen() }
        }

        // Floating Pill Navigation Bar
        FloatingNavBar(
            destinations = NavDestination.entries,
            currentRoute = currentDestination?.route,
            onNavigate = { dest ->
                navController.navigate(dest.route) {
                    popUpTo(navController.graph.findStartDestination().id) {
                        saveState = true
                    }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(start = 40.dp, end = 40.dp, bottom = 16.dp),
        )
    }
}

@Composable
private fun FloatingNavBar(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(100.dp) // capsule

    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 20.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.30f),
                spotColor = Color.Black.copy(alpha = 0.30f),
            )
            .clip(shape)
            .background(AppColors.bgSecondary.copy(alpha = 0.95f))
            .border(1.dp, AppColors.navBarBorder, shape)
            .padding(8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        destinations.forEach { dest ->
            val selected = currentRoute == dest.route
            NavBarTab(
                destination = dest,
                selected = selected,
                onClick = { onNavigate(dest) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun NavBarTab(
    destination: NavDestination,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scale by animateFloatAsState(
        targetValue = if (selected) 1f else 1f,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        label = "tabScale",
    )
    val bgColor by animateColorAsState(
        targetValue = if (selected) Color.White.copy(alpha = 0.15f) else Color.Transparent,
        label = "tabBg",
    )
    val contentColor = if (selected) AppColors.textPrimary else AppColors.textMuted
    val shape = RoundedCornerShape(100.dp)

    Column(
        modifier = modifier
            .scale(scale)
            .height(56.dp)
            .clip(shape)
            .background(bgColor)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            destination.icon,
            contentDescription = destination.label,
            tint = contentColor,
            modifier = Modifier.size(22.dp),
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            destination.label,
            color = contentColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun animateColorAsState(
    targetValue: Color,
    label: String,
): State<Color> {
    val animatedAlpha by animateFloatAsState(
        targetValue = targetValue.alpha,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        label = label,
    )
    return remember(targetValue, animatedAlpha) {
        mutableStateOf(targetValue.copy(alpha = animatedAlpha))
    }
}
