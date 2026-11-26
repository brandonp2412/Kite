package io.element.android.libraries.matrix.impl.verification

import io.element.android.libraries.matrix.api.verification.SessionVerifiedStatus
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

class VerificationCompletionTest {
    @Test fun unverifiedSessionReturnsFailureInsteadOfCancellingCompletion() = runTest {
        val status = MutableStateFlow<SessionVerifiedStatus>(SessionVerifiedStatus.NotVerified)
        assertFalse(awaitVerifiedSession(status, 1.seconds))
    }
    @Test fun onlySdkVerifiedStateCompletesSuccessfully() = runTest {
        val status = MutableStateFlow<SessionVerifiedStatus>(SessionVerifiedStatus.NotVerified)
        launch { delay(100); status.value = SessionVerifiedStatus.Verified }
        assertTrue(awaitVerifiedSession(status, 1.seconds))
    }
}
