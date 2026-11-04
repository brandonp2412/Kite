package chat.schildi.revenge.util.filepicker

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertNull

class AttachmentPickerKindTest {
    @Test
    fun gifActionRequestsOnlyGifFiles() {
        assertContentEquals(arrayOf("image/gif"), AttachmentPickerKind.GIF.documentMimeTypes())
    }

    @Test
    fun existingAttachmentActionsKeepTheirMimeFilters() {
        assertContentEquals(arrayOf("*/*"), AttachmentPickerKind.FILE.documentMimeTypes())
        assertContentEquals(arrayOf("image/*", "video/*"), AttachmentPickerKind.GALLERY.documentMimeTypes())
        assertNull(AttachmentPickerKind.CAMERA.documentMimeTypes())
    }
}
