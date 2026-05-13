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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.HealthMdTheme

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
            .padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(R.string.privacy_policy_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
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
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = if (monospace) FontFamily.Monospace else null,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
