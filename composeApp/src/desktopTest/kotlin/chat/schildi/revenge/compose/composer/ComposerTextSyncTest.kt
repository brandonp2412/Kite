package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ComposerTextSyncTest {
    @Test
    fun rapidKeyboardEditsPublishOnlyCommittedEditorText() = runBlocking {
        val editor = TextFieldState()
        val observed = mutableListOf<TextFieldValue>()
        val collection = launch(start = CoroutineStart.UNDISPATCHED) {
            editor.committedComposerEdits().collect { observed += it }
        }
        // Multiple editor transactions can coalesce in the snapshot collector.
        // The final committed value must still contain every character.
        listOf("h", "he", "hel", "hell", "hello").forEach { text ->
            editor.edit {
                replace(0, length, text)
                selection = TextRange(text.length)
            }
        }
        Snapshot.sendApplyNotifications()
        withTimeout(2_000) {
            while (observed.last().text != "hello") delay(1)
        }
        collection.cancelAndJoin()
        assertEquals("hello", observed.last().text)
        assertEquals(TextRange(5), observed.last().selection)
    }

    @Test
    fun delayedEditorSnapshotsCannotOverwriteNewerKeyboardOrAutocomplete() {
        val initial = TextFieldValue("a", TextRange(1))
        val second = TextFieldValue("ab", TextRange(2))
        val third = TextFieldValue("abc", TextRange(3))
        val sync = ComposerTextSync(initial)
        assertFalse(sync.shouldPublishCommittedValue(initial))
        sync.recordKeyboardEdit(second)
        sync.recordKeyboardEdit(third)
        assertFalse(sync.shouldPublishCommittedValue(second))
        assertTrue(sync.shouldPublishCommittedValue(third))
        assertFalse(sync.shouldApplyExternalValue(third, third))
        assertFalse(sync.shouldPublishCommittedValue(third))

        val completion = TextFieldValue("autocomplete ", TextRange(13))
        assertTrue(sync.shouldApplyExternalValue(completion, completion))
        sync.recordExternalValue(completion)
        assertFalse(sync.shouldPublishCommittedValue(third))
        assertFalse(sync.shouldPublishCommittedValue(completion))
    }

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
