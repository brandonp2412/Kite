package chat.schildi.revenge

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.graphics.Color
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
}
