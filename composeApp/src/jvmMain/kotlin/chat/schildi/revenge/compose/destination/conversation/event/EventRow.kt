package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import chat.schildi.revenge.DateTimeFormat
import chat.schildi.revenge.LocalTimeDisplayFormat
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.actions.CopyActions
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.HierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.compose.components.ContextMenuPresentation
import chat.schildi.revenge.compose.components.LocalTouchTextSelectionEnabled
import chat.schildi.revenge.compose.components.WithContextMenu
import chat.schildi.revenge.compose.destination.conversation.event.message.timestampOverlayContent
import chat.schildi.revenge.compose.destination.conversation.event.reaction.ReactionsRow
import chat.schildi.revenge.compose.destination.conversation.event.reaction.ReactionPickerDialog
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.compose.focus.rememberFocusId
import chat.schildi.revenge.model.conversation.ConversationPermissions
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.model.conversation.MessageMetadata
import chat.schildi.revenge.plaintext.EventTextFormat
import com.beeper.android.messageformat.MatrixFormatInteractionState
import com.beeper.android.messageformat.rememberMatrixFormatInteractionState
import io.element.android.libraries.matrix.api.core.ThreadId
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.RoomMember
import io.element.android.libraries.matrix.api.timeline.item.EventThreadInfo
import io.element.android.libraries.matrix.api.timeline.item.event.EventContent
import io.element.android.libraries.matrix.api.timeline.item.event.EventOrTransactionId
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent
import io.element.android.libraries.matrix.api.timeline.item.event.MessageTypeWithAttachment
import io.element.android.libraries.matrix.api.timeline.item.event.UnknownContent
import kotlinx.collections.immutable.ImmutableMap
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_deselect_message
import shire.res.generated.resources.action_select_message

enum class EventHighlight {
    NONE,
    ACTION_TARGET,
}

