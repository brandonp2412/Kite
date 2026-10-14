package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
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

/** A compact, labelled dock above the system navigation bar, not another full-width app bar. */
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
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f)),
        shadowElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Keep at most four labelled actions across a compact device.
            if (canRetry) {
                SelectionAction(Icons.Default.Refresh, Res.string.action_retry, onRetry)
            } else if (canReply) {
                SelectionAction(Icons.AutoMirrored.Default.Reply, Res.string.action_reply, onReply)
            }
            SelectionAction(Icons.Default.ContentCopy, Res.string.action_copy_body, onCopy)
            if (canForward) {
                SelectionAction(Icons.AutoMirrored.Default.Forward, Res.string.action_forward, onForward)
            }
            if (selectedCount == 1) {
                SelectionAction(Icons.Default.MoreHoriz, Res.string.action_show_more, onMore)
            } else if (canDelete) {
                SelectionAction(Icons.Default.Delete, Res.string.action_redact, onDelete, destructive = true)
            }
        }
    }
}

@Composable
private fun RowScope.SelectionAction(
    icon: ImageVector,
    label: StringResource,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 64.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 2.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = contentColor,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = stringResource(label),
            style = MaterialTheme.typography.labelSmall,
            color = contentColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}
