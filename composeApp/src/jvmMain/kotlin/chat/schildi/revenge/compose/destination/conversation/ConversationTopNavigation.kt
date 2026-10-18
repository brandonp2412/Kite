package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.PestControlRodent
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.NavigationPreference
import chat.schildi.revenge.platformWindowManager
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.ContextMenuActionEntry
import chat.schildi.revenge.compose.components.ContextMenuDecoration
import chat.schildi.revenge.compose.components.TopNavigation
import chat.schildi.revenge.compose.components.TopNavigationCloseOrNavigateToInboxIcon
import chat.schildi.revenge.compose.components.TopNavigationIcon
import chat.schildi.revenge.compose.components.TopNavigationTitle
import chat.schildi.revenge.compose.components.WithContextMenu
import chat.schildi.revenge.compose.focus.LocalFocusParent
import chat.schildi.revenge.compose.search.LocalSearchProvider
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.compose.focus.rememberFocusId
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.config.keybindings.DestinationEnum
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.model.conversation.RoomPreviewViewModel
import chat.schildi.revenge.preferences.isEnabled
import chat.schildi.revenge.preferences.value
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.CreateTimelineParams
import kotlinx.collections.immutable.persistentListOf
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_close
import shire.res.generated.resources.action_close_unread
import shire.res.generated.resources.action_show_room_members
import shire.res.generated.resources.dev_tools_title
import shire.res.generated.resources.hint_search
import shire.res.generated.resources.keep_24px
import shire.res.generated.resources.pinned_messages
import shire.res.generated.resources.pref_always_show_sdk_unread_line_title_short
import shire.res.generated.resources.pref_show_dev_infos_title_short
import shire.res.generated.resources.pref_threaded_replies_in_main_timeline_title_short
import shire.res.generated.resources.pref_view_hidden_events_title_short
import shire.res.generated.resources.pref_view_redactions_title_short
import shire.res.generated.resources.room_details_title
import shire.res.generated.resources.selection_messages_count
import shire.res.generated.resources.thread
import shire.res.generated.resources.thread_in


