package chat.schildi.revenge.notification

private val notificationNumericCode = Regex("""(?<!\d)\d{4,8}(?!\d)""")
private val notificationCodeHint = Regex(
    pattern = """\b(code|otp|verification|verify|passcode|pin|2fa|two[- ]factor)\b""",
    option = RegexOption.IGNORE_CASE,
)

/**
 * Returns a conservative verification code for a notification quick action.
 *
 * We only expose a code when the message explicitly looks code-related, or when
 * the message itself is a standalone six-digit number. This avoids turning ordinary
 * dates, prices, room numbers, or message counts into a misleading Copy code action.
 */
internal fun extractNotificationVerificationCode(text: String): String? {
    val candidates = notificationNumericCode.findAll(text).map { it.value }.toList()
    if (candidates.isEmpty()) return null
    if (notificationCodeHint.containsMatchIn(text)) return candidates.first()
    val candidate = candidates.singleOrNull() ?: return null
    val numericOnlyMessage = text.trim().trim('.', ',', ':', ';', '!', '?', '(', ')', '[', ']').trim()
    return candidate.takeIf { it.length == 6 && numericOnlyMessage == it }
}
