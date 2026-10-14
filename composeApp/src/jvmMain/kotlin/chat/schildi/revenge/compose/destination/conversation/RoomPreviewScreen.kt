package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraintsScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalKeyboardActionProvider
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.LocalRoomContextSuggestionsProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.buildNavigationActionProvider
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.actions.plainTextCopyActionWithMxcUrl
import chat.schildi.revenge.actions.plainTextCopyActionWithUserId
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.WithTrackedAction
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.model.PendingAction
import chat.schildi.revenge.model.conversation.RoomPreviewViewModel
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.room.CurrentUserMembership
import io.element.android.libraries.matrix.api.room.RoomInfo
import io.element.android.libraries.matrix.api.room.RoomType
import io.element.android.libraries.matrix.api.room.preview.RoomPreviewInfo
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_join
import shire.res.generated.resources.action_reject_invite
import shire.res.generated.resources.hint_room_via
import shire.res.generated.resources.message_placeholder_invite_by
import shire.res.generated.resources.message_placeholder_invite_by_disambiguated
import shire.res.generated.resources.room_preview_failed
import shire.res.generated.resources.room_preview_membership_banned
import shire.res.generated.resources.room_preview_membership_invited
import shire.res.generated.resources.room_preview_membership_joined
import shire.res.generated.resources.room_preview_membership_knocked
import shire.res.generated.resources.room_preview_membership_left
import shire.res.generated.resources.room_type_space

