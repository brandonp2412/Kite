package chat.schildi.revenge.notification

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NotificationCodeExtractorTest {
    @Test
    fun extractsExplicitVerificationCode() {
        assertEquals("482913", extractNotificationVerificationCode("Your verification code is 482913."))
        assertEquals("7314", extractNotificationVerificationCode("PIN: 7314"))
    }

    @Test
    fun acceptsNumericOnlySixDigitCodeWithoutHint() {
        assertEquals("654321", extractNotificationVerificationCode("654321"))
    }

    @Test
    fun rejectsOrdinaryNumbersWithoutCodeContext() {
        assertNull(extractNotificationVerificationCode("Meet at 1234 Queen Street"))
        assertNull(extractNotificationVerificationCode("Order 123456"))
        assertNull(extractNotificationVerificationCode("Order 123456 costs 789012 cents"))
    }

    @Test
    fun doesNotMatchInsideLongerNumbers() {
        assertNull(extractNotificationVerificationCode("Reference 123456789"))
    }
}
