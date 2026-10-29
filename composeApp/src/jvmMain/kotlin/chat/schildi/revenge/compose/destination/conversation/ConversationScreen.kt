package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.notification.NotificationOpenPreview
import chat.schildi.revenge.notification.NotificationOpenPreviews
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.LocalMatrixBodyDrawStyle
import chat.schildi.revenge.LocalMatrixBodyFormatter
import chat.schildi.revenge.NavigationPreference
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.actions.LocalKeyboardActionProvider
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.LocalRoomContextSuggestionsProvider
import chat.schildi.revenge.actions.LocalUserIdSuggestionsProvider
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.composer.ComposerRow
import chat.schildi.revenge.compose.components.PlatformBackHandler
import chat.schildi.revenge.compose.destination.imeAwareBottomPadding
import chat.schildi.revenge.compose.destination.SplashScreenContent
import chat.schildi.revenge.compose.destination.conversation.event.EventHighlight
import chat.schildi.revenge.compose.destination.conversation.event.LocalHeartBurstState
import chat.schildi.revenge.compose.destination.conversation.event.drawHeartBurst
import chat.schildi.revenge.compose.destination.conversation.event.rememberHeartBurstState
import chat.schildi.revenge.compose.destination.conversation.event.isKiteSelectableMessage
import chat.schildi.revenge.compose.destination.conversation.event.kiteSelectionKey
import chat.schildi.revenge.compose.destination.conversation.event.resolveMessageSwipeConfig
import chat.schildi.revenge.compose.destination.conversation.event.message.MessageLayoutNormal
import chat.schildi.revenge.compose.destination.conversation.event.message.MessageBubble
import chat.schildi.revenge.compose.destination.conversation.event.message.LocalUrlPreviewStateProvider
import chat.schildi.revenge.compose.destination.conversation.virtual.PagingIndicator
import chat.schildi.revenge.compose.destination.split.requireSinglePaneLayout
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.shouldAutoRequestFocus
import chat.schildi.revenge.compose.search.LocalSearchProvider
import chat.schildi.revenge.compose.search.SearchBar
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.config.keybindings.DestinationEnum
import chat.schildi.revenge.matrixBodyDrawStyle
import chat.schildi.revenge.matrixBodyFormatter
import chat.schildi.revenge.model.CheckpointLoadState
import chat.schildi.revenge.model.MessageForward
import chat.schildi.revenge.model.LoadCheckPoint
import chat.schildi.revenge.model.conversation.EventJumpTarget
import chat.schildi.revenge.model.conversation.ScTimelineItem
import chat.schildi.revenge.model.conversation.LocalEventActionViewModel
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.plaintext.EventTextFormat
import chat.schildi.revenge.publishTitle
import chat.schildi.revenge.viewModelKey
import chat.schildi.theme.scExposures
import co.touchlab.kermit.Logger
import io.element.android.libraries.matrix.api.room.CreateTimelineParams
import io.element.android.libraries.matrix.api.room.CurrentUserMembership
import io.element.android.libraries.matrix.api.core.ThreadId
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.EventThreadInfo
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.EventOrTransactionId
import io.element.android.libraries.matrix.api.timeline.item.event.LocalEventSendState
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent
import io.element.android.libraries.matrix.api.timeline.item.event.MessageTypeWithAttachment
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.persistentMapOf
import kotlinx.collections.immutable.mutate
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_jump_to_bottom
import shire.res.generated.resources.action_jump_to_unread
import kotlin.math.absoluteValue
import kotlin.math.sign

internal fun notificationTimelineKey(eventId: String) = "matrix-event:$eventId"

