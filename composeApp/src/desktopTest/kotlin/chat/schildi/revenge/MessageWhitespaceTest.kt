package chat.schildi.revenge

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.graphics.Color
import chat.schildi.revenge.model.conversation.trimLeadingBlankLines
import chat.schildi.revenge.model.conversation.trimTrailingWhitespace
import com.beeper.android.messageformat.MatrixBodyParseResult
import kotlin.test.Test
import kotlin.test.assertEquals

class MessageWhitespaceTest {
    @Test
    fun removesBridgeFooterButPreservesInternalAndLeadingWhitespace() {
        val body = MatrixBodyParseResult("  First line\n\nSecond line\n \n  ")
        assertEquals("  First line\n\nSecond line", body.trimTrailingWhitespace().text.text)
    }

    @Test
    fun preservesFormattingWhenRemovingFooter() {
        val text = AnnotatedString.Builder().apply {
            pushStyle(SpanStyle(color = Color.Red))
            append("Caption")
            pop()
            append("\n  ")
        }.toAnnotatedString()
        val result = MatrixBodyParseResult(text).trimTrailingWhitespace().text
        assertEquals("Caption", result.text)
        assertEquals(text.spanStyles, result.spanStyles)
    }
    @Test
    fun removesLeadingEmptyParagraphsButKeepsIndentationAndInternalSpacing() {
        val body = MatrixBodyParseResult(" \n\t\r\n  First line\n\n Second line\n")
        assertEquals(
            "  First line\n\n Second line",
            body.trimTrailingWhitespace().trimLeadingBlankLines().text.text,
        )
    }

    @Test
    fun preservesFormattingWhenRemovingLeadingBlankLine() {
        val text = AnnotatedString.Builder().apply {
            append("\n")
            pushStyle(SpanStyle(color = Color.Red))
            append("Message")
            pop()
        }.toAnnotatedString()
        val trimmed = MatrixBodyParseResult(text).trimLeadingBlankLines().text
        assertEquals("Message", trimmed.text)
        assertEquals(text.subSequence(1, text.length).spanStyles, trimmed.spanStyles)
    }

}
