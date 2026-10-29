package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.compose.destination.conversation.event.EventHighlight
import chat.schildi.revenge.compose.destination.conversation.event.EventRow
import chat.schildi.revenge.compose.destination.conversation.event.MessageSwipeConfig
import chat.schildi.revenge.compose.destination.conversation.virtual.DayHeaderRow
import chat.schildi.revenge.compose.destination.conversation.virtual.DebugLinePosition
import chat.schildi.revenge.compose.destination.conversation.virtual.TimelineItemDebugLine
import chat.schildi.revenge.compose.destination.conversation.virtual.TimelineItemDebugLineInstance
import chat.schildi.revenge.compose.destination.conversation.virtual.NewMessageLineInstance
import chat.schildi.revenge.compose.destination.conversation.virtual.NewMessagesLine
import chat.schildi.revenge.compose.destination.conversation.virtual.PagingIndicator
import chat.schildi.revenge.compose.destination.conversation.virtual.RoomBeginning
import chat.schildi.revenge.compose.destination.conversation.virtual.drawTimelineItemDebugLineBehind
import chat.schildi.revenge.model.conversation.ConversationPermissions
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.model.conversation.EventJumpTarget
import chat.schildi.revenge.model.conversation.FullyReadEventState
import chat.schildi.revenge.model.conversation.ScTimelineItem
import io.element.android.libraries.matrix.api.core.ThreadId
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.RoomMember
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.FailedToParseStateContent
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent
import io.element.android.libraries.matrix.api.timeline.item.event.ProfileChangeContent
import io.element.android.libraries.matrix.api.timeline.item.event.RoomMembershipContent
import io.element.android.libraries.matrix.api.timeline.item.event.StateContent
import io.element.android.libraries.matrix.api.timeline.item.event.UnknownContent
import io.element.android.libraries.matrix.api.timeline.item.event.perMessageProfile
import io.element.android.libraries.matrix.api.timeline.item.virtual.VirtualTimelineItem
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.ImmutableMap
import kotlinx.collections.immutable.persistentListOf

