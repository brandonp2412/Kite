package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Gesture
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.StringResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_download
import shire.res.generated.resources.action_edit
import shire.res.generated.resources.action_message_info
import shire.res.generated.resources.action_pin
import shire.res.generated.resources.action_redact
import shire.res.generated.resources.action_report_message
import shire.res.generated.resources.action_thread
import shire.res.generated.resources.action_unpin

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageSelectionMoreSheet(
    canEdit: Boolean,
    canOpenThread: Boolean,
    canPin: Boolean,
    isPinned: Boolean,
    canDownload: Boolean,
    canReport: Boolean,
    canDelete: Boolean,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onOpenThread: () -> Unit,
    onTogglePin: () -> Unit,
    onDownload: () -> Unit,
    onInfo: () -> Unit,
    onReport: () -> Unit,
    onDelete: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        if (canEdit) {
            SelectionMoreAction(Res.string.action_edit, { Icon(Icons.Default.Edit, null) }) {
                onDismiss()
                onEdit()
            }
        }
        if (canOpenThread) {
            SelectionMoreAction(Res.string.action_thread, { Icon(Icons.Default.Gesture, null) }) {
                onDismiss()
                onOpenThread()
            }
        }
        if (canPin) {
            SelectionMoreAction(
                if (isPinned) Res.string.action_unpin else Res.string.action_pin,
                { Icon(Icons.Default.PushPin, null) },
            ) {
                onDismiss()
                onTogglePin()
            }
        }
        if (canDownload) {
            SelectionMoreAction(Res.string.action_download, { Icon(Icons.Default.Download, null) }) {
                onDismiss()
                onDownload()
            }
        }
        SelectionMoreAction(Res.string.action_message_info, { Icon(Icons.Default.Info, null) }) {
            onDismiss()
            onInfo()
        }
        if (canReport) {
            SelectionMoreAction(
                Res.string.action_report_message,
                { Icon(Icons.Outlined.Shield, null, tint = MaterialTheme.colorScheme.error) },
                color = MaterialTheme.colorScheme.error,
            ) {
                onDismiss()
                onReport()
            }
        }
        if (canDelete) {
            SelectionMoreAction(
                Res.string.action_redact,
                { Icon(Icons.Default.Delete, null, tint = MaterialTheme.colorScheme.error) },
                color = MaterialTheme.colorScheme.error,
            ) {
                onDismiss()
                onDelete()
            }
        }
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun SelectionMoreAction(
    label: StringResource,
    icon: @Composable () -> Unit,
    color: Color = MaterialTheme.colorScheme.onSurface,
    onClick: () -> Unit,
) {
    val destructive = color == MaterialTheme.colorScheme.error
    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        shape = MaterialTheme.shapes.large,
        color = if (destructive) {
            MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.58f)
        } else {
            MaterialTheme.colorScheme.surfaceContainer
        },
        contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                modifier = Modifier.size(40.dp),
                shape = MaterialTheme.shapes.extraLarge,
                color = if (destructive) {
                    MaterialTheme.colorScheme.errorContainer
                } else {
                    MaterialTheme.colorScheme.surfaceContainerHighest
                },
                contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    icon()
                }
            }
            Text(
                text = stringResource(label),
                color = color,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}
