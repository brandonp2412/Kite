package chat.schildi.revenge.push

import io.element.android.libraries.matrix.api.exception.NotificationResolverException

/** Event-not-found can be temporary while a homeserver or SDK catches up. */
internal object PushResolutionPolicy {
    const val NOT_FOUND_RETRY_WINDOW_MILLIS = 24 * 60 * 60 * 1000L

    fun isTerminalFailure(exception: NotificationResolverException?, ageMillis: Long): Boolean = when (exception) {
        NotificationResolverException.EventFilteredOut,
        NotificationResolverException.EventRedacted -> true
        NotificationResolverException.EventNotFound -> ageMillis >= NOT_FOUND_RETRY_WINDOW_MILLIS
        null, is NotificationResolverException.UnknownError -> false
    }
}
