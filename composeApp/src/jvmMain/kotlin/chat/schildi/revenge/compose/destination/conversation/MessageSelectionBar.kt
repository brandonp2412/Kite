package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.runtime.Composable
import chat.schildi.revenge.compose.components.TopNavigationIcon
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_copy_body
import shire.res.generated.resources.action_forward
import shire.res.generated.resources.action_redact
import shire.res.generated.resources.action_reply
import shire.res.generated.resources.action_retry
import shire.res.generated.resources.action_show_more

data class MessageSelectionActions(
    val selectedCount: Int,
    val canReply: Boolean,
    val canRetry: Boolean,
    val canForward: Boolean,
    val canDelete: Boolean,
    val onReply: () -> Unit,
    val onRetry: () -> Unit,
    val onCopy: () -> Unit,
    val onForward: () -> Unit,
    val onDelete: () -> Unit,
    val onMore: () -> Unit,
)

/**
 * Google Messages keeps multi-select actions in the contextual top app bar.
 * Keeping these actions icon-only also avoids a second bottom surface fighting
 * the composer/system-navigation region on compact phones.
 */
@Composable
fun RowScope.MessageSelectionActions(actions: MessageSelectionActions) {
    if (actions.canRetry) {
        TopNavigationIcon(
            Icons.Default.Refresh,
            stringResource(Res.string.action_retry),
            onClick = actions.onRetry,
        )
    } else if (actions.canReply && actions.selectedCount == 1) {
        TopNavigationIcon(
            Icons.AutoMirrored.Default.Reply,
            stringResource(Res.string.action_reply),
            onClick = actions.onReply,
        )
    }

    TopNavigationIcon(
        Icons.Default.ContentCopy,
        stringResource(Res.string.action_copy_body),
        onClick = actions.onCopy,
    )

    if (actions.canForward) {
        TopNavigationIcon(
            Icons.AutoMirrored.Default.Forward,
            stringResource(Res.string.action_forward),
            onClick = actions.onForward,
        )
    }

    if (actions.selectedCount == 1) {
        TopNavigationIcon(
            Icons.Default.MoreHoriz,
            stringResource(Res.string.action_show_more),
            onClick = actions.onMore,
        )
    } else if (actions.canDelete) {
        TopNavigationIcon(
            Icons.Default.Delete,
            stringResource(Res.string.action_redact),
            onClick = actions.onDelete,
        )
    }
}