@Composable
fun BoxWithConstraintsScope.RoomPreviewScreen(
    roomInfo: RoomInfo?,
    roomPreview: RoomPreviewInfo?,
    viewModel: RoomPreviewViewModel,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    val listAction = rememberListActions(listState)

    val avatarUrl = roomInfo?.avatarUrl ?: roomPreview?.avatarUrl
    val roomName = roomInfo?.name ?: roomPreview?.name
    val privateRoomName = roomInfo?.privateRoomName
    val currentUserMembership = roomInfo?.currentUserMembership ?: roomPreview?.membership
    val inviter = roomInfo?.inviter
    val roomType = roomPreview?.roomType

    val inviterMutualRoomsInfo =
        viewModel.inviterMutualRoomsProvider?.mutualRooms?.collectAsState(null)?.value
    val inviterMutualRoomsPreview =
        viewModel.inviterMutualRoomsProvider?.mutualRoomsPreview?.collectAsState()?.value
    val expandInviterMutualRoomPreviews = remember { mutableStateOf(false) }

    val displayName = buildString {
        append(privateRoomName ?: roomName ?: viewModel.roomId.value)
        if (roomName != null && privateRoomName != null && roomName != privateRoomName) {
            append(" (")
            append(roomName)
            append(")")
        }
    }
    val roomTypeText = when (roomType) {
        is RoomType.Other -> roomType.type
        RoomType.Space -> stringResource(Res.string.room_type_space)
        RoomType.Room, null -> null
    }
    val membershipText = currentUserMembership?.let {
        when (it) {
            CurrentUserMembership.INVITED -> stringResource(Res.string.room_preview_membership_invited)
            CurrentUserMembership.JOINED -> stringResource(Res.string.room_preview_membership_joined)
            CurrentUserMembership.LEFT -> stringResource(Res.string.room_preview_membership_left)
            CurrentUserMembership.KNOCKED -> stringResource(Res.string.room_preview_membership_knocked)
            CurrentUserMembership.BANNED -> stringResource(Res.string.room_preview_membership_banned)
        }
    }

    FocusContainer(
        LocalListActionProvider provides listAction,
        LocalRoomContextSuggestionsProvider provides viewModel.roomContextSuggestionsProvider,
        LocalKeyboardActionProvider provides viewModel.roomActionProvider.hierarchicalKeyboardActionProvider(),
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .fillMaxSize(),
    ) {
        Column(contentModifier.fillMaxSize()) {
            ConversationTopNavigation(
                viewModel,
                hasTimeline = false,
                compact = this@RoomPreviewScreen.maxWidth < Dimens.compactActionBarThreshold,
            )
            Surface(
                modifier = Modifier.fillMaxSize(),
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                Box(
                    Modifier.fillMaxSize().padding(Dimens.windowPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = WindowInsets.navigationBars
                            .only(WindowInsetsSides.Bottom)
                            .asPaddingValues(),
                    ) {
                        if (roomInfo == null && roomPreview == null) {
                            item(key = "preview_error", contentType = "state") {
                                Surface(
                                    modifier = Modifier.fillMaxWidth(),
                                    shape = RoundedCornerShape(20.dp),
                                    color = MaterialTheme.colorScheme.errorContainer,
                                ) {
                                    Text(
                                        stringResource(Res.string.room_preview_failed),
                                        color = MaterialTheme.colorScheme.onErrorContainer,
                                        style = MaterialTheme.typography.titleMedium,
                                        textAlign = TextAlign.Center,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 20.dp, vertical = 24.dp)
                                            .keyFocusable(role = FocusRole.LIST_ITEM),
                                    )
                                }
                            }
                        } else {
                            item(key = "preview_hero", contentType = "hero") {
                                Surface(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .keyFocusable(
                                            role = FocusRole.LIST_ITEM,
                                            actionProvider = actionProvider(
                                                copyActions = plainTextCopyAction { displayName },
                                            ),
                                        ),
                                    shape = RoundedCornerShape(28.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                                    tonalElevation = 0.dp,
                                ) {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 24.dp, vertical = 24.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        AvatarImage(
                                            source = avatarUrl?.let { MediaSource(it) },
                                            size = 104.dp,
                                            displayName = displayName,
                                            shape = CircleShape,
                                            modifier = Modifier.keyFocusable(
                                                role = FocusRole.NESTED_AUX_ITEM,
                                                actionProvider = actionProvider(
                                                    copyActions = plainTextCopyActionWithMxcUrl(avatarUrl),
                                                ),
                                            ),
                                            allowAnimated = true,
                                        )
                                        SelectionContainer {
                                            Text(
                                                displayName,
                                                color = MaterialTheme.colorScheme.onSurface,
                                                style = MaterialTheme.typography.headlineSmall,
                                                textAlign = TextAlign.Center,
                                            )
                                        }
                                        viewModel.alias?.let { alias ->
                                            SelectionContainer {
                                                Text(
                                                    alias.value,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                    style = MaterialTheme.typography.bodyMedium,
                                                    textAlign = TextAlign.Center,
                                                    modifier = Modifier.keyFocusable(
                                                        role = FocusRole.NESTED_AUX_ITEM,
                                                        actionProvider = actionProvider(
                                                            copyActions = plainTextCopyAction { alias.value },
                                                        ),
                                                    ),
                                                )
                                            }
                                        }
                                        if (
                                            roomTypeText != null ||
                                            (
                                                membershipText != null &&
                                                    (currentUserMembership != CurrentUserMembership.INVITED || inviter == null)
                                                )
                                        ) {
                                            FlowRow(
                                                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                roomTypeText?.let {
                                                    RoomPreviewPill(it)
                                                }
                                                if (
                                                    membershipText != null &&
                                                    (currentUserMembership != CurrentUserMembership.INVITED || inviter == null)
                                                ) {
                                                    RoomPreviewPill(membershipText)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        inviter?.let { roomInviter ->
                            item(key = "inviter", contentType = "inviter") {
                                val invitedBy = if (roomInviter.displayName != null) {
                                    stringResource(
                                        Res.string.message_placeholder_invite_by_disambiguated,
                                        roomInviter.displayName ?: "",
                                        roomInviter.userId.value,
                                    )
                                } else {
                                    stringResource(
                                        Res.string.message_placeholder_invite_by,
                                        roomInviter.userId.value,
                                    )
                                }
                                Surface(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .keyFocusable(
                                            role = FocusRole.LIST_ITEM,
                                            actionProvider = buildNavigationActionProvider(
                                                copyActions = plainTextCopyActionWithUserId(roomInviter.userId) {
                                                    invitedBy
                                                },
                                            ) {
                                                Destination.UserDetails(
                                                    viewModel.sessionId,
                                                    roomInviter.userId,
                                                    viewModel.roomId,
                                                )
                                            },
                                        ),
                                    shape = RoundedCornerShape(20.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                                    tonalElevation = 0.dp,
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 14.dp),
                                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        AvatarImage(
                                            source = roomInviter.avatarUrl?.let { MediaSource(it) },
                                            size = 48.dp,
                                            displayName = roomInviter.disambiguatedDisplayName,
                                            shape = CircleShape,
                                            allowAnimated = true,
                                        )
                                        Column(
                                            modifier = Modifier.weight(1f),
                                            verticalArrangement = Arrangement.spacedBy(2.dp),
                                        ) {
                                            Text(
                                                roomInviter.displayName ?: roomInviter.userId.value,
                                                color = MaterialTheme.colorScheme.onSurface,
                                                style = MaterialTheme.typography.titleMedium,
                                            )
                                            Text(
                                                invitedBy,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                style = MaterialTheme.typography.bodyMedium,
                                            )
                                        }
                                    }
                                }
                            }

                            if (inviterMutualRoomsInfo != null) {
                                item(key = "mutual_rooms_header", contentType = "mutual_header") {
                                    MutualRoomsExpandHeader(
                                        expandInviterMutualRoomPreviews,
                                        inviterMutualRoomsInfo,
                                        inviterMutualRoomsPreview,
                                        Modifier.fillMaxWidth(),
                                    )
                                }
                            }
                            if (expandInviterMutualRoomPreviews.value && inviterMutualRoomsPreview != null) {
                                items(
                                    items = inviterMutualRoomsPreview,
                                    key = { "mutual_room_preview_${it.id}" },
                                    contentType = { "mutual_room" },
                                ) { preview ->
                                    MutualRoomsListItem(
                                        viewModel.sessionId,
                                        preview,
                                        Modifier.fillMaxWidth(),
                                    )
                                }
                            }
                        }

                        item(key = "join", contentType = "primary_action") {
                            val actionContext = currentActionContext()
                            fun join(): Boolean {
                                return viewModel.roomActionProvider.handleAction(
                                    actionContext,
                                    Action.Room.Join,
                                    emptyList(),
                                ) is ActionResult.Actioned
                            }
                            WithTrackedAction(PendingAction.RoomJoin(viewModel.roomId)) { enabled ->
                                Button(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(min = 56.dp)
                                        .keyFocusable(
                                            role = FocusRole.LIST_ITEM,
                                            actionProvider = actionProvider(
                                                primaryAction = if (enabled) InteractionAction.Invoke(::join) else null,
                                            ),
                                            addMouseFocusable = false,
                                            addClickListener = false,
                                        ),
                                    enabled = enabled,
                                    shape = RoundedCornerShape(28.dp),
                                    onClick = { join() },
                                ) {
                                    Text(
                                        stringResource(Res.string.action_join),
                                        style = MaterialTheme.typography.labelLarge,
                                    )
                                }
                            }
                        }

                        if (currentUserMembership == CurrentUserMembership.INVITED) {
                            item(key = "reject_invite", contentType = "secondary_action") {
                                val actionContext = currentActionContext()
                                fun leave(): Boolean {
                                    return viewModel.roomActionProvider.handleAction(
                                        actionContext,
                                        Action.Room.Leave,
                                        emptyList(),
                                    ) is ActionResult.Actioned
                                }
                                WithTrackedAction(PendingAction.RoomLeave(viewModel.roomId)) { enabled ->
                                    Button(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .heightIn(min = 52.dp)
                                            .keyFocusable(
                                                role = FocusRole.LIST_ITEM,
                                                actionProvider = actionProvider(
                                                    primaryAction = if (enabled) InteractionAction.Invoke(::leave) else null,
                                                ),
                                                addMouseFocusable = false,
                                                addClickListener = false,
                                            ),
                                        enabled = enabled,
                                        shape = RoundedCornerShape(26.dp),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = MaterialTheme.colorScheme.errorContainer,
                                            contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                        ),
                                        onClick = { leave() },
                                    ) {
                                        Text(
                                            stringResource(Res.string.action_reject_invite),
                                            style = MaterialTheme.typography.labelLarge,
                                        )
                                    }
                                }
                            }
                        }

                        viewModel.joinServerNames?.takeIf { it.isNotEmpty() }?.let { joinServerNames ->
                            item(key = "via_servers", contentType = "metadata") {
                                val serversText = joinServerNames.joinToString()
                                Surface(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .keyFocusable(
                                            role = FocusRole.LIST_ITEM,
                                            actionProvider = actionProvider(
                                                copyActions = plainTextCopyAction { serversText },
                                            ),
                                        ),
                                    shape = RoundedCornerShape(20.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                                    tonalElevation = 0.dp,
                                ) {
                                    SelectionContainer {
                                        Text(
                                            stringResource(Res.string.hint_room_via, serversText),
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            style = MaterialTheme.typography.bodyMedium,
                                            modifier = Modifier.padding(horizontal = 18.dp, vertical = 14.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RoomPreviewPill(
    text: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        tonalElevation = 0.dp,
    ) {
        Text(
            text,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}
