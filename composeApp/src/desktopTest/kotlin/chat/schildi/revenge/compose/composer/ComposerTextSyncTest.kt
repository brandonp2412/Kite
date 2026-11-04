package chat.schildi.revenge.compose.composer

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ComposerTextSyncTest {
    @Test
    fun staleCollectedDraftCannotEraseNewerKeyboardInputEvenIfLiveFlowLags() {
        val stale = TextFieldValue("hello", TextRange(5))
        val typed = TextFieldValue("hello world", TextRange(11))
        val sync = ComposerTextSync(stale)
        sync.recordKeyboardEdit(typed)

        assertFalse(sync.shouldApplyExternalValue(stale, stale))
        assertFalse(sync.shouldApplyExternalValue(stale, typed))
        assertFalse(sync.shouldApplyExternalValue(typed, typed)) // Acknowledge the IME edit
    }

    @Test
    fun intermediateRapidTypingUpdatesCannotReplaceNewestInput() {
        val first = TextFieldValue("a", TextRange(1))
        val second = TextFieldValue("ab", TextRange(2))
        val third = TextFieldValue("abc", TextRange(3))
        val sync = ComposerTextSync(first)
        sync.recordKeyboardEdit(second)
        sync.recordKeyboardEdit(third)

        assertFalse(sync.shouldApplyExternalValue(second, second))
        assertFalse(sync.shouldApplyExternalValue(second, third))
        assertFalse(sync.shouldApplyExternalValue(third, third))
    }

    @Test
    fun externalCompletionsAndCursorChangesStillSyncAfterAcknowledgement() {
        val typed = TextFieldValue("@ty", TextRange(3))
        val completion = TextFieldValue("@tyla ", TextRange(6))
        val movedCursor = TextFieldValue("@tyla ", TextRange(0))
        val sync = ComposerTextSync(TextFieldValue())
        sync.recordKeyboardEdit(typed)
        assertFalse(sync.shouldApplyExternalValue(typed, typed))

        assertTrue(sync.shouldApplyExternalValue(completion, completion))
        sync.recordExternalValue(completion)
        assertTrue(sync.shouldApplyExternalValue(movedCursor, movedCursor))
        sync.recordExternalValue(movedCursor)
        assertFalse(sync.shouldApplyExternalValue(movedCursor, movedCursor))
    }

    @Test
    fun unreadableOrNonCurrentDraftIsNotMirrored() {
        val typed = TextFieldValue("new", TextRange(3))
        val sync = ComposerTextSync(typed)
        assertFalse(sync.shouldApplyExternalValue(TextFieldValue(), null))
        assertFalse(sync.shouldApplyExternalValue(TextFieldValue(), typed))
    }
}
