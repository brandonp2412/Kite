package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.plus
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.actions.LocalKeyboardActionProvider
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.DiagnosticsRow
import chat.schildi.revenge.compose.components.EmptyListScreen
import chat.schildi.revenge.compose.destination.imeAwareBottomPadding
import chat.schildi.revenge.compose.destination.split.requireSinglePaneLayout
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.compose.search.LocalSearchProvider
import chat.schildi.revenge.config.keybindings.DestinationEnum
import chat.schildi.revenge.model.DraftRepo
import chat.schildi.revenge.model.InboxViewModel
import chat.schildi.revenge.model.IncomingShare
import chat.schildi.revenge.model.MessageForward
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.publishTitle
import chat.schildi.revenge.viewModelKey
import chat.schildi.resources.toStringHolder
import chat.schildi.theme.scExposures
import kotlinx.collections.immutable.persistentSetOf
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_account_management
import shire.res.generated.resources.action_start_chat
import shire.res.generated.resources.empty_screen_placeholder_inbox
import shire.res.generated.resources.search_results_conversations

private val KiteSearchBarReserve = 88.dp
private val KiteStartChatBottomGap = 12.dp

@OptIn(FlowPreview::class)
@Composable
fun InboxScreen(
    destination: Destination.Inbox,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    if (requireSinglePaneLayout(DestinationEnum.InboxConversationSplit, ScPrefs.PREFER_DUAL_PANE_INBOX) { inbox ->
        Destination.InboxConversationMultiPane(inbox = inbox)
    }) {
        return
    }

    val viewModel: InboxViewModel = viewModel(
        key = viewModelKey(destination),
        factory = viewModelFactory { initializer { InboxViewModel() } },
    )
    publishTitle(viewModel)

    val keyboardActionHandler = LocalKeyboardActionHandler.current
    val searchQuery = keyboardActionHandler
        .searchQueryForDestination(viewModel)
        .collectAsState(null).value
    val accounts = viewModel.accounts.collectAsState().value
    val accountsSorted = viewModel.accountsSorted.collectAsState().value
    val preferredAccount = accountsSorted
        ?.firstOrNull { it.isCurrentlyVisible }
        ?: accountsSorted?.firstOrNull()

    val listState = key(searchQuery) {
        rememberLazyListState()
    }
    val drafts = DraftRepo.roomsWithDrafts.collectAsState(persistentSetOf())
    val pendingForward = MessageForward.pending.collectAsState(null).value
    // Read inbox-wide unread preferences once instead of collecting them separately in every row.
    val unreadCountPreferences = RoomUnreadCountPreferences(
        allowSilentUnreadCount = ScPrefs.RENDER_SILENT_UNREAD.value(),
        clientGeneratedUnreadCounts = ScPrefs.CLIENT_GENERATED_UNREAD_COUNTS.value(),
        renderUnderestimates = ScPrefs.INDICATE_UNREAD_COUNT_UNDERESTIMATES.value(),
        dualMentionUnreadCounts = ScPrefs.DUAL_MENTION_UNREAD_COUNTS.value(),
    )

    FocusContainer(
        LocalSearchProvider provides viewModel,
        LocalKeyboardActionProvider provides viewModel.hierarchicalKeyboardActionProvider(),
        LocalListActionProvider provides rememberListActions(listState),
        modifier = modifier.windowInsetsPadding(
            WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
        ),
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
    ) {
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .imePadding()
        ) {
            val compact = maxWidth < Dimens.compactActionBarThreshold
            val navigationBottomPadding = WindowInsets.navigationBars
                .asPaddingValues()
                .calculateBottomPadding()
            val imeBottomPadding = WindowInsets.ime
                .asPaddingValues()
                .calculateBottomPadding()
            val compactSearchBottomPadding = imeAwareBottomPadding(navigationBottomPadding, imeBottomPadding)

            Column(
                Modifier
                    .fillMaxSize()
                    .padding(top = if (compact) Dimens.listPadding else 0.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (ScPrefs.SHOW_DEV_INFOS.value()) {
                    DiagnosticsRow(Modifier.fillMaxWidth())
                }

                val roomsState = viewModel.filteredRooms.collectAsState().value
                val rooms = roomsState?.rooms
                val roomsByRoomId = viewModel.roomsByRoomId.collectAsState().value
                val dmsByHeroes = viewModel.dmsByHeroes.collectAsState().value
                val needsAccountDisambiguation =
                    (accountsSorted?.count { it.isCurrentlyVisible } ?: 0) > 1

                LaunchedEffect(listState, rooms) {
                    snapshotFlow {
                        val visibleItems = listState.layoutInfo.visibleItemsInfo
                        if (visibleItems.isEmpty()) {
                            -1L
                        } else {
                            (visibleItems.first().index.toLong() shl 32) or
                                (visibleItems.last().index.toLong() and 0xffffffffL)
                        }
                    }
                        .debounce(200)
                        .collect { visibleRange ->
                            if (visibleRange < 0L || rooms == null) {
                                viewModel.onVisibleRoomsChanged(emptyList())
                            } else {
                                val firstVisible = (visibleRange shr 32).toInt().coerceAtLeast(0)
                                val lastVisible = visibleRange.toInt()
                                val fromIndex = firstVisible.coerceAtMost(rooms.size)
                                val toIndex = (lastVisible + 1).coerceIn(fromIndex, rooms.size)
                                viewModel.onVisibleRoomsChanged(rooms.subList(fromIndex, toIndex))
                            }
                        }
                }

                Surface(
                    modifier = contentModifier.fillMaxSize(),
                    shape = Dimens.Inbox.listSurfaceShape,
                    color = MaterialTheme.colorScheme.surface,
                    tonalElevation = 0.dp,
                ) {
                    Box(
                        Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                    if (rooms.isNullOrEmpty()) {
                        EmptyListScreen(
                            title = Res.string.empty_screen_placeholder_inbox.toStringHolder(),
                            icon = rememberVectorPainter(Icons.Default.Inbox),
                            renderedSearchTerm = roomsState?.searchTerm,
                            isLoading = roomsState == null,
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            if (accounts != null && accounts.isEmpty()) {
                                Text(
                                    stringResource(Res.string.action_account_management),
                                    color = MaterialTheme.scExposures.accentColor,
                                    style = MaterialTheme.typography.labelLarge,
                                    modifier = Modifier
                                        .padding(Dimens.listPadding)
                                        .keyFocusable(
                                            role = FocusRole.AUX_ITEM,
                                            actionProvider = actionProvider(
                                                primaryAction = InteractionAction.Navigate {
                                                    Destination.AccountManagement()
                                                },
                                            ),
                                        ),
                                )
                            }
                        }
                    } else {
                        val pendingTransferHeight = remember { mutableIntStateOf(0) }
                        val extraContentPadding = LocalDensity.current.run {
                            PaddingValues(
                                top = pendingTransferHeight.intValue.toDp(),
                                bottom = KiteSearchBarReserve,
                            )
                        }
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            state = listState,
                            contentPadding = WindowInsets.navigationBars
                                .only(WindowInsetsSides.Bottom)
                                .asPaddingValues() +
                                    extraContentPadding +
                                    PaddingValues(vertical = Dimens.Inbox.listContentPadding),
                        ) {
                            if (!roomsState.searchTerm.isNullOrBlank()) {
                                item(key = "kite-search-results-header") {
                                    Text(
                                        text = stringResource(Res.string.search_results_conversations),
                                        style = MaterialTheme.typography.titleSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(
                                            start = Dimens.windowPadding,
                                            end = Dimens.windowPadding,
                                            top = 8.dp,
                                            bottom = 4.dp,
                                        ),
                                    )
                                }
                            }
                            items(
                                rooms,
                                key = { room -> Pair(room.sessionId, room.summary.roomId) },
                            ) { room ->
                                val needsDisambiguation = needsAccountDisambiguation &&
                                        (
                                                room.summary.isInvite() ||
                                                        (roomsByRoomId[room.summary.roomId]?.size ?: 0) > 1 ||
                                                        room.summary.isDm &&
                                                        (dmsByHeroes[room.summary.info.heroes]?.size ?: 0) > 1
                                                )
                                InboxRow(
                                    viewModel,
                                    room,
                                    hasDraft = room.key in drafts.value,
                                    user = remember(accounts) { accounts?.get(room.sessionId)?.user },
                                    needsAccountDisambiguation = needsDisambiguation,
                                    pendingForward = pendingForward,
                                    unreadCountPreferences = unreadCountPreferences,
                                )
                            }
                        }

                        val incomingShare = IncomingShare.share.collectAsState(null).value
                        if (pendingForward != null || incomingShare != null) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .align(Alignment.TopCenter),
                                contentAlignment = Alignment.Center,
                            ) {
                                val noticeModifier = Modifier
                                    .onGloballyPositioned {
                                        pendingTransferHeight.intValue = it.size.height
                                    }
                                    .padding(
                                        horizontal = Dimens.windowPadding,
                                        vertical = Dimens.listPadding,
                                    )
                                if (pendingForward != null) {
                                    MessageForwardNoticeCard(
                                        forward = pendingForward,
                                        modifier = noticeModifier,
                                    )
                                } else if (incomingShare != null) {
                                    IncomingShareNoticeCard(
                                        share = incomingShare,
                                        modifier = noticeModifier,
                                    )
                                }
                            }
                        } else {
                            SideEffect {
                                pendingTransferHeight.intValue = 0
                            }
                        }
                    }
                    }
                }
            }

            val destinationState = LocalDestinationState.current
            if (searchQuery == null && destinationState != null) {
                Button(
                    onClick = {
                        destinationState.navigate(Destination.StartChat(preferredAccount?.sessionId))
                    },
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(
                            end = Dimens.windowPadding,
                            bottom = compactSearchBottomPadding + KiteSearchBarReserve + KiteStartChatBottomGap,
                        )
                        .heightIn(min = 56.dp),
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
                    contentPadding = PaddingValues(horizontal = 18.dp),
                ) {
                    Icon(
                        Icons.Outlined.ChatBubbleOutline,
                        contentDescription = null,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text = stringResource(Res.string.action_start_chat),
                        style = MaterialTheme.typography.labelLarge,
                    )
                }
            }

            KiteInboxSearchBar(
                viewModel = viewModel,
                query = searchQuery,
                account = preferredAccount,
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .padding(
                        start = Dimens.windowPadding,
                        end = Dimens.windowPadding,
                        bottom = compactSearchBottomPadding,
                    ),
            )
        }
    }
}