@Composable
fun EventRow(
    viewModel: ConversationViewModel,
    event: EventTimelineItem,
    messageMetadata: MessageMetadata?,
    roomPermissions: ConversationPermissions?,
    currentThreadId: ThreadId?,
    isSameAsPreviousSender: Boolean,
    isSameAsNextSender: Boolean,
    showSenderDetails: Boolean,
    roomMembersById: ImmutableMap<UserId, RoomMember>,
    highlight: EventHighlight,
    doubleTapToReact: Boolean,
    doubleTapReaction: String,
    swipeConfig: MessageSwipeConfig,
    selectionActive: Boolean,
    isSelected: Boolean,
    isPinned: Boolean,
    canPin: Boolean,
    showReadReceipts: Boolean,
    onToggleSelection: () -> Unit,
    onForward: () -> Unit,
    onShowInfo: () -> Unit,
    modifier: Modifier = Modifier
) {
    val backgroundHighlightColor = animateColorAsState(
        if (highlight == EventHighlight.ACTION_TARGET) {
            MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
        } else {
            Color.Transparent
        }
    ).value
    val focusId = rememberFocusId()
    var reactionPickerOpen by remember { mutableStateOf(false) }
    val keyboardHandler = LocalKeyboardActionHandler.current
    val formatInteractionState = messageMetadata?.preFormattedContent?.let {
        rememberMatrixFormatInteractionState(it)
    }
    val selectable = event.isKiteSelectableMessage()
    val timeFormat = LocalTimeDisplayFormat.current
    val timestamp = remember(event) { event.timestampOverlayContent() }
    val toggleSelection = remember(onToggleSelection) {
        { onToggleSelection() }
    }
    val canDoubleTapReact = !selectionActive && doubleTapToReact &&
            event.content is MessageContent &&
            (roomPermissions?.canSendReactions ?: false)
    WithContextMenu(
        focusId,
        event.contextMenu(
            permissions = roomPermissions,
            isSelected = isSelected,
            onToggleSelection = toggleSelection.takeIf { selectable },
        ),
        presentation = ContextMenuPresentation.Message,
        onComposeReaction = { reactionPickerOpen = true },
        messageTimestamp = if (selectable) remember(event.timestamp, timeFormat) {
            DateTimeFormat.formatFullDateTime(
                DateTimeFormat.timestampToDateTime(event.timestamp), timeFormat,
            )
        } else null,
    ) { openContextMenu ->
        val messageActionMenuOpen = LocalTouchTextSelectionEnabled.current
        // Child content (links, media, polls and reaction chips) has its own click
        // targets. In selection mode place one hit target *above* all of them,
        // so touching any part of this message toggles selection exactly once.
        // matchParentSize does not change the row's measured size or scroll offset.
        Box(Modifier.fillMaxWidth()) {
            Column(
                modifier
                .keyFocusable(
                    FocusRole.LIST_ITEM,
                    focusId,
                    actionProvider = actionProvider(
                        keyActions = eventRowKeyboardActionProvider(
                            viewModel,
                            event,
                            messageMetadata,
                            formatInteractionState,
                        ),
                        primaryAction = if (selectionActive && selectable) {
                            InteractionAction.Invoke {
                                toggleSelection()
                                true
                            }
                        } else {
                            eventClickAction(viewModel, currentActionContext(), event)
                        },
                        secondaryAction = openContextMenu,
                        copyActions = eventCopyActions(event, messageMetadata),
                    ),
                    // Once the Messages-style action surface is visible, pointer
                    // gestures belong to the message content itself: a second
                    // long-press selects text and handle drags refine that range.
                    // Keep keyboard/focus actions installed, but remove this row's
                    // click/long-click detector while the menu or selection overlay
                    // takes ownership of pointer taps.
                    addClickListener = !messageActionMenuOpen && !selectionActive,
                )
                .background(
                    if (isSelected) {
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.28f)
                    } else {
                        backgroundHighlightColor
                    },
                    Dimens.Conversation.messageBubbleShape,
                )
                .padding(horizontal = Dimens.Conversation.timelineHorizontalPadding)
        ) {
            val threadInfo = event.threadInfo()
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
            ) {
                if (selectionActive && selectable) {
                    MessageSelectionIndicator(
                        selected = isSelected,
                        onClick = toggleSelection,
                    )
                }
                Box(Modifier.weight(1f)) {
                    Column(Modifier.fillMaxWidth().animateContentSize()) {
                        EventSwipeable(
                            focusId = focusId,
                            isOwn = event.isOwn,
                            swipeConfig = swipeConfig,
                            enabled = !selectionActive && !messageActionMenuOpen,
                        ) { modifier ->
                            EventContentLayout(
                                eventId = event.eventId,
                                content = event.content,
                                messageMetadata = messageMetadata,
                                formatInteractionState = formatInteractionState,
                                senderId = event.sender,
                                senderProfile = event.senderProfile,
                                isOwn = event.isOwn,
                                showSenderDetails = showSenderDetails,
                                timestamp = timestamp,
                                isSameAsPreviousSender = isSameAsPreviousSender,
                                isSameAsNextSender = isSameAsNextSender,
                                inReplyTo = event.inReplyTo(),
                                threadInfo = threadInfo,
                                roomMembersById = roomMembersById,
                                timelineItemDebugInfoProvider = event.timelineItemDebugInfoProvider,
                                modifier = modifier,
                                messageContentModifier = Modifier.passiveDoubleTapReaction(
                                    focusId = focusId,
                                    enabled = canDoubleTapReact && !messageActionMenuOpen,
                                    singleTapEnabled = false,
                                    reaction = doubleTapReaction,
                                    reactionActive = event.reactions.any { reaction ->
                                        reaction.key == doubleTapReaction && reaction.senders.any { sender ->
                                            sender.senderId.value == viewModel.sessionId.value
                                        }
                                    },
                                    onSingleTap = {},
                                ),
                            )
                        }
                        ReactionsRow(
                            viewModel = viewModel,
                            eventOrTransactionId = EventOrTransactionId.from(event.eventId, event.transactionId),
                            reactions = event.reactions,
                            roomMembersById = roomMembersById,
                            messageIsOwn = event.isOwn,
                            showSenderDetails = showSenderDetails,
                        )
                        if (threadInfo is EventThreadInfo.ThreadRoot && event.eventId?.value != currentThreadId?.value) {
                            ThreadRootInfoRow(
                                threadInfo = threadInfo,
                                sessionId = viewModel.sessionId,
                                roomId = viewModel.roomId,
                                eventId = event.eventId,
                                messageIsOwn = event.isOwn,
                                showSenderDetails = showSenderDetails,
                            )
                        }
                        if (showReadReceipts) {
                            ReadReceiptsRow(
                                receipts = event.receipts,
                                roomMembersById = roomMembersById,
                            )
                        }
                    }
                }
            }
            }
            if (selectionActive && selectable) {
                Box(
                    Modifier
                        .matchParentSize()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClickLabel = stringResource(
                                if (isSelected) Res.string.action_deselect_message
                                else Res.string.action_select_message
                            ),
                            onClick = toggleSelection,
                        ),
                )
            }
        }
    }
    if (reactionPickerOpen) {
        ReactionPickerDialog(
            onDismiss = { reactionPickerOpen = false },
            onSelect = { emoji ->
                reactionPickerOpen = false
                keyboardHandler.handleAction(focusId, Action.Event.ToggleReactionKey, listOf(emoji))
            },
        )
    }
}

@Composable
private fun eventRowKeyboardActionProvider(
    viewModel: ConversationViewModel,
    event: EventTimelineItem,
    messageMetadata: MessageMetadata?,
    formatInteractionState: MatrixFormatInteractionState?,
): HierarchicalKeyboardActionProvider {
    val ownHandler = remember(viewModel, event) {
        viewModel.getKeyboardActionProviderForEvent(event, messageMetadata, formatInteractionState)
    }
    return ownHandler.hierarchicalKeyboardActionProvider()
}

@Composable
private fun eventClickAction(
    viewModel: ConversationViewModel,
    context: ActionContext,
    event: EventTimelineItem,
): InteractionAction? = remember(viewModel, context, event) {
    when (val content = event.content) {
        is MessageContent -> {
            when (content.type) {
                is MessageTypeWithAttachment -> InteractionAction.Invoke {
                    viewModel.downloadFileAndOpen(context, event) is ActionResult.Success
                }
                else -> null
            }
        }
        else -> null
    }
}

@Composable
private fun eventCopyActions(
    event: EventTimelineItem,
    messageMetadata: MessageMetadata?,
) = remember(event, messageMetadata) {
    CopyActions(
        accessPlaintextSuspend = {
            if (event.content.isPlaintextCopyable()) {
                EventTextFormat.eventToTextSuspend(
                    content = event.content,
                    messageMetadata = messageMetadata,
                    senderProfile = event.senderProfile,
                    senderId = event.sender,
                )
            } else {
                null
            }
        },
        accessUserId = { event.sender.value },
    )
}

private fun EventContent.isPlaintextCopyable() = when (this) {
    // There's literally no content attached to UnknownContent right now, copying doesn't make much sense.
    UnknownContent -> false
    else -> true
}
