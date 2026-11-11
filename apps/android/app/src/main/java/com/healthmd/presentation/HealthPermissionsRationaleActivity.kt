package com.healthmd.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * Activity shown when Health Connect requests the app's privacy policy / permissions rationale.
 *
 * Required by Health Connect guidelines. Each section maps a Health Connect permission group
 * directly to the specific exported fields it produces, demonstrating that every requested
 * permission is necessary for the app's core export feature.
 */
class HealthPermissionsRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HealthMdTheme {
                RationaleScreen(onClose = ::finish)
            }
        }
    }
}

private data class PermissionCategory(
    val nameRes: Int,
    val permissionsRes: Int,
    val exportsRes: Int,
)

private val categories = listOf(
    PermissionCategory(
        R.string.privacy_category_sleep,
        R.string.privacy_category_sleep_permissions,
        R.string.privacy_category_sleep_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_activity,
        R.string.privacy_category_activity_permissions,
        R.string.privacy_category_activity_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_heart,
        R.string.privacy_category_heart_permissions,
        R.string.privacy_category_heart_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_vitals,
        R.string.privacy_category_vitals_permissions,
        R.string.privacy_category_vitals_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_body,
        R.string.privacy_category_body_permissions,
        R.string.privacy_category_body_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_nutrition,
        R.string.privacy_category_nutrition_permissions,
        R.string.privacy_category_nutrition_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_mobility,
        R.string.privacy_category_mobility_permissions,
        R.string.privacy_category_mobility_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_reproductive,
        R.string.privacy_category_reproductive_permissions,
        R.string.privacy_category_reproductive_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_mindfulness,
        R.string.privacy_category_mindfulness_permissions,
        R.string.privacy_category_mindfulness_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_medical,
        R.string.privacy_category_medical_permissions,
        R.string.privacy_category_medical_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_history,
        R.string.privacy_category_history_permissions,
        R.string.privacy_category_history_exports,
    ),
    PermissionCategory(
        R.string.privacy_category_background,
        R.string.privacy_category_background_permissions,
        R.string.privacy_category_background_exports,
    ),
)

@Composable
private fun RationaleScreen(onClose: () -> Unit) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background100)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .padding(horizontal = GeistSpacing.space1),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose, modifier = Modifier.size(GeistSizes.minimumTouchTarget)) {
                Icon(
                    Icons.AutoMirrored.Outlined.ArrowBack,
                    contentDescription = stringResource(R.string.back),
                    tint = colors.primary,
                )
            }
            Text(
                text = stringResource(R.string.privacy_policy_title),
                style = GeistType.heading24,
                color = colors.primary,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = GeistSpacing.space1, end = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2)
                    .semantics { heading() },
            )
        }
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
            Column(
                modifier = Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    text = stringResource(R.string.privacy_policy_subtitle),
                    style = GeistType.copy16,
                    color = colors.primary,
                )
                Text(
                    text = stringResource(R.string.privacy_policy_direct_cli),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
                // One list group: rows 2dp apart, 20dp outer corners, no dividers.
                Column(
                    modifier = Modifier.padding(vertical = GeistSpacing.space3),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    categories.forEachIndexed { index, category ->
                        CategoryRow(category, groupRowShape(index, categories.size))
                    }
                }
                Text(
                    text = stringResource(R.string.privacy_policy_footer),
                    style = GeistType.copy13,
                    color = colors.secondary,
                )
            }
        }
    }
}

@Composable
private fun CategoryRow(category: PermissionCategory, shape: Shape) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Text(
            text = stringResource(category.nameRes),
            style = GeistType.heading16,
            color = colors.primary,
            modifier = Modifier.semantics { heading() },
        )
        LabeledValue(
            label = stringResource(R.string.privacy_permissions_label),
            value = stringResource(category.permissionsRes),
            monospace = true,
        )
        LabeledValue(
            label = stringResource(R.string.privacy_export_label),
            value = stringResource(category.exportsRes),
        )
    }
}

/** Label above value so long permission names and field lists wrap at full width. */
@Composable
private fun LabeledValue(label: String, value: String, monospace: Boolean = false) {
    val colors = LocalGeistColors.current
    Column {
        Text(text = label, style = GeistType.label12, color = colors.brandPrimary)
        Text(
            text = value,
            style = if (monospace) GeistType.copy13Mono else GeistType.copy14,
            color = colors.secondary,
        )
    }
}
