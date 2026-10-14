package chat.schildi.revenge.model.conversation

import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.EventContent
import io.element.android.libraries.matrix.api.timeline.item.event.FailedToParseStateContent
import io.element.android.libraries.matrix.api.timeline.item.event.ProfileChangeContent
import io.element.android.libraries.matrix.api.timeline.item.event.RoomMembershipContent
import io.element.android.libraries.matrix.api.timeline.item.event.StateContent
import io.element.android.libraries.matrix.api.timeline.item.event.UnknownContent
import io.element.android.libraries.matrix.api.timeline.item.virtual.VirtualTimelineItem

/**
 * Filter *before* rendering and list indexing. Hiding a state event inside its
 * Composable leaves its SDK day separator behind as an empty dated row.
 */
internal fun MatrixTimelineItem.isKiteVisibleConversationItem(): Boolean = when (this) {
    is MatrixTimelineItem.Event -> event.content.isKiteVisibleMessageContent()
    is MatrixTimelineItem.Virtual -> virtual !is VirtualTimelineItem.DayDivider
    MatrixTimelineItem.Other -> false
}

internal fun EventContent.isKiteVisibleMessageContent(): Boolean = when (this) {
    is RoomMembershipContent,
    is ProfileChangeContent,
    is StateContent,
    is FailedToParseStateContent,
    is UnknownContent -> false
    else -> true
}
