package com.healthmd.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.GeistMono
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.theme.Spacing

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
                Surface(modifier = Modifier.fillMaxSize()) {
                    RationaleScreen()
                }
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
private fun RationaleScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Text(
            text = stringResource(R.string.privacy_policy_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )

        Text(
            text = stringResource(R.string.privacy_policy_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        HorizontalDivider()

        categories.forEach { category ->
            CategoryCard(category)
        }

        HorizontalDivider()

        Text(
            text = stringResource(R.string.privacy_policy_footer),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CategoryCard(category: PermissionCategory) {
    GeistCard(
        modifier = Modifier.fillMaxWidth(),
        padding = Spacing.md,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            Text(
                text = stringResource(category.nameRes),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            LabeledRow(
                label = "Permissions:",
                value = stringResource(category.permissionsRes),
                monospace = true,
            )

            LabeledRow(
                label = "Export:",
                value = stringResource(category.exportsRes),
            )
        }
    }
}

@Composable
private fun LabeledRow(label: String, value: String, monospace: Boolean = false) {
    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = if (monospace) GeistMono else null,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
