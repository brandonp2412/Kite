package chat.schildi.revenge.notification

import io.element.android.libraries.matrix.api.room.RoomInfo

/** Only read-state fields that can change when another Matrix client reads a room. */
internal data class NotificationReadState(
    val unreadMessages: Long,
    val unreadNotifications: Long,
    val unreadCount: Long,
    val manuallyUnread: Boolean,
    val incompleteUnreadCount: Boolean,
    val fullyReadEventId: String?,
) {
    constructor(info: RoomInfo) : this(
        unreadMessages = info.numUnreadMessages,
        unreadNotifications = info.numUnreadNotifications,
        unreadCount = info.unreadCount,
        manuallyUnread = info.isMarkedUnread,
        incompleteUnreadCount = info.unreadCountUnderestimate,
        fullyReadEventId = info.fullyReadEventId?.value,
    )

    private val hasUnread: Boolean
        get() = manuallyUnread || unreadMessages > 0 || unreadNotifications > 0 || unreadCount > 0

    /** An initial zero can be stale. Require an observed change from unread to read. */
    fun becameReadSince(previous: NotificationReadState?): Boolean =
        previous != null && previous.hasUnread && !hasUnread && !incompleteUnreadCount
}
