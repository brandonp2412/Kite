package chat.schildi.revenge.push

import io.element.android.libraries.matrix.api.exception.NotificationResolverException
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PushResolutionPolicyTest {
    @Test fun missingResultRemainsRetryable() {
        assertFalse(PushResolutionPolicy.isTerminalFailure(null, 0))
        assertFalse(PushResolutionPolicy.isTerminalFailure(null, 999999999))
        assertFalse(PushResolutionPolicy.isTerminalFailure(NotificationResolverException.UnknownError("network"), 0))
    }

    @Test fun eventNotFoundRetriesDuringSyncLagThenExpires() {
        assertFalse(PushResolutionPolicy.isTerminalFailure(NotificationResolverException.EventNotFound, 0))
        assertFalse(PushResolutionPolicy.isTerminalFailure(
            NotificationResolverException.EventNotFound,
            PushResolutionPolicy.NOT_FOUND_RETRY_WINDOW_MILLIS - 1,
        ))
        assertTrue(PushResolutionPolicy.isTerminalFailure(
            NotificationResolverException.EventNotFound,
            PushResolutionPolicy.NOT_FOUND_RETRY_WINDOW_MILLIS,
        ))
    }

    @Test fun filteredAndRedactedAreTerminal() {
        assertTrue(PushResolutionPolicy.isTerminalFailure(NotificationResolverException.EventFilteredOut, 0))
        assertTrue(PushResolutionPolicy.isTerminalFailure(NotificationResolverException.EventRedacted, 0))
    }
}
