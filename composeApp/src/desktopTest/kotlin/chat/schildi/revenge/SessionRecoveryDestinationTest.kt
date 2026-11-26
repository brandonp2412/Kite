package chat.schildi.revenge

import chat.schildi.revenge.compose.sessionRecoveryDestination
import io.element.android.libraries.matrix.api.core.SessionId
import kotlin.test.Test
import kotlin.test.assertEquals

class SessionRecoveryDestinationTest {
    private val failed = SessionId("@failed:example.org")
    private val healthy = SessionId("@healthy:example.org")
    @Test fun revokedOnlyAccountOpensRecoveryInsteadOfBlankInbox() {
        assertEquals(Destination.AccountManagement(isInitialSetup = false),
            sessionRecoveryDestination(Destination.Inbox, true, emptySet(), setOf(failed)))
    }
    @Test fun healthyAccountInboxRemainsAccessible() {
        assertEquals(Destination.Inbox,
            sessionRecoveryDestination(Destination.Inbox, true, setOf(healthy), setOf(failed)))
    }
    @Test fun recoveryDisappearsWhenLoginSucceeds() {
        assertEquals(Destination.Inbox,
            sessionRecoveryDestination(Destination.Inbox, true, setOf(failed), emptySet()))
    }
    @Test fun noRecoveryDuringInitialRestore() {
        assertEquals(Destination.Inbox,
            sessionRecoveryDestination(Destination.Inbox, false, emptySet(), setOf(failed)))
    }
}
