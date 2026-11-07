package com.healthmd.presentation.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * The Material 3 sub-screen top app bar (DESIGN.md "Components"): Back, a one-line `heading-20`
 * title with an optional subtitle, and trailing actions (icon or text buttons). No container
 * fill or divider; the bar sits on the page surface.
 */
@Composable
fun SubScreenTopBar(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    backButtonModifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .padding(horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = backButtonModifier.size(GeistSizes.minimumTouchTarget)) {
                Icon(
                    Icons.AutoMirrored.Outlined.ArrowBack,
                    contentDescription = stringResource(R.string.back),
                    tint = colors.primary,
                )
            }
        }
        Column(
            Modifier
                .weight(1f)
                .padding(
                    start = if (onBack != null) GeistSpacing.space1 else GeistSpacing.space3,
                    end = GeistSpacing.space1,
                    top = GeistSpacing.space2,
                    bottom = GeistSpacing.space2,
                ),
        ) {
            Text(
                title,
                style = GeistType.heading20,
                color = colors.primary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            subtitle?.let {
                Text(it, style = GeistType.copy13, color = colors.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        actions()
    }
}

/**
 * A full sub-screen: [SubScreenTopBar], then [content] centered at the readable width, then an
 * optional pinned [bottomBar] (for a screen's single filled primary action). Content owns its
 * own scrolling and the 16dp side gutter.
 */
@Composable
fun SubScreen(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    backButtonModifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: (@Composable () -> Unit)? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    Column(modifier.fillMaxSize()) {
        SubScreenTopBar(title = title, onBack = onBack, subtitle = subtitle, backButtonModifier = backButtonModifier, actions = actions)
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentAlignment = Alignment.TopCenter,
        ) {
            Box(
                Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize(),
                content = content,
            )
        }
        bottomBar?.invoke()
    }
}