@Composable
fun ConversationItemRow(
    viewModel: ConversationViewModel,
    item: ScTimelineItem,
    roomMembersById: ImmutableMap<UserId, RoomMember>,
    next: ScTimelineItem?,
    previous: ScTimelineItem?,
    previousVisibleEvent: EventTimelineItem?,
    nextVisibleEvent: EventTimelineItem?,
    previousEvent: MatrixTimelineItem.Event?,
    fullyReadEvent: FullyReadEventState?,
    currentThreadId: ThreadId?,
    showSenderDetails: Boolean,
    targetEvent: EventJumpTarget?,
    roomPermissions: ConversationPermissions?,
    highlight: EventHighlight,
    doubleTapToReact: Boolean,
    doubleTapReaction: String,
    swipeConfig: MessageSwipeConfig,
    selectionActive: Boolean,
    isSelected: Boolean,
    isPinned: Boolean,
    canPin: Boolean,
    showReadReceipts: Boolean,
    onToggleSelection: (ScTimelineItem) -> Unit,
    onForward: (EventTimelineItem) -> Unit,
    onShowInfo: (EventTimelineItem) -> Unit,
    showBackwardPagingIndicator: Boolean,
    showForwardPagingIndicator: Boolean,
    isBackwardPaging: Boolean,
    isForwardPaging: Boolean,
    modifier: Modifier = Modifier,
    debugSeparatorLines: ImmutableList<TimelineItemDebugLineInstance> = persistentListOf(),
) {
    Column(modifier.fillMaxWidth()) {
        if (previous == null) {
            Spacer(Modifier.height(Dimens.windowPadding))
            if (showBackwardPagingIndicator) {
                PagingIndicator(isLoading = isBackwardPaging)
            }
        }
        debugSeparatorLines.filter { it.position == DebugLinePosition.Above }.forEach {
            TimelineItemDebugLine(it)
        }
        when (item.item) {
            is MatrixTimelineItem.Virtual -> {
                when (val virtualItem = item.item.virtual) {
                    is VirtualTimelineItem.DayDivider -> DayHeaderRow(virtualItem)
                    is VirtualTimelineItem.LoadingIndicator -> PagingIndicator(isLoading = isBackwardPaging || isForwardPaging)
                    VirtualTimelineItem.ReadMarker -> NewMessagesLine(
                        instance = NewMessageLineInstance.Sdk,
                        isThreadedTimeline = currentThreadId != null,
                    )
                    VirtualTimelineItem.RoomBeginning -> {}
                    // Not sure if we're supposed to render something for that one
                    VirtualTimelineItem.LastForwardIndicator -> {}
                    VirtualTimelineItem.TypingNotification -> TypingUsersRow(
                        viewModel.typingUsers.collectAsState(null).value ?: persistentListOf(),
                        roomMembersById,
                    )
                }
            }

            is MatrixTimelineItem.Event -> {
                if (item.item.event.isKiteServerEvent()) return@Column
                val isFirstUnreadEvent = fullyReadEvent?.has(previousEvent?.eventId) == true
                val showUnreadLine = isFirstUnreadEvent && (!item.item.event.isOwn || fullyReadEvent.usedAsJumpTarget)
                if (isFirstUnreadEvent || fullyReadEvent?.has(item.item.eventId) == true) {
                    // Changed target event clears the seen marker, so need to re-set if it changes
                    SideEffect(item.item.eventId, targetEvent) {
                        viewModel.markUnreadLineSeen()
                    }
                }
                if (showUnreadLine) {
                    NewMessagesLine(
                        instance = NewMessageLineInstance.ReadMarker,
                        isThreadedTimeline = currentThreadId != null,
                    )
                }

                // Raw neighbors may be invisible state events. Grouping and spacing
                // must follow the adjacent *rendered* messages instead.
                val directPreviousEvent = previousVisibleEvent
                val directNextEvent = nextVisibleEvent
                val previousSender = directPreviousEvent?.sender?.takeIf { !showUnreadLine }
                val isSameAsPreviousSender = previousSender == item.item.event.sender &&
                        directPreviousEvent.content is MessageContent &&
                        item.item.event.content is MessageContent &&
                        directPreviousEvent.content.perMessageProfile() == item.item.event.content.perMessageProfile()
                val isSameAsNextSender = directNextEvent?.sender == item.item.event.sender &&
                        directNextEvent.content is MessageContent &&
                        item.item.event.content is MessageContent &&
                        directNextEvent.content.perMessageProfile() == item.item.event.content.perMessageProfile()
                Spacer(Modifier.height(messageGapBeforeEvent(
                    hasOlderVisibleMessage = directPreviousEvent != null,
                    hasUnreadSeparator = showUnreadLine,
                )))
                EventRow(
                    viewModel,
                    item.item.event,
                    item.messageMetadata,
                    roomPermissions = roomPermissions,
                    currentThreadId = currentThreadId,
                    isSameAsPreviousSender = isSameAsPreviousSender,
                    isSameAsNextSender = isSameAsNextSender,
                    showSenderDetails = showSenderDetails,
                    roomMembersById = roomMembersById,
                    highlight = highlight,
                    doubleTapToReact = doubleTapToReact,
                    doubleTapReaction = doubleTapReaction,
                    swipeConfig = swipeConfig,
                    selectionActive = selectionActive,
                    isSelected = isSelected,
                    isPinned = isPinned,
                    canPin = canPin,
                    showReadReceipts = showReadReceipts,
                    onToggleSelection = { onToggleSelection(item) },
                    onForward = { onForward(item.item.event) },
                    onShowInfo = { onShowInfo(item.item.event) },
                    modifier = debugSeparatorLines.firstOrNull { it.position == DebugLinePosition.Start }?.let {
                        Modifier.drawTimelineItemDebugLineBehind(it)
                    } ?: Modifier,
                )
            }

            MatrixTimelineItem.Other -> {
                // TODO what is this?
                if (ScPrefs.VIEW_HIDDEN_EVENTS.value()) {
                    Text("OTHER???")
                }
            }
        }
        if (next == null) {
            if (showForwardPagingIndicator) {
                PagingIndicator(isLoading = isForwardPaging)
            }
            Spacer(Modifier.height(4.dp))
        }
    }
}


internal fun EventTimelineItem.isKiteServerEvent(): Boolean = when (content) {
    is RoomMembershipContent,
    is ProfileChangeContent,
    is StateContent,
    is FailedToParseStateContent,
    is UnknownContent -> true
    else -> false
}
