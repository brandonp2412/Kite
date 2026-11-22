package io.element.android.libraries.matrix.impl.notification

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotificationEditDetectorTest {
    @Test
    fun hidesMatrixReplacementWithBridgeFallback() {
        assertTrue(isMatrixReplacementEvent("""{"type":"m.room.message","content":{"body":"* Thanks, but I’m looking for a place with Gideo[edit fallback cut…]","m.relates_to":{"rel_type":"m.replace","event_id":"target"},"m.new_content":{"body":"Thanks, but I’m looking for a place with Gideon"}}}"""))
    }

    @Test
    fun ordinaryTextWithFallbackWordsStillDisplays() {
        assertFalse(isMatrixReplacementEvent("""{"type":"m.room.message","content":{"body":"* note [edit fallback cut…]"}}"""))
    }

    @Test
    fun otherRelationsAndMalformedEventsAreNotReplacements() {
        assertFalse(isMatrixReplacementEvent("""{"content":{"m.relates_to":{"rel_type":"m.annotation","event_id":"target"}}}"""))
        assertFalse(isMatrixReplacementEvent("""{"content":{"m.relates_to":{"event_id":"target"}}}"""))
        assertFalse(isMatrixReplacementEvent("not JSON"))
    }
}
