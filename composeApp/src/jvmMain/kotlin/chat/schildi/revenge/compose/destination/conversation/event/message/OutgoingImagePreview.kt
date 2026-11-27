package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.painter.Painter
import chat.schildi.revenge.model.Attachment
import chat.schildi.revenge.model.DraftValue
import io.element.android.libraries.matrix.api.core.UniqueId
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.ImageLikeMessageType
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent

/** A decoded composer preview is handed only to the new matching own timeline event. */
internal data class OutgoingImagePreview(
    val attachment: Attachment.Image,
    val painter: Painter,
    val draft: DraftValue,
    val previousEvent: UniqueId?,
    val startedAt: Long,
    val eventKey: UniqueId? = null,
) {
    fun matchesImage(image: ImageLikeMessageType): Boolean {
        val info = image.info ?: return false
        val expected = attachment.imageInfo
        return image.filename == attachment.file.name &&
            (info.size == expected.size || (info.size == null &&
                info.width == expected.width && info.height == expected.height))
    }

    fun matchesCandidate(item: MatrixTimelineItem.Event?): Boolean {
        if (item == null || !item.event.isOwn || item.uniqueId == previousEvent) return false
        val image = (item.event.content as? MessageContent)?.type as? ImageLikeMessageType ?: return false
        return item.event.timestamp >= startedAt - 5_000 &&
            item.event.timestamp <= startedAt + 60_000 && matchesImage(image)
    }
}
internal val LocalOutgoingImagePreview = compositionLocalOf<OutgoingImagePreview?> { null }