@Composable
private fun RowScope.ConversationParticipantHeader(
    title: String,
    avatar: MediaSource?,
    userId: UserId?,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = Dimens.topAppBarMinHeight)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarImage(
            source = avatar,
            userId = userId,
            size = 36.dp,
            displayName = title,
            shape = CircleShape,
        )
        Text(
            text = title,
            modifier = Modifier
                .weight(1f)
                .padding(start = 10.dp, end = 4.dp),
            color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun ConversationTopNavigation(
    viewModel: RoomPreviewViewModel,
    hasTimeline: Boolean,
    compact: Boolean,
    selectionCount: Int = 0,
    onClearSelection: (() -> Unit)? = null,
    selectionActions: MessageSelectionActions? = null,
    isSearchVisible: Boolean = false,
) {
    val roomInfo = viewModel.roomInfo.collectAsState(null).value
    val title = if ((viewModel as? ConversationViewModel)?.threadId?.collectAsState()?.value != null) {
        roomInfo?.name?.let {
            stringResource(Res.string.thread_in, it)
        } ?: stringResource(Res.string.thread)
    } else {
        roomInfo?.name ?: ""
    }
    val directHero = roomInfo?.heroes?.singleOrNull()
        ?.takeIf { roomInfo.joinedMembersCount <= 2 }
    val avatar = (roomInfo?.avatarUrl ?: directHero?.avatarUrl)?.let(::MediaSource)
    val keyHandler = LocalKeyboardActionHandler.current
    val focusParent = LocalFocusParent.current
    val destinationState = LocalDestinationState.current
    val focusManager = LocalFocusManager.current
    val detailsDestination = directHero
        ?.let { hero -> Destination.UserDetails(viewModel.sessionId, hero.userId, viewModel.roomId) }
        ?: Destination.RoomDetails(viewModel.sessionId, viewModel.roomId)
    val searchProvider = LocalSearchProvider.current
    TopNavigation(forceVisible = compact) {
        if (selectionCount > 0 && onClearSelection != null) {
            TopNavigationIcon(
                Icons.Default.Close,
                stringResource(Res.string.action_close),
                onClick = onClearSelection,
            )
            TopNavigationTitle(stringResource(Res.string.selection_messages_count, selectionCount))
            selectionActions?.let { MessageSelectionActions(it) }
            return@TopNavigation
        }
        // Current Messages treats in-chat search as its own mode instead of squeezing
        // an editable field beside the avatar/title. The actual query control lives
        // at the bottom of ConversationScreen.
        if (isSearchVisible && searchProvider != null) {
            TopNavigationIcon(
                Icons.AutoMirrored.Filled.ArrowBack,
                stringResource(Res.string.action_close),
            ) {
                keyHandler.clearSearch()
                focusManager.clearFocus()
            }
            TopNavigationTitle(title)
            return@TopNavigation
        }
        if (compact) {
            TopNavigationIcon(
                Icons.AutoMirrored.Filled.ArrowBack,
                stringResource(Res.string.action_close),
            ) {
                if (!platformWindowManager.appOwnsWindows) {
                    destinationState?.navigate(Destination.Inbox, NavigationPreference.REPLACE)
                } else {
                    destinationState?.closeScreen(keyHandler)
                }
            }
        }

        when (viewModel.timelineParams) {
            is CreateTimelineParams.Threaded -> TopNavigationTitle(stringResource(Res.string.thread))
            is CreateTimelineParams.PinnedOnly -> TopNavigationTitle(stringResource(Res.string.pinned_messages))
            else -> {
                ConversationParticipantHeader(
                    title = title,
                    avatar = avatar,
                    userId = directHero?.userId?.takeIf { roomInfo.avatarUrl == null },
                    onClick = { destinationState?.navigate(detailsDestination) },
                )
                if (focusParent != null) {
                    // In compact mode, hide what can be reached via room click or room details anyway
                    if (!compact) {
                        TopNavigationIcon(
                            Icons.Default.Info,
                            stringResource(Res.string.room_details_title),
                        ) {
                            destinationState?.navigate(Destination.RoomDetails(viewModel.sessionId, viewModel.roomId))
                        }
                        TopNavigationIcon(
                            Icons.Default.Group,
                            stringResource(Res.string.action_show_room_members),
                        ) {
                            destinationState?.navigate(Destination.RoomMembers(viewModel.sessionId, viewModel.roomId))
                        }
                    }
                    if (ScPrefs.DEV_QUICK_OPTIONS.value()) {
                        val focusId = rememberFocusId()
                        WithContextMenu(
                            focusId = focusId,
                            entries = persistentListOf(
                                ContextMenuActionEntry(
                                    Res.string.pref_view_redactions_title_short.toStringHolder(),
                                    null,
                                    Action.Global.ToggleSetting,
                                    persistentListOf(
                                        ScPrefs.VIEW_REDACTIONS.sKey,
                                    ),
                                    keyboardShortcut = Key.R,
                                    decoration = ContextMenuDecoration.Toggle(ScPrefs.VIEW_REDACTIONS.value()),
                                    enabled = ScPrefs.VIEW_REDACTIONS.isEnabled(),
                                ),
                                ContextMenuActionEntry(
                                    Res.string.pref_view_hidden_events_title_short.toStringHolder(),
                                    null,
                                    Action.Global.ToggleSetting,
                                    persistentListOf(
                                        ScPrefs.VIEW_HIDDEN_EVENTS.sKey,
                                    ),
                                    keyboardShortcut = Key.H,
                                    decoration = ContextMenuDecoration.Toggle(ScPrefs.VIEW_HIDDEN_EVENTS.value()),
                                    enabled = ScPrefs.VIEW_HIDDEN_EVENTS.isEnabled(),
                                ),
                                ContextMenuActionEntry(
                                    Res.string.pref_threaded_replies_in_main_timeline_title_short.toStringHolder(),
                                    null,
                                    Action.Global.ToggleSetting,
                                    persistentListOf(
                                        ScPrefs.THREAD_REPLIES_IN_MAIN_TIMELINE.sKey,
                                    ),
                                    keyboardShortcut = Key.T,
                                    decoration = ContextMenuDecoration.Toggle(ScPrefs.THREAD_REPLIES_IN_MAIN_TIMELINE.value()),
                                    enabled = ScPrefs.THREAD_REPLIES_IN_MAIN_TIMELINE.isEnabled(),
                                ),
                                ContextMenuActionEntry(
                                    Res.string.pref_show_dev_infos_title_short.toStringHolder(),
                                    null,
                                    Action.Global.ToggleSetting,
                                    persistentListOf(
                                        ScPrefs.SHOW_DEV_INFOS.sKey,
                                    ),
                                    keyboardShortcut = Key.I,
                                    decoration = ContextMenuDecoration.Toggle(ScPrefs.SHOW_DEV_INFOS.value()),
                                    enabled = ScPrefs.SHOW_DEV_INFOS.isEnabled(),
                                ),
                                ContextMenuActionEntry(
                                    Res.string.pref_always_show_sdk_unread_line_title_short.toStringHolder(),
                                    null,
                                    Action.Global.ToggleSetting,
                                    persistentListOf(
                                        ScPrefs.ALWAYS_SHOW_SDK_UNREAD_LINE.sKey,
                                    ),
                                    keyboardShortcut = Key.R,
                                    decoration = ContextMenuDecoration.Toggle(ScPrefs.ALWAYS_SHOW_SDK_UNREAD_LINE.value()),
                                    enabled = ScPrefs.ALWAYS_SHOW_SDK_UNREAD_LINE.isEnabled(),
                                ),
                                ContextMenuActionEntry(
                                    Res.string.dev_tools_title.toStringHolder(),
                                    null,
                                    Action.Navigation.NavigateAuto,
                                    persistentListOf(
                                        DestinationEnum.RoomDevTools.destName,
                                        viewModel.sessionId.value,
                                        viewModel.roomId.value,
                                    ),
                                    keyboardShortcut = Key.D,
                                ),
                            ),
                        ) { openContextMenu ->
                            TopNavigationIcon(
                                Icons.Default.PestControlRodent,
                                stringResource(Res.string.dev_tools_title),
                                modifier = Modifier.keyFocusable(
                                    FocusRole.SHADOW_ITEM,
                                    id = focusId,
                                    actionProvider = actionProvider(
                                        primaryAction = openContextMenu,
                                    ),
                                    addClickListener = false,
                                ),
                            ) {
                                openContextMenu ?: return@TopNavigationIcon
                                keyHandler.executeAction(openContextMenu, destinationState)
                            }
                        }
                    }
                    if (hasTimeline) {
                        if (!roomInfo?.pinnedEventIds.isNullOrEmpty()) {
                            TopNavigationIcon(
                                painterResource(Res.drawable.keep_24px),
                                stringResource(Res.string.pinned_messages),
                            ) {
                                destinationState?.navigate(Destination.Conversation(viewModel.sessionId, viewModel.roomId, CreateTimelineParams.PinnedOnly))
                            }
                        }
                    }
                }
            }
        }
        if (hasTimeline && searchProvider != null) {
            TopNavigationIcon(
                Icons.Default.Search,
                stringResource(Res.string.hint_search),
            ) {
                keyHandler.onSearchEnter(searchProvider, null, "")
            }
        }
        if (compact) {
            return@TopNavigation
        }

        val canBypassMarkReadOnClose = ScPrefs.AUTO_MARK_AS_READ_TRIGGER.value() == ScPrefs.AutoMarkAsReadTrigger.ROOM_CLOSE.name
        if (canBypassMarkReadOnClose) {
            val directLongpressAction = ScPrefs.LONGPRESS_CLOSE_TO_UNREAD.value()
            val focusId = rememberFocusId()
            WithContextMenu(
                focusId = focusId,
                entries = persistentListOf(
                    ContextMenuActionEntry(
                        Res.string.action_close.toStringHolder(),
                        null,
                        Action.Navigation.CloseDestination,
                        keyboardShortcut = Key.C,
                    ),
                    ContextMenuActionEntry(
                        Res.string.action_close_unread.toStringHolder(),
                        null,
                        Action.Conversation.CloseConversationBypassingReadTracking,
                        keyboardShortcut = Key.U,
                    ),
                ),
            ) { openContextMenu ->
                // Cannot use TopNavigationIcon / IconButton for longpress actions :/
                Icon(
                    Icons.Default.Close,
                    stringResource(Res.string.action_close),
                    modifier = Modifier.keyFocusable(
                        FocusRole.SHADOW_ITEM,
                        id = focusId,
                        actionProvider = actionProvider(
                            primaryAction = InteractionAction.Invoke {
                                destinationState?.closeScreen(keyHandler)
                                true
                            },
                            secondaryAction = if (directLongpressAction) {
                                InteractionAction.HandleAction(focusId, Action.Conversation.CloseConversationBypassingReadTracking)
                            } else {
                                openContextMenu
                            },
                        ),
                    ).minimumInteractiveComponentSize().size(24.dp),
                )
            }
        } else {
            TopNavigationCloseOrNavigateToInboxIcon()
        }
    }
}
