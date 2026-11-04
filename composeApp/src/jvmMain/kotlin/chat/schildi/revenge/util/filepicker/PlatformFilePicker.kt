package chat.schildi.revenge.util.filepicker

import chat.schildi.revenge.WindowId
import java.io.File

enum class AttachmentPickerKind {
    CAMERA,
    FILE,
    GALLERY,
}

data class FilePickerResult(
    val file: File,
    val mimeType: String? = null,
    val isAppOwned: Boolean = false,
)

expect val availableAttachmentPickerKinds: Set<AttachmentPickerKind>

expect object FilePicker {
    suspend fun requestFilePicker(
        title: String,
        windowId: WindowId,
        kind: AttachmentPickerKind = AttachmentPickerKind.FILE,
    ): Result<FilePickerResult?>
}
