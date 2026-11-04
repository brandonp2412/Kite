package chat.schildi.revenge.compose.composer

import androidx.compose.ui.text.input.TextFieldValue

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
