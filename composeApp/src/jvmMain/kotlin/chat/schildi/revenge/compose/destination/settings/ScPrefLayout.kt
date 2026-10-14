package chat.schildi.revenge.compose.destination.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPref
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.compose.focus.rememberFocusId
import chat.schildi.revenge.preferences.LocalScPreferencesStore
import chat.schildi.revenge.preferences.enabledState
import chat.schildi.revenge.preferences.value
import org.jetbrains.compose.resources.stringResource
import kotlin.uuid.Uuid

private val SettingsPreferenceShape = RoundedCornerShape(20.dp)

@Composable
fun <T> ScPref<T>.ScPrefLayout(
    modifier: Modifier = Modifier,
    clickAction: ((T) -> InteractionAction?) = { null },
    focusId: Uuid = rememberFocusId(),
    selectionAsSummary: Boolean = false,
    valueToString: @Composable (T) -> String = { it.toString() },
    secondaryContent: @Composable ((value: T, enabled: Boolean) -> Unit)? = null,
    trailing: @Composable ((value: T, enabled: Boolean) -> Unit)? = null,
) {
    val currentValue = value()
    val enabled = LocalScPreferencesStore.current.enabledState(this).value
    val secondaryText = summaryRes?.let { stringResource(it, valueToString(currentValue)) }
        ?: currentValue.takeIf { selectionAsSummary }?.let { valueToString(it) }
    ScPrefRow(
        title = stringResource(titleRes),
        secondaryText = secondaryText,
        enabled = enabled,
        modifier = modifier.preferenceRowModifier(
            focusId = focusId,
            enabled = enabled,
            primaryAction = clickAction(currentValue),
            copyText = sKey,
        ),
        secondaryContent = secondaryContent?.let { content ->
            { content(currentValue, enabled) }
        },
        trailing = trailing?.let { content ->
            { content(currentValue, enabled) }
        },
    )
}

@Composable
fun ScPrefLayout(
    title: String,
    secondaryText: String? = null,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    clickAction: (() -> InteractionAction?) = { null },
    focusId: Uuid = rememberFocusId(),
    secondaryContent: @Composable ((enabled: Boolean) -> Unit)? = null,
    trailing: @Composable ((enabled: Boolean) -> Unit)? = null,
) {
    ScPrefRow(
        title = title,
        secondaryText = secondaryText,
        enabled = enabled,
        modifier = modifier.preferenceRowModifier(
            focusId = focusId,
            enabled = enabled,
            primaryAction = clickAction(),
            copyText = title,
        ),
        secondaryContent = secondaryContent?.let { content ->
            { content(enabled) }
        },
        trailing = trailing?.let { content ->
            { content(enabled) }
        },
    )
}

@Composable
private fun Modifier.preferenceRowModifier(
    focusId: Uuid,
    enabled: Boolean,
    primaryAction: InteractionAction?,
    copyText: String,
): Modifier = fillMaxWidth()
    .padding(horizontal = 16.dp, vertical = 3.dp)
    .clip(SettingsPreferenceShape)
    .keyFocusable(
        role = FocusRole.LIST_ITEM,
        id = focusId,
        actionProvider = actionProvider(
            primaryAction = if (enabled) primaryAction else null,
            copyActions = plainTextCopyAction { copyText },
        ),
        enableClicks = enabled,
    )

@Composable
private fun ScPrefRow(
    title: String,
    secondaryText: String?,
    enabled: Boolean,
    modifier: Modifier,
    secondaryContent: (@Composable () -> Unit)?,
    trailing: (@Composable () -> Unit)?,
) {
    val titleColor = if (enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    val secondaryColor = if (enabled) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
    }
    val hasSecondary = secondaryText != null || secondaryContent != null

    Surface(
        modifier = modifier,
        shape = SettingsPreferenceShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = if (hasSecondary) 80.dp else 68.dp)
                .padding(horizontal = 18.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = title,
                    color = titleColor,
                    style = MaterialTheme.typography.bodyLarge,
                )
                secondaryText?.let {
                    Text(
                        text = it,
                        color = secondaryColor,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                secondaryContent?.invoke()
            }
            trailing?.let {
                Spacer(Modifier.width(16.dp))
                Box(contentAlignment = Alignment.Center) {
                    it()
                }
            }
        }
    }
}

@Composable
fun ScPrefCategoryHeader(
    title: String,
    isFirst: Boolean = false,
    color: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    style: TextStyle = MaterialTheme.typography.labelLarge,
) {
    Column(Modifier.fillMaxWidth()) {
        Spacer(Modifier.height(if (isFirst) 10.dp else 16.dp))
        Text(
            text = title,
            style = style,
            color = color,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 8.dp),
        )
    }
}
