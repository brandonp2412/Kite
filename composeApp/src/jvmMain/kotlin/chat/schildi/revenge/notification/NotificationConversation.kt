package chat.schildi.revenge.notification

/** Treat a bridge room named after its sole sender like a direct conversation. */
internal fun isGroupNotification(
    isDirect: Boolean,
    isDm: Boolean,
    roomName: String?,
    senderName: String,
    senderId: String,
    previousSenderIds: List<String?>,
): Boolean {
    if (isDirect || isDm) return false
    val namesMatch = roomName?.trim()?.equals(senderName.trim(), ignoreCase = true) == true
    return !namesMatch || previousSenderIds.any { it != senderId }
}
