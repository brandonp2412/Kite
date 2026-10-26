package chat.schildi.revenge.model.conversation

import chat.schildi.revenge.MessageFormatDefaults
import com.beeper.android.messageformat.MatrixBodyParseResult
import com.beeper.android.messageformat.MatrixBodyPreFormatStyle
import com.beeper.android.messageformat.MatrixHtmlParser
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.CanMentionRoom
import io.element.android.libraries.matrix.api.timeline.item.event.EventContent
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent
import io.element.android.libraries.matrix.api.timeline.item.event.MessageFormat
import io.element.android.libraries.matrix.api.timeline.item.event.MessageTypeWithAttachment
import io.element.android.libraries.matrix.api.timeline.item.event.TextLikeMessageType

data class MessageMetadata(
    val preFormattedContent: MatrixBodyParseResult? = null,
)

data class ScTimelineItem(
    val item: MatrixTimelineItem,
    val messageMetadata: MessageMetadata? = null,
)

/**
 * Potentially expensive message parsing included!
 * Avoid in UI thread if possible (but exceptions are probably ok).
 */
fun MatrixTimelineItem.toScTimelineItem(
    parser: MatrixHtmlParser,
    style: MatrixBodyPreFormatStyle,
): ScTimelineItem {
    return when (this) {
        is MatrixTimelineItem.Event -> {
            ScTimelineItem(this, event.content.messageMetadata(parser, style))
        }
        is MatrixTimelineItem.Virtual,
        MatrixTimelineItem.Other -> ScTimelineItem(this)
    }
}

/**
 * Potentially expensive message parsing included!
 * Avoid in UI thread if possible (but exceptions are probably ok).
 */
fun EventContent.messageMetadata(
    parser: MatrixHtmlParser = MessageFormatDefaults.parser,
    style: MatrixBodyPreFormatStyle = MessageFormatDefaults.parseStyle,
): MessageMetadata {
    val (formattedBody, plaintext, allowEmpty) = when (val type = (this as? MessageContent)?.type) {
        is TextLikeMessageType -> Triple(type.formatted, type.body, true)
        is MessageTypeWithAttachment -> Triple(type.formattedCaption, type.caption, false)
        else -> Triple(null, null, false)
    }
    val allowRoomMention = (this as? CanMentionRoom)?.isRoomMention ?: true
    val preFormattedContent = when {
        formattedBody?.format == MessageFormat.HTML -> {
            parser.parseHtml(formattedBody.body, style, allowRoomMention)
        }
        plaintext != null && (allowEmpty || plaintext.isNotEmpty()) -> {
            parser.parsePlaintext(renderTextEmoticons(plaintext), style, allowRoomMention)
        }
        else -> null
    }
    val content = preFormattedContent?.trimTrailingWhitespace()
    return MessageMetadata(if (allowEmpty) content?.trimLeadingBlankLines() else content)
}

// Bridges may append blank lines; they should not become bubble padding.
internal fun MatrixBodyParseResult.trimTrailingWhitespace(): MatrixBodyParseResult {
    val end = text.text.trimEnd().length
    return if (end == text.length) this else copy(text = text.subSequence(0, end))
}

// Ignore empty paragraphs before text without stripping meaningful indentation.
internal fun MatrixBodyParseResult.trimLeadingBlankLines(): MatrixBodyParseResult {
    val content = text.text
    var start = 0
    while (start < content.length) {
        var lineEnd = start
        while (lineEnd < content.length && (content[lineEnd] == ' ' || content[lineEnd] == '\t')) lineEnd++
        if (lineEnd < content.length && content[lineEnd] == '\r') lineEnd++
        if (lineEnd >= content.length || content[lineEnd] != '\n') break
        start = lineEnd + 1
    }
    return if (start == 0) this else copy(text = text.subSequence(start, content.length))
}