@Composable
private fun NotificationPreviewBubble(
    preview: NotificationOpenPreview,
    showSenderDetails: Boolean = false,
    joinsPreviousBubble: Boolean = false,
    hasPreviousMessage: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        if (hasPreviousMessage) {
            Spacer(Modifier.height(
                if (joinsPreviousBubble) Dimens.Conversation.messageSameSenderPadding
                else Dimens.Conversation.messageOtherSenderPadding
            ))
        }
        MessageLayoutNormal(
            isOwn = false,
            showSenderDetails = showSenderDetails,
            joinsPreviousBubble = joinsPreviousBubble,
            joinsNextBubble = false,
            senderAvatar = {},
            senderName = {
                if (!joinsPreviousBubble) {
                    Text(
                        preview.senderName ?: preview.senderId.orEmpty(),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.scExposures.accentColor,
                        maxLines = 1,
                    )
                }
            },
            messageContent = {
                // Reuse bubble geometry without the full message formatter: that
                // CompositionLocal is unavailable before the timeline initializes.
                MessageBubble(isOwn = false, timestamp = null) {
                    Text(
                        preview.text,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            },
        )
    }
}

@Composable
fun ConversationScreen(
    destination: Destination.Conversation,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    // A phone cannot show the details split. Avoid composing an empty intermediate
    // multi-pane destination before the conversation itself is shown.
    val supportsDetailsSplit = with(LocalDensity.current) {
        LocalWindowInfo.current.containerSize.width.toDp() >=
            ScPrefs.CONVERSATION_DETAILS_SPLIT_MIN_WIDTH.value().dp
    }
    if (!destination.preferDetailsPane && supportsDetailsSplit && requireSinglePaneLayout(DestinationEnum.ConversationDetailsSplit, ScPrefs.PREFER_CONVERSATION_DETAILS_SPLIT) { conversation ->
            Destination.ConversationDetailsMultiPane(
                conversation = conversation,
            )
        }) {
        return
    }

    val keyHandler = LocalKeyboardActionHandler.current
    val viewModel: ConversationViewModel = viewModel(
        key = viewModelKey(destination),
        factory = ConversationViewModel.factory(
            destination.sessionId,
            destination.roomId,
            destination.timelineParams,
            destination.alias,
            destination.joinServerNames,
        )
    )

    publishTitle(viewModel)

    // Collect the search-mode flag once for the whole conversation. Both the app bar and
    // bottom search dock consume this plain value instead of creating separate flow collectors.
    val conversationSearchVisible = keyHandler
        .needsKeyboardSearchBar(viewModel)
        .collectAsState()
        .value

    DisposableEffect(Unit) {
        onDispose {
            viewModel.onUiDispose()
        }
    }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .let {
            if (viewModel.modeSupportsComposer || conversationSearchVisible) {
                it.windowInsetsPadding(
                    WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
                ).imePadding()
            } else {
                it.windowInsetsPadding(
                    WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
                )
            }
        },
        contentAlignment = Alignment.Center,
    ) {
        val contentHeight = maxHeight
        val density = LocalDensity.current
        val navigationBottomPadding = WindowInsets.navigationBars
            .asPaddingValues()
            .calculateBottomPadding()
        val imeBottomPadding = WindowInsets.ime
            .asPaddingValues()
            .calculateBottomPadding()
        val composerBottomPadding = imeAwareBottomPadding(navigationBottomPadding, imeBottomPadding)

        val timelineItems = viewModel.timelineItems.collectAsState().value
        val openPreview = NotificationOpenPreviews.current.collectAsState().value?.takeIf {
            destination.timelineParams == null &&
                it.sessionId == destination.sessionId.value && it.roomId == destination.roomId.value &&
                System.currentTimeMillis() - it.capturedAt in 0L..600_000L
        }
        val previewInTimeline = openPreview != null && timelineItems?.any {
            (it.item as? MatrixTimelineItem.Event)?.eventId?.value == openPreview.eventId
        } == true
        LaunchedEffect(openPreview, previewInTimeline) {
            if (openPreview != null && previewInTimeline) {
                // Keep placement animations off until the SDK handoff has settled.
                delay(300)
                NotificationOpenPreviews.clearIfCurrent(openPreview)
            }
        }
        val visibleOpenPreview = openPreview?.takeUnless { previewInTimeline }
        // Keep selected timeline objects directly so toggling selection stays O(1) with
        // respect to loaded room history. Re-scanning every event here can hitch large rooms.
        val selectedMessagesState = remember { mutableStateOf(persistentMapOf<String, ScTimelineItem>()) }
        val selectedMessages = selectedMessagesState.value
        val selectionActive = selectedMessages.isNotEmpty()
        val clearMessageSelection = remember {
            { selectedMessagesState.value = persistentMapOf() }
        }
        var selectionMoreOpen by remember { mutableStateOf(false) }
        var messageInfoEvent by remember { mutableStateOf<EventTimelineItem?>(null) }
        var selectionReportOpen by remember { mutableStateOf(false) }
        LaunchedEffect(selectionActive) {
            if (!selectionActive) {
                selectionMoreOpen = false
                selectionReportOpen = false
            }
        }
        val toggleMessageSelection: (ScTimelineItem) -> Unit = remember {
            { item ->
                val event = (item.item as? MatrixTimelineItem.Event)?.event
                if (event?.isKiteSelectableMessage() == true) {
                    event.kiteSelectionKey()?.let { key ->
                        val current = selectedMessagesState.value
                        selectedMessagesState.value = current.mutate { selected ->
                            if (key in current) {
                                selected.remove(key)
                            } else {
                                selected[key] = item
                            }
                        }
                    }
                }
            }
        }
        PlatformBackHandler(enabled = selectionActive) {
            clearMessageSelection()
        }
        val debugLines = if (ScPrefs.SHOW_DEV_INFOS.value()) {
            viewModel.debugLines.collectAsState().value
        } else {
            null
        }
        val forwardPaginationStatus = viewModel.forwardPaginationStatus.collectAsState(null).value
        val backwardPaginationStatus = viewModel.backwardPaginationStatus.collectAsState(null).value
        val showBackwardPagingIndicator = backwardPaginationStatus?.hasMoreToLoad == true
        val showForwardPagingIndicator = forwardPaginationStatus?.hasMoreToLoad == true
        val isBackwardPaging = backwardPaginationStatus?.isPaginating == true
        val isForwardPaging = forwardPaginationStatus?.isPaginating == true

        val roomInfo = viewModel.roomInfo.collectAsState().value
        val showSenderDetails = shouldShowTimelineSenderDetails(roomInfo?.joinedMembersCount)
        val roomPreview = viewModel.roomPreview.collectAsState().value
        val loadState = viewModel.loadState.collectAsState().value

        // From room links we may not know if it's a space or other special type of room pre-join,
        // so allow re-navigating once we know
        if (destination.allowRoomTypeBasedReNavigation && roomInfo != null) {
            val destinationStateHolder = LocalDestinationState.current
            val isSpace = roomInfo.isSpace
            LaunchedEffect(isSpace, roomInfo.currentUserMembership) {
                if (isSpace && roomInfo.currentUserMembership == CurrentUserMembership.JOINED) {
                    destinationStateHolder?.navigate(
                        Destination.SpaceDiscovery(destination.sessionId, destination.roomId),
                        NavigationPreference.REPLACE,
                    )
                    return@LaunchedEffect
                }
            }
        }

        // Group/DM geometry must be known before showing a notification preview:
        // otherwise the avatar/name gutter suddenly shifts the bubble on handoff.
        if (timelineItems == null || (openPreview != null && roomInfo == null)) {
            val isRoomPreview = when {
                roomInfo != null -> roomInfo.currentUserMembership != CurrentUserMembership.JOINED
                roomPreview != null -> roomPreview.membership != CurrentUserMembership.JOINED
                loadState.any {
                    it.checkpoint is LoadCheckPoint.RoomPreview && it.state == CheckpointLoadState.FAILED
                } -> true
                else -> false
            }
            if (isRoomPreview) {
                RoomPreviewScreen(roomInfo, roomPreview, viewModel, Modifier.fillMaxSize(), contentModifier)
            } else {
                // Keep the native conversation header visible while the SDK exposes
                // its already-synced timeline. A blank 650 ms splash makes even warm
                // room opens look stalled. No background room composables are retained.
                Column(contentModifier.fillMaxSize()) {
                    ConversationTopNavigation(
                        viewModel,
                        hasTimeline = false,
                        compact = this@BoxWithConstraints.maxWidth < Dimens.compactActionBarThreshold,
                    )
                    Box(Modifier.fillMaxWidth().weight(1f)) {
                        if (visibleOpenPreview != null && roomInfo != null) {
                            NotificationPreviewBubble(
                                visibleOpenPreview,
                                showSenderDetails = showSenderDetails,
                                modifier = Modifier.align(Alignment.BottomStart),
                            )
                        } else {
                            SplashScreenContent(
                                Modifier.fillMaxSize(),
                                viewModel.loadState,
                                delayMillis = 100L,
                            )
                        }
                    }
                    if (viewModel.modeSupportsComposer) {
                        // Reserve the composer's footprint before the timeline arrives.
                        // Otherwise the first real conversation frame shrinks the
                        // viewport and visibly jumps the newest message.
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .padding(
                                    start = Dimens.windowPadding,
                                    end = Dimens.windowPadding,
                                    top = 8.dp,
                                    bottom = composerBottomPadding,
                                )
                                .height(56.dp)
                                .background(
                                    MaterialTheme.colorScheme.surfaceContainerHigh,
                                    RoundedCornerShape(28.dp),
                                ),
                        )
                    }
                }
            }
            return@BoxWithConstraints
        }

        val actionContext = currentActionContext()
        val forwardEvents: (List<EventTimelineItem>) -> Unit = { events ->
            val holder = actionContext.destinationStateHolder
            val forward = MessageForward.prepare(
                sessionId = viewModel.sessionId,
                sourceRoomId = viewModel.roomId,
                events = events.sortedBy { it.timestamp },
            )
            if (holder != null && forward != null) {
                MessageForward.set(forward)
                clearMessageSelection()
                holder.navigate(Destination.Inbox, NavigationPreference.REPLACE)
            }
        }
        var isDragging by remember { mutableStateOf(false) }
        val dragAlpha = animateFloatAsState(if (isDragging) 0.4f else 1f)
        val fileDragTarget = remember {
            object : DragAndDropTarget {
                override fun onEntered(event: DragAndDropEvent) {
                    Logger.withTag("DnD").d { "Entered $event" }
                    isDragging = true
                }
                override fun onExited(event: DragAndDropEvent) {
                    Logger.withTag("DnD").d { "Exited $event" }
                    isDragging = false
                }
                override fun onDrop(event: DragAndDropEvent): Boolean {
                    isDragging = false
                    val file = event.firstDroppedFile()
                    Logger.withTag("DnD").d { "Received drop $event, file ${file != null}" }
                    return if (file != null) {
                        viewModel.attachFile(actionContext, file)
                    } else {
                        false
                    }
                }
            }
        }

        var initialListOffset by remember { mutableStateOf(Triple(0, 0, -1)) }
        var scrolledToEvent by remember { mutableStateOf<EventJumpTarget?>(null) }
        val targetEvent = viewModel.targetEvent.collectAsState().value
        val fullyReadEvent = viewModel.cachedFullyRead.collectAsState().value
        // Opening an unread room should land on its newest message. The explicit
        // "jump to unread" action still goes to the beginning of unread history.
        val isOpeningUnread = targetEvent is EventJumpTarget.Event && !targetEvent.highlight
        val isUnreadJump = targetEvent is EventJumpTarget.Event && !isOpeningUnread &&
                fullyReadEvent?.has(targetEvent.eventId) == true
        var allowPaginateAfterInitialLoad by remember(targetEvent) {
            Logger.withTag("ConversationScreen").w("Loading for $targetEvent ($scrolledToEvent)")
            mutableStateOf(
                targetEvent == null ||
                        targetEvent == scrolledToEvent ||
                        (targetEvent as? EventJumpTarget.Index)?.index == 0
            )
        }
        SideEffect(targetEvent, timelineItems) {
            if (targetEvent == scrolledToEvent || timelineItems.isEmpty()) {
                return@SideEffect
            }
            if (targetEvent == null) {
                // Ignore / keep last
                return@SideEffect
            }
            val index = when(targetEvent) {
                is EventJumpTarget.Event -> timelineItems.indexOfFirst { item ->
                    (item.item as? MatrixTimelineItem.Event)?.eventId == targetEvent.eventId
                }.takeIf { it >= 0 }?.let { markerIndex ->
                    val targetIndex = when {
                        isOpeningUnread -> latestTimelineIndex(timelineItems.size) { itemIndex ->
                            timelineItems[itemIndex].item is MatrixTimelineItem.Event
                        }
                        isUnreadJump -> firstUnreadTimelineIndex(markerIndex, timelineItems.size) { itemIndex ->
                            timelineItems[itemIndex].item is MatrixTimelineItem.Event
                        }
                        else -> markerIndex
                    }
                    // Reverse layout is applied by LazyColumn, not by timelineItems.
                    timelineItems.size - targetIndex - 1
                }
                is EventJumpTarget.Index -> targetEvent.index.takeIf {
                    forwardPaginationStatus?.hasMoreToLoad == false && it in 0..<timelineItems.size
                }
            }
            if (index == null) {
                Logger.withTag("ConversationScreen").w("Cannot find target event $targetEvent in ${timelineItems.size} items")
            } else {
                Logger.withTag("ConversationScreen").d("Targetting $index for $targetEvent")
                val offset = density.run { contentHeight.roundToPx() } / 2
                val scrollOffset = if (
                    isUnreadJump || isOpeningUnread ||
                    targetEvent is EventJumpTarget.Index && index == 0
                ) 0 else -offset
                // The normal inbox -> chat target is Index(0). Re-keying an
                // already-correct LazyListState for that no-op resets measurement
                // and makes the first visible chat frame jump.
                if (index != initialListOffset.first ||
                    scrollOffset != initialListOffset.second ||
                    (targetEvent.renavigationCount > 0 &&
                        targetEvent.renavigationCount != initialListOffset.third)
                ) {
                    initialListOffset = Triple(index, scrollOffset, targetEvent.renavigationCount)
                }
                scrolledToEvent = targetEvent
            }
            allowPaginateAfterInitialLoad = true
        }

        val listState = key(initialListOffset) {
            SideEffect(initialListOffset) {
                Logger.withTag("ConversationScreen").w("Init list state for $initialListOffset")
            }
            rememberLazyListState(
                initialFirstVisibleItemIndex = initialListOffset.first,
                initialFirstVisibleItemScrollOffset = initialListOffset.second,
            )
        }

        if (allowPaginateAfterInitialLoad) {
            LaunchedEffect(listState, backwardPaginationStatus, timelineItems) {
                snapshotFlow {
                    listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index
                }
                    .collect { lastVisibleIndex ->
                        if (lastVisibleIndex != null && lastVisibleIndex >= timelineItems.size - 3 && backwardPaginationStatus?.canPaginate == true) {
                            Logger.withTag("ConversationScreen")
                                .d("Paginate backwards via $lastVisibleIndex/${timelineItems.size}, $backwardPaginationStatus")
                            viewModel.paginateBackward()
                        }
                    }
            }
            LaunchedEffect(listState, forwardPaginationStatus, timelineItems) {
                snapshotFlow {
                    listState.layoutInfo.visibleItemsInfo.firstOrNull()?.index
                }
                    .collect { firstVisibleIndex ->
                        if (allowPaginateAfterInitialLoad && firstVisibleIndex != null && firstVisibleIndex <= 3 && forwardPaginationStatus?.canPaginate == true) {
                            Logger.withTag("ConversationScreen")
                                .d("Paginate forward via $firstVisibleIndex/${timelineItems.size}, $forwardPaginationStatus")
                            viewModel.paginateForward()
                        }
                    }
            }
        }

        // Provider will be null if not allowed via settings
        val urlPreviewProvider = viewModel.urlPreviewStateProvider.collectAsState().value
        // Prefetch url preview metadata a window ahead of the visible items so we can avoid some visual jumps
        if (urlPreviewProvider != null) {
            LaunchedEffect(listState, urlPreviewProvider) {
                snapshotFlow {
                    listState.layoutInfo.visibleItemsInfo
                        .map { it.index }
                        .takeIf { it.isNotEmpty() }
                        ?.let { it.min() to it.max() }
                }.collect { visibleRange ->
                    visibleRange?.let { (lo, hi) ->
                        viewModel.prefetchUrlPreviews(lo, hi)
                    }
                }
            }
        }

        val isReadMarkerVisible = remember { mutableStateOf(false) }
        val isBottomVisible = remember { mutableStateOf(true) }

        val listAction = rememberListActions(listState, isReverseList = true)
        FocusContainer(
            LocalSearchProvider provides viewModel,
            LocalEventActionViewModel provides viewModel,
            LocalKeyboardActionProvider provides
                    viewModel.actionProvider.hierarchicalKeyboardActionProvider(),
            LocalUrlPreviewStateProvider provides urlPreviewProvider,
            LocalUserIdSuggestionsProvider provides viewModel,
            LocalRoomContextSuggestionsProvider provides viewModel.roomContextSuggestionsProvider,
            LocalListActionProvider provides listAction,
            LocalMatrixBodyFormatter provides matrixBodyFormatter(),
            LocalMatrixBodyDrawStyle provides matrixBodyDrawStyle(),
            role = FocusRole.DESTINATION_ROOT_CONTAINER,
            modifier = Modifier.fillMaxSize(),
        ) {
            val roomMembersById = viewModel.roomMembersById.collectAsState()
            val roomPermissions = viewModel.roomPermissions.collectAsState().value

            val selectionActionScope = rememberCoroutineScope()
            val selectedSingle = selectedMessages.values.singleOrNull()
            val selectedSingleEvent = (selectedSingle?.item as? MatrixTimelineItem.Event)?.event
            val selectedEvents = remember(selectedMessages) {
                selectedMessages.values.mapNotNull { selected ->
                    (selected.item as? MatrixTimelineItem.Event)?.event
                }
            }
            val canDeleteSelection = selectedEvents.isNotEmpty() && selectedEvents.all { event ->
                if (event.isOwn) {
                    roomPermissions?.canRedactOwn ?: true
                } else {
                    roomPermissions?.canRedactOther ?: false
                }
            }
            val executeSelectedAction: (ScTimelineItem, Action.Event) -> ActionResult = { selected, action ->
                val event = (selected.item as MatrixTimelineItem.Event).event
                viewModel.getKeyboardActionProviderForEvent(
                    event = event,
                    messageMetadata = selected.messageMetadata,
                    formatInteractionState = null,
                ).handleAction(actionContext, action, emptyList())
            }
            val clearSelection = clearMessageSelection
            val canForwardSelection = selectedEvents.isNotEmpty() && selectedEvents.all { it.eventId != null }
            val canEditSingle = selectedSingleEvent?.isEditable == true &&
                    (roomPermissions?.canSendMessages ?: true)
            val canOpenThread = selectedSingleEvent?.eventId != null &&
                    destination.timelineParams !is CreateTimelineParams.Threaded &&
                    (roomPermissions?.canSendMessages ?: false)
            val isPinned = selectedSingleEvent?.eventId?.let { it in (roomInfo?.pinnedEventIds ?: emptyList()) } == true
            val canDownload = ((selectedSingleEvent?.content as? MessageContent)?.type is MessageTypeWithAttachment)
            val selectionActions = if (selectionActive) {
                MessageSelectionActions(
                    selectedCount = selectedMessages.size,
                    canReply = selectedSingleEvent?.eventId != null &&
                            (roomPermissions?.canSendMessages ?: false),
                    canRetry = selectedSingleEvent?.localSendState is LocalEventSendState.Failed,
                    canForward = canForwardSelection,
                    canDelete = canDeleteSelection,
                    onReply = {
                        selectedSingle?.let {
                            if (executeSelectedAction(it, Action.Event.ComposeReply) is ActionResult.Success) {
                                clearSelection()
                            }
                        }
                    },
                    onRetry = {
                        selectedSingle?.let {
                            if (executeSelectedAction(it, Action.Event.RetrySend) is ActionResult.Success) {
                                clearSelection()
                            }
                        }
                    },
                    onCopy = {
                        val snapshot = selectedMessages.values.toList()
                        selectionActionScope.launch {
                            val result = if (
                                snapshot.size == 1 &&
                                ((snapshot.single().item as? MatrixTimelineItem.Event)?.event?.content is MessageContent)
                            ) {
                                executeSelectedAction(snapshot.single(), Action.Event.CopyContent)
                            } else {
                                val eventsWithMetadata = snapshot
                                    .mapNotNull { selected ->
                                        val event = (selected.item as? MatrixTimelineItem.Event)?.event
                                            ?: return@mapNotNull null
                                        event to selected.messageMetadata
                                    }
                                    .sortedBy { (event, _) -> event.timestamp }
                                val text = buildList {
                                    for ((event, messageMetadata) in eventsWithMetadata) {
                                        add(
                                            EventTextFormat.eventToTextSuspend(
                                                content = event.content,
                                                messageMetadata = messageMetadata,
                                                senderProfile = event.senderProfile,
                                                senderId = event.sender,
                                                stripNewlines = false,
                                            )
                                        )
                                    }
                                }.joinToString("\n\n")
                                if (text.isEmpty()) {
                                    ActionResult.Inapplicable
                                } else {
                                    actionContext.copyToClipboard(text)
                                }
                            }
                            if (result is ActionResult.Success) {
                                clearSelection()
                            }
                        }
                    },
                    onForward = {
                        forwardEvents(selectedEvents)
                    },
                    onDelete = {
                        viewModel.redactEventsWithConfirmation(
                            context = actionContext,
                            events = selectedEvents,
                            onConfirmed = clearSelection,
                        )
                    },
                    onMore = { selectionMoreOpen = true },
                )
            } else {
                null
            }

            val pinnedEventIds = remember(roomInfo?.pinnedEventIds) {
                roomInfo?.pinnedEventIds?.toSet() ?: emptySet()
            }
            // Bots/bridges often live in two-member rooms without m.direct. Visually those
            // are still one-to-one conversations; only true multi-member rooms need labels.
            val highlightedActionEventId = viewModel.highlightedActionEventId.collectAsState().value
            val heartBurst = rememberHeartBurstState()
            val composerHeightPx = remember { mutableIntStateOf(0) }
            Column(contentModifier
                .fillMaxSize()
                .alpha(dragAlpha.value)
                .dragAndDropTarget(
                    shouldStartDragAndDrop = { event ->
                        event.hasDroppedFiles()
                    },
                    target = fileDragTarget,
                ),
            ) {
                ConversationTopNavigation(
                    viewModel,
                    hasTimeline = true,
                    compact = this@BoxWithConstraints.maxWidth < Dimens.compactActionBarThreshold,
                    selectionCount = selectedMessages.size,
                    onClearSelection = clearMessageSelection,
                    selectionActions = selectionActions,
                    isSearchVisible = conversationSearchVisible,
                )

                ConversationTopDebugHeader(viewModel, Modifier.fillMaxWidth())

                Box(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(Dimens.Conversation.timelineSurfaceShape)
                        .background(MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    // Reverse layout helps with stick-to-bottom while paging backwards or receiving messages
                    val renderedItems = remember(timelineItems) {
                        timelineItems.reversed().toPersistentList()
                    }
                    val visibleNeighborIndices = remember(renderedItems) {
                        calculateVisibleTimelineNeighbors(renderedItems.map { timelineItem ->
                            when (val matrixItem = timelineItem.item) {
                                is MatrixTimelineItem.Event -> if (matrixItem.event.isKiteServerEvent()) {
                                    TimelineRowKind.Hidden
                                } else {
                                    TimelineRowKind.Event
                                }
                                else -> TimelineRowKind.Boundary
                            }
                        })
                    }
                    // Position the FIRST unread event using the measured timeline viewport and
                    // row height. The old half-of-the-window offset could leave it hidden
                    // behind the composer or clipped, especially for long messages.
                    if (isUnreadJump && initialListOffset.first in renderedItems.indices) {
                        LaunchedEffect(listState) {
                            val (viewportHeight, rowHeight) = snapshotFlow {
                                val layout = listState.layoutInfo
                                val item = layout.visibleItemsInfo.firstOrNull {
                                    it.index == initialListOffset.first
                                }
                                item?.let { (layout.viewportEndOffset - layout.viewportStartOffset) to it.size }
                            }.filterNotNull().first()
                            listState.scrollToItem(
                                initialListOffset.first,
                                unreadTopScrollOffset(viewportHeight, rowHeight, density.run { 12.dp.roundToPx() }),
                            )
                        }
                    }
                    // A visible room opened at its newest message must not stay unread
                    // because the SDK's per-event receipt tracker missed an event.
                    val roomHasUnread = roomInfo?.let {
                        it.isMarkedUnread || it.numUnreadMessages > 0L ||
                            it.numUnreadNotifications > 0L || it.unreadCount > 0L
                    } == true
                    if (viewModel.timelineParams == null && roomHasUnread &&
                        allowPaginateAfterInitialLoad && renderedItems.isNotEmpty()
                    ) {
                        LaunchedEffect(viewModel, listState, renderedItems, roomInfo) {
                            snapshotFlow {
                                listState.layoutInfo.visibleItemsInfo.any { it.index == 0 }
                            }.first { it }
                            viewModel.markVisibleRoomReadOnOpen()
                        }
                    }
                    // A programmatic scroll is also "isScrollInProgress". Do not mistake
                    // initial positioning or a new message for the user scrolling away.
                    val followLatest = remember(listState) { mutableStateOf(true) }
                    val userHasScrolled = remember(listState) { mutableStateOf(false) }
                    val userScrollObserver = remember(listState) {
                        object : NestedScrollConnection {
                            override fun onPostScroll(
                                consumed: Offset,
                                available: Offset,
                                source: NestedScrollSource,
                            ): Offset {
                                if (source == NestedScrollSource.UserInput && consumed != Offset.Zero) {
                                    userHasScrolled.value = true
                                    followLatest.value = isLatestPosition(
                                        listState.firstVisibleItemIndex,
                                        listState.firstVisibleItemScrollOffset,
                                    )
                                }
                                return Offset.Zero
                            }
                        }
                    }
                    LaunchedEffect(listState) {
                        snapshotFlow {
                            listState.isScrollInProgress to isLatestPosition(
                                listState.firstVisibleItemIndex,
                                listState.firstVisibleItemScrollOffset,
                            )
                        }.collect { (scrolling, atLatest) ->
                            // After a user fling settles, restore follow mode at the bottom.
                            if (!scrolling && userHasScrolled.value) {
                                followLatest.value = atLatest
                                userHasScrolled.value = false
                            }
                        }
                    }
                    val newestEvent = remember(renderedItems) {
                        renderedItems.firstNotNullOfOrNull { it.item as? MatrixTimelineItem.Event }
                    }
                    val newestEventKey = newestEvent?.uniqueId
                    if (viewModel.timelineParams == null &&
                        (isOpeningUnread || targetEvent is EventJumpTarget.Index && targetEvent.index == 0)
                    ) {
                        var lastAnchoredEventKey by remember(listState) { mutableStateOf(newestEventKey) }
                        if (newestEventKey != null && newestEventKey != lastAnchoredEventKey) {
                            val isOwnMessage = newestEvent.event.isOwn && newestEvent.event.content is MessageContent
                            SideEffect {
                                // Local echoes already enter at index 0. Re-anchoring them
                                // defeats item placement animations and creates a hard jump.
                                if (followLatest.value && !isOwnMessage) listState.requestScrollToItem(0)
                                lastAnchoredEventKey = newestEventKey
                            }
                        }
                    }
                    val latestOwnMessageKey = remember(renderedItems) {
                        renderedItems.firstNotNullOfOrNull { timelineItem ->
                            val event = (timelineItem.item as? MatrixTimelineItem.Event)?.event
                            event
                                ?.takeIf { it.isOwn && it.content is MessageContent }
                                ?.kiteSelectionKey()
                        }
                    }

                    // Track whether we see bottom or latest read message for jump-to-message FABs
                    val currentThreadId = viewModel.threadId.collectAsState().value
                    LaunchedEffect(listState, fullyReadEvent, renderedItems) {
                        snapshotFlow {
                            val visible = listState.layoutInfo.visibleItemsInfo
                            val bottom = visible.firstOrNull()?.index?.let { it <= 1 } != false
                            // No read marker known counts as "visible" since we cannot jump to it anyway
                            val readMarker = fullyReadEvent == null || visible.any {
                                fullyReadEvent.has((renderedItems.getOrNull(it.index)?.item as? MatrixTimelineItem.Event)?.eventId)
                            }
                            Pair(bottom, readMarker)
                        }.collect {
                            isBottomVisible.value = it.first
                            isReadMarkerVisible.value = it.second
                        }
                    }

                    val shouldTrackLatestRead = when (viewModel.timelineParams) {
                        null,
                        is CreateTimelineParams.Focused,
                        is CreateTimelineParams.Threaded -> true
                        else -> false
                    }
                    if (ScPrefs.AUTO_MARK_AS_READ_TRIGGER.value() != ScPrefs.AutoMarkAsReadTrigger.NEVER.name &&
                        shouldTrackLatestRead &&
                        allowPaginateAfterInitialLoad
                    ) {
                        LaunchedEffect(listState, renderedItems) {
                            snapshotFlow {
                                listState.layoutInfo.visibleItemsInfo
                                    .sortedBy { it.index }
                                    .firstNotNullOfOrNull {
                                        // Require bottom on screen
                                        if (it.offset < 0)
                                            null
                                        else
                                            (renderedItems.getOrNull(it.index)?.item as? MatrixTimelineItem.Event)?.eventId
                                    }
                            }.collect { eventId ->
                                if (eventId != null) {
                                    viewModel.trackSeenMessage(eventId, renderedItems)
                                }
                            }
                        }
                    }

                    // Read Kite interaction preferences once for the conversation, not once per
                    // visible timeline row. This keeps preference-flow collection off the hot row path.
                    val doubleTapToReact = ScPrefs.DOUBLE_TAP_TO_REACT.value()
                    val doubleTapReaction = ScPrefs.DOUBLE_TAP_REACTION.value()
                    val swipeActionLeftRaw = ScPrefs.MESSAGE_SWIPE_ACTION_LEFT.value()
                    val swipeActionRightRaw = ScPrefs.MESSAGE_SWIPE_ACTION_RIGHT.value()
                    val messageSwipeConfig = remember(swipeActionLeftRaw, swipeActionRightRaw) {
                        resolveMessageSwipeConfig(swipeActionLeftRaw, swipeActionRightRaw)
                    }

                    val messagePlacementSpec = remember {
                        // Start moving immediately, then settle. Keep the same 180 ms budget;
                        // the old ease-in delayed motion before a noticeable mid-flight surge.
                        tween<IntOffset>(durationMillis = 180, easing = LinearOutSlowInEasing)
                    }
                    val messageArrivalSpec = remember {
                        // Soften the new bubble’s first frame while older rows make room.
                        tween<Float>(durationMillis = 90, easing = LinearOutSlowInEasing)
                    }
                    CompositionLocalProvider(LocalHeartBurstState provides heartBurst) {
                    LazyColumn(
                        Modifier.fillMaxSize().nestedScroll(userScrollObserver),
                        reverseLayout = true,
                        state = listState,
                        contentPadding = if (viewModel.modeSupportsComposer) {
                            PaddingValues()
                        } else {
                            WindowInsets.navigationBars
                                .only(WindowInsetsSides.Bottom)
                                .asPaddingValues()
                        }
                    ) {
                        // Keep the notified event in the list's newest slot. Its replacement
                        // by the SDK event then keeps the older messages at the same offsets.
                        visibleOpenPreview?.let { preview ->
                            item(key = notificationTimelineKey(preview.eventId)) {
                                val previousEvent = (renderedItems.firstOrNull()?.item as? MatrixTimelineItem.Event)?.event
                                val joinsPrevious = previousEvent != null &&
                                    previousEvent.sender.value == preview.senderId &&
                                    previousEvent.content is MessageContent
                                NotificationPreviewBubble(
                                    preview = preview,
                                    showSenderDetails = showSenderDetails,
                                    joinsPreviousBubble = joinsPrevious,
                                    hasPreviousMessage = previousEvent != null,
                                )
                            }
                        }
                        itemsIndexed(
                            renderedItems,
                            key = { index, item ->
                                when (val timelineItem = item.item) {
                                    // The SDK uniqueId is stable while a local echo becomes a
                                    // remote event. Event/transaction IDs are not, and re-keying
                                    // the row makes the reversed list jump on every send.
                                    is MatrixTimelineItem.Event -> timelineItem.event.eventId
                                        ?.takeIf { !timelineItem.event.isOwn }
                                        ?.let { notificationTimelineKey(it.value) }
                                        ?: timelineItem.uniqueId
                                    MatrixTimelineItem.Other -> index
                                    is MatrixTimelineItem.Virtual -> timelineItem.uniqueId
                                }
                            },
                        ) { index, item ->
                            // Reversed list, let's not confuse us too much and still say "previous = older"
                            val next = renderedItems.getOrNull(index - 1)
                            val previous = renderedItems.getOrNull(index + 1)
                            val highlight = when {
                                item.item !is MatrixTimelineItem.Event -> EventHighlight.NONE
                                highlightedActionEventId is EventOrTransactionId.Event &&
                                        item.item.eventId == highlightedActionEventId.eventId -> EventHighlight.ACTION_TARGET

                                highlightedActionEventId is EventOrTransactionId.Transaction &&
                                        item.item.transactionId == highlightedActionEventId.id -> EventHighlight.ACTION_TARGET

                                else -> EventHighlight.NONE
                            }
                            // Reverse list causes reverses indices
                            val currentDebugLines = debugLines?.get(timelineItems.size - index - 1) ?: persistentListOf()
                            val rowEvent = (item.item as? MatrixTimelineItem.Event)?.event
                            val rowSelected = rowEvent?.kiteSelectionKey()?.let(selectedMessages::containsKey) == true
                            ConversationItemRow(
                                viewModel = viewModel,
                                item = item,
                                next = next,
                                previous = previous,
                                previousVisibleEvent = (renderedItems.getOrNull(
                                    visibleNeighborIndices.older[index]
                                )?.item as? MatrixTimelineItem.Event)?.event,
                                nextVisibleEvent = (renderedItems.getOrNull(
                                    visibleNeighborIndices.newer[index]
                                )?.item as? MatrixTimelineItem.Event)?.event,
                                previousEvent = getNextItem(
                                    index,
                                    renderedItems::getOrNull,
                                ) {
                                    it.item is MatrixTimelineItem.Event
                                }.first?.item as? MatrixTimelineItem.Event,
                                roomMembersById = roomMembersById.value,
                                fullyReadEvent = fullyReadEvent,
                                currentThreadId = currentThreadId,
                                showSenderDetails = showSenderDetails,
                                targetEvent = targetEvent,
                                roomPermissions = roomPermissions,
                                highlight = highlight,
                                doubleTapToReact = doubleTapToReact,
                                doubleTapReaction = doubleTapReaction,
                                swipeConfig = messageSwipeConfig,
                                selectionActive = selectionActive,
                                isSelected = rowSelected,
                                isPinned = rowEvent?.eventId?.let { it in pinnedEventIds } == true,
                                canPin = roomPermissions?.canPinUnpin == true,
                                showReadReceipts = rowEvent?.kiteSelectionKey() == latestOwnMessageKey,
                                onToggleSelection = toggleMessageSelection,
                                onForward = { event -> forwardEvents(listOf(event)) },
                                onShowInfo = { event -> messageInfoEvent = event },
                                showBackwardPagingIndicator = showBackwardPagingIndicator,
                                showForwardPagingIndicator = showForwardPagingIndicator,
                                isBackwardPaging = isBackwardPaging,
                                isForwardPaging = isForwardPaging,
                                modifier = Modifier.animateItem(
                                    // Only the newest real message enters; paginated history
                                    // and notification handoff never fade or delay.
                                    fadeInSpec = if (openPreview == null && index == 0) messageArrivalSpec else null,
                                    fadeOutSpec = null,
                                    // The notified event must replace its preview in place,
                                    // without animating previously visible messages.
                                    placementSpec = if (openPreview == null) messagePlacementSpec else null,
                                ),
                                debugSeparatorLines = currentDebugLines.toPersistentList(),
                            )
                        }
                        if (renderedItems.isEmpty() && showBackwardPagingIndicator) {
                            item {
                                PagingIndicator(isLoading = isBackwardPaging, modifier = Modifier.padding(vertical = Dimens.windowPadding))
                            }
                        }
                    }
                    }

                    // Jump-to-message FABs
                    val isLive = viewModel.activeTimelineState.collectAsState().value?.isLive != false
                    val bottomItem = if (isLive) getNextItem(
                        0,
                        renderedItems::getOrNull,
                    ) {
                        it.item is MatrixTimelineItem.Event
                    }.first?.item as? MatrixTimelineItem.Event else null
                    val showJumpToUnread = when (viewModel.timelineParams) {
                        null,
                        is CreateTimelineParams.Focused -> fullyReadEvent != null &&
                                !isReadMarkerVisible.value &&
                                // Keep UI clean while at the bottom
                                !isBottomVisible.value &&
                                // If bottom-most message is already the latest read, then the jump-to-bottom button is enough for that
                                !fullyReadEvent.has(bottomItem?.eventId)
                        else -> false
                    }
                    val showJumpToBottom = !isBottomVisible.value
                    Column(
                        modifier = Modifier.align(Alignment.BottomEnd).padding(Dimens.windowPadding),
                        verticalArrangement = Dimens.verticalArrangement,
                    ) {
                        val showAnyFabs = !selectionActive &&
                                !keyHandler.keyboardPrimaryWithoutSettingOverride.collectAsState().value
                        TimelineJumpFab(
                            Icons.Outlined.Visibility,
                            stringResource(Res.string.action_jump_to_unread),
                            action = Action.Conversation.JumpToFullyRead,
                            isVisible = showAnyFabs && showJumpToUnread,
                        )
                        TimelineJumpFab(
                            Icons.Default.KeyboardArrowDown,
                            stringResource(Res.string.action_jump_to_bottom),
                            action = Action.Conversation.JumpToBottom,
                            isVisible = showAnyFabs && showJumpToBottom,
                        )
                    }
                }

                if (selectionActive) {
                    // Selection replaces the composer visually, but not its measured viewport.
                    if (composerHeightPx.intValue > 0) {
                        Spacer(Modifier.height(with(density) { composerHeightPx.intValue.toDp() }))
                    }
                    if (selectionMoreOpen && selectedSingle != null && selectedSingleEvent != null) {
                        MessageSelectionMoreSheet(
                            canEdit = canEditSingle,
                            canOpenThread = canOpenThread,
                            canPin = selectedSingleEvent.eventId != null && roomPermissions?.canPinUnpin == true,
                            isPinned = isPinned,
                            canDownload = canDownload,
                            canForward = canForwardSelection,
                            canReport = selectedSingleEvent.eventId != null && !selectedSingleEvent.isOwn,
                            canDelete = canDeleteSelection,
                            onDismiss = { selectionMoreOpen = false },
                            onEdit = {
                                if (executeSelectedAction(selectedSingle, Action.Event.ComposeEdit) is ActionResult.Success) {
                                    clearSelection()
                                }
                            },
                            onOpenThread = {
                                val threadRootId =
                                    (selectedSingleEvent.threadInfo() as? EventThreadInfo.ThreadResponse)
                                        ?.threadRootId
                                        ?.value
                                        ?: selectedSingleEvent.eventId?.value
                                if (threadRootId != null) {
                                    actionContext.destinationStateHolder?.navigate(
                                        Destination.Conversation(
                                            sessionId = viewModel.sessionId,
                                            roomId = viewModel.roomId,
                                            timelineParams = CreateTimelineParams.Threaded(ThreadId(threadRootId)),
                                        )
                                    )
                                    clearSelection()
                                }
                            },
                            onTogglePin = {
                                val action = if (isPinned) Action.Event.Unpin else Action.Event.Pin
                                if (executeSelectedAction(selectedSingle, action) is ActionResult.Success) {
                                    clearSelection()
                                }
                            },
                            onDownload = {
                                if (executeSelectedAction(selectedSingle, Action.Event.DownloadFile) is ActionResult.Success) {
                                    clearSelection()
                                }
                            },
                            onForward = {
                                forwardEvents(listOf(selectedSingleEvent))
                            },
                            onInfo = { messageInfoEvent = selectedSingleEvent },
                            onReport = { selectionReportOpen = true },
                            onDelete = {
                                viewModel.redactEventsWithConfirmation(
                                    context = actionContext,
                                    events = selectedEvents,
                                    onConfirmed = clearSelection,
                                )
                            },
                        )
                    }
                    val reportEvent = selectedSingleEvent
                    if (selectionReportOpen && reportEvent?.eventId != null && !reportEvent.isOwn) {
                        ReportMessageSheet(
                            onDismiss = { selectionReportOpen = false },
                            onReport = { reason ->
                                if (
                                    viewModel.reportEvent(
                                        context = actionContext,
                                        event = reportEvent,
                                        reason = reason,
                                        onReported = clearSelection,
                                    ) is ActionResult.Actioned
                                ) {
                                    // Selection is cleared only after the async report succeeds.
                                }
                            },
                        )
                    }
                } else {
                    val shouldShowComposer = viewModel.shouldShowComposer.collectAsState().value
                    val shouldAutoFocusComposer = FocusRole.MESSAGE_COMPOSER.shouldAutoRequestFocus()
                    LaunchedEffect(shouldShowComposer, conversationSearchVisible) {
                        if (
                            shouldShowComposer &&
                            !conversationSearchVisible &&
                            shouldAutoFocusComposer
                        ) {
                            keyHandler.focusByRole(FocusRole.MESSAGE_COMPOSER)
                        }
                    }
                    if (conversationSearchVisible) {
                        SearchBar(
                            searchProvider = viewModel,
                            searchFocusContainer = null,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(
                                    start = Dimens.windowPadding,
                                    end = Dimens.windowPadding,
                                    top = 8.dp,
                                    bottom = composerBottomPadding,
                                ),
                            showClearButton = true,
                            topNavigationStyle = true,
                        )
                    } else if (shouldShowComposer) {
                        // Keep the bottom control stable. A slide+shrink exit used to remeasure
                        // the timeline during mode/close transitions and produced a visible
                        // end-of-close jolt on compact Android.
                        Box(Modifier.onSizeChanged { composerHeightPx.intValue = it.height }) {
                            ComposerRow(
                                viewModel,
                                modifier = Modifier.padding(bottom = composerBottomPadding),
                            )
                        }
                    }
                }
                messageInfoEvent?.let { infoEvent ->
                    MessageInfoSheet(
                        event = infoEvent,
                        onDismiss = { messageInfoEvent = null },
                    )
                }
            }
            // Draw above the composer without joining the clipped timeline's layout.
            Box(
                Modifier.matchParentSize()
                    .onGloballyPositioned { heartBurst.updateViewport(it) }
                    .drawHeartBurst(heartBurst),
            )
        }
    }
}

