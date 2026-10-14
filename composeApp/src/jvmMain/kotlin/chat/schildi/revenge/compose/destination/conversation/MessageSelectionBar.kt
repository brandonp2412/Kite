package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.StringResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_copy_body
import shire.res.generated.resources.action_forward
import shire.res.generated.resources.action_redact
import shire.res.generated.resources.action_reply
import shire.res.generated.resources.action_retry
import shire.res.generated.resources.action_show_more

@Composable
fun MessageSelectionBar(
    selectedCount: Int,
    canReply: Boolean,
    canRetry: Boolean,
    canForward: Boolean,
    canDelete: Boolean,
    onReply: () -> Unit,
    onRetry: () -> Unit,
    onCopy: () -> Unit,
    onForward: () -> Unit,
    onDelete: () -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 6.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (canReply) {
                SelectionAction(Icons.AutoMirrored.Default.Reply, Res.string.action_reply, onReply)
            }
            if (canRetry) {
                SelectionAction(Icons.Default.Refresh, Res.string.action_retry, onRetry)
            }
            SelectionAction(Icons.Default.ContentCopy, Res.string.action_copy_body, onCopy)
            if (canForward) {
                SelectionAction(Icons.AutoMirrored.Default.Forward, Res.string.action_forward, onForward)
            }
            if (canDelete && (selectedCount > 1 || canRetry)) {
                SelectionAction(Icons.Default.Delete, Res.string.action_redact, onDelete, destructive = true)
            }
            if (selectedCount == 1) {
                SelectionAction(Icons.Default.MoreHoriz, Res.string.action_show_more, onMore)
            }
        }
    }
}

@Composable
private fun SelectionAction(
    icon: ImageVector,
    label: StringResource,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
    TextButton(
        onClick = onClick,
        modifier = Modifier
            .widthIn(min = 68.dp)
            .heightIn(min = 56.dp),
        shape = MaterialTheme.shapes.extraLarge,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = contentColor,
            )
            Text(
                text = stringResource(label),
                modifier = Modifier.widthIn(max = 72.dp),
                color = contentColor,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
