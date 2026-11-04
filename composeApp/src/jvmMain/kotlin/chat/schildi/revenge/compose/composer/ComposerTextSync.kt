package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.text.input.TextFieldValue
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged

/** Read the actual committed edit, after the IME transaction finishes. */
internal fun TextFieldState.committedComposerEdits(): Flow<TextFieldValue> =
    snapshotFlow { TextFieldValue(text.toString(), selection) }.distinctUntilChanged()

private fun TextFieldValue.sameTextAndSelection(other: TextFieldValue): Boolean =
    text == other.text && selection == other.selection

/**
 * The StateFlow collected by Compose can be a frame behind the keyboard. Do not
 * overwrite its in-flight text until the draft has acknowledged that edit.
 */
internal class ComposerTextSync(initial: TextFieldValue) {
    private var latestEditor = initial
    private var pendingKeyboardEdit: TextFieldValue? = null

    fun recordKeyboardEdit(value: TextFieldValue) {
        latestEditor = value
        pendingKeyboardEdit = value
    }

    // A snapshot collector may be delayed behind a newer IME edit or an
    // external autocomplete. Only forward the currently pending keyboard edit.
    fun shouldPublishCommittedValue(value: TextFieldValue): Boolean =
        pendingKeyboardEdit?.sameTextAndSelection(value) == true

    fun shouldApplyExternalValue(composed: TextFieldValue, live: TextFieldValue?): Boolean {
        pendingKeyboardEdit?.let { pending ->
            if (live == null || !live.sameTextAndSelection(pending) ||
                !composed.sameTextAndSelection(pending)
            ) {
                return false
            }
            pendingKeyboardEdit = null
        }
        return live != null &&
            composed.sameTextAndSelection(live) &&
            !composed.sameTextAndSelection(latestEditor)
    }

    fun recordExternalValue(value: TextFieldValue) {
        latestEditor = value
    }
}
