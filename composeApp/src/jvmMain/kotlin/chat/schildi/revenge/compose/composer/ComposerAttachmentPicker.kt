package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import chat.schildi.revenge.util.filepicker.AttachmentPickerKind
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_attachment_camera
import shire.res.generated.resources.action_attachment_file
import shire.res.generated.resources.action_attachment_gallery

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ComposerAttachmentPicker(
    availableKinds: Set<AttachmentPickerKind>,
    onPick: (AttachmentPickerKind) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column {
            AttachmentPickerKind.entries.forEach { kind ->
                if (kind in availableKinds) {
                    val label = when (kind) {
                        AttachmentPickerKind.CAMERA -> stringResource(Res.string.action_attachment_camera)
                        AttachmentPickerKind.FILE -> stringResource(Res.string.action_attachment_file)
                        AttachmentPickerKind.GALLERY -> stringResource(Res.string.action_attachment_gallery)
                    }
                    ListItem(
                        headlineContent = { Text(label) },
                        leadingContent = {
                            Icon(
                                imageVector = when (kind) {
                                    AttachmentPickerKind.CAMERA -> Icons.Default.CameraAlt
                                    AttachmentPickerKind.FILE -> Icons.Default.UploadFile
                                    AttachmentPickerKind.GALLERY -> Icons.Default.PhotoLibrary
                                },
                                contentDescription = null,
                            )
                        },
                        modifier = Modifier.clickable {
                            onDismiss()
                            onPick(kind)
                        },
                    )
                }
            }
        }
    }
}
