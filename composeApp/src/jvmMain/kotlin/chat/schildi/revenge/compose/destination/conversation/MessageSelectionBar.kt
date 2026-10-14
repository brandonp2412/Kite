package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.components.WithTooltip
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_close
import shire.res.generated.resources.action_copy_body
import shire.res.generated.resources.action_edit
import shire.res.generated.resources.action_redact
import shire.res.generated.resources.action_reply
import shire.res.generated.resources.selection_messages_count

@Composable
fun MessageSelectionBar(
    selectedCount: Int,
    canReply: Boolean,
    canEdit: Boolean,
    canDelete: Boolean,
    onClear: () -> Unit,
    onReply: () -> Unit,
    onCopy: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(modifier.fillMaxWidth(), tonalElevation = Dimens.windowPadding) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Dimens.horizontalItemPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            WithTooltip(stringResource(Res.string.action_close)) {
                IconButton(onClick = onClear) {
                    Icon(Icons.Default.Close, stringResource(Res.string.action_close))
                }
            }
            Text(
                text = stringResource(Res.string.selection_messages_count, selectedCount),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleMedium,
            )
            if (canReply) {
                WithTooltip(stringResource(Res.string.action_reply)) {
                    IconButton(onClick = onReply) {
                        Icon(Icons.AutoMirrored.Default.Reply, stringResource(Res.string.action_reply))
                    }
                }
            }
            WithTooltip(stringResource(Res.string.action_copy_body)) {
                IconButton(onClick = onCopy) {
                    Icon(Icons.Default.ContentCopy, stringResource(Res.string.action_copy_body))
                }
            }
            if (canEdit) {
                WithTooltip(stringResource(Res.string.action_edit)) {
                    IconButton(onClick = onEdit) {
                        Icon(Icons.Default.Edit, stringResource(Res.string.action_edit))
                    }
                }
            }
            if (canDelete) {
                WithTooltip(stringResource(Res.string.action_redact)) {
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Default.Delete, stringResource(Res.string.action_redact))
                    }
                }
            }
        }
    }
}
