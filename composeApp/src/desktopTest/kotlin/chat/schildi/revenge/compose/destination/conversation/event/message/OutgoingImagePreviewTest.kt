package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.ColorPainter
import chat.schildi.revenge.model.Attachment
import chat.schildi.revenge.model.DraftValue
import io.element.android.libraries.matrix.api.media.ImageInfo
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.timeline.item.event.ImageMessageType
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OutgoingImagePreviewTest {
    private val info = ImageInfo(200, 100, "image/png", 1234, null, null, null)
    private val attachment = Attachment.Image(File("photo.png"), null, info)
    private val preview = OutgoingImagePreview(attachment, ColorPainter(Color.Red), DraftValue(), null, 0)
    private fun message(name: String = "photo.png", imageInfo: ImageInfo? = info) =
        ImageMessageType(name, null, null, MediaSource("mxc://example.test/image"), imageInfo)

    @Test fun matchesLocalAndRemoteImage() {
        assertTrue(preview.matchesImage(message()))
        assertTrue(preview.matchesImage(message(imageInfo = info.copy(size = null))))
    }

    @Test fun rejectsUnrelatedImages() {
        assertFalse(preview.matchesImage(message(name = "other.png")))
        assertFalse(preview.matchesImage(message(imageInfo = info.copy(size = 4321))))
        assertFalse(preview.matchesImage(message(imageInfo = info.copy(size = null, width = 999))))
        assertFalse(preview.matchesImage(message(imageInfo = null)))
    }
}
