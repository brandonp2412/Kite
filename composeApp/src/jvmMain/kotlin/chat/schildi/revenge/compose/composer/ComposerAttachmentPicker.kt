package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.util.filepicker.AttachmentPickerKind
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_attachment_camera
import shire.res.generated.resources.action_attachment_file
import shire.res.generated.resources.action_attachment_gallery

private val AttachmentActionShape = RoundedCornerShape(28.dp)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ComposerAttachmentPicker(
    availableKinds: Set<AttachmentPickerKind>,
    onPick: (AttachmentPickerKind) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AttachmentPickerKind.entries.forEach { kind ->
                    if (kind in availableKinds) {
                        val label = when (kind) {
                            AttachmentPickerKind.CAMERA -> stringResource(Res.string.action_attachment_camera)
                            AttachmentPickerKind.FILE -> stringResource(Res.string.action_attachment_file)
                            AttachmentPickerKind.GALLERY -> stringResource(Res.string.action_attachment_gallery)
                        }
                        val icon = when (kind) {
                            AttachmentPickerKind.CAMERA -> Icons.Default.CameraAlt
                            AttachmentPickerKind.FILE -> Icons.Default.UploadFile
                            AttachmentPickerKind.GALLERY -> Icons.Default.PhotoLibrary
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(width = 68.dp, height = 56.dp)
                                    .clip(AttachmentActionShape)
                                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                                    .clickable {
                                        onDismiss()
                                        onPick(kind)
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    imageVector = icon,
                                    contentDescription = label,
                                    tint = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.size(26.dp),
                                )
                            }
                            Spacer(Modifier.height(8.dp))
                            Text(
                                text = label,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
        }
    }
}