internal fun shouldShowTimelineSenderDetails(joinedMembersCount: Long?): Boolean =
    (joinedMembersCount ?: 0L) > 2L

private inline fun <T>getNextItem(
    currentIndex: Int,
    peek: (Int) -> T?,
    direction: Int = 1,
    limit: Int = 100,
    predicate: (T) -> Boolean = { true },
): Pair<T?, Int?> {
    var count = direction.absoluteValue
    val step = direction.sign
    var index = currentIndex
    for (i in 0..limit) {
        index += step
        val item = peek(index) ?: return Pair(null, null)
        if (predicate(item)) {
            count--
            if (count == 0) {
                return Pair(item, index)
            }
        }
    }
    return Pair(null, null)
}

/** Choose the first real message after the last-read marker, skipping day dividers. */
internal fun firstUnreadTimelineIndex(markerIndex: Int, itemCount: Int, isMessage: (Int) -> Boolean): Int =
    ((markerIndex + 1) until itemCount).firstOrNull(isMessage) ?: markerIndex

/** For a reverse-layout list, align the older (top) edge of the unread row near the viewport top. */
internal fun unreadTopScrollOffset(viewportHeight: Int, rowHeight: Int, topPadding: Int): Int =
    rowHeight - viewportHeight + topPadding

/** The reversed list's newest event is at index 0 with zero scroll offset. */
internal fun isLatestPosition(firstVisibleIndex: Int, firstVisibleOffset: Int): Boolean =
    firstVisibleIndex == 0 && firstVisibleOffset == 0

/** Find the newest real event, ignoring trailing typing and other virtual rows. */
internal fun latestTimelineIndex(itemCount: Int, isMessage: (Int) -> Boolean): Int =
    (itemCount - 1 downTo 0).firstOrNull(isMessage) ?: 0
