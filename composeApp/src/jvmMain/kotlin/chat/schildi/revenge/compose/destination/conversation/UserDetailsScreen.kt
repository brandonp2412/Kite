package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.LocalUserIdSuggestionsProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.actions.plainTextCopyActionWithMxcUrl
import chat.schildi.revenge.actions.plainTextCopyActionWithUserId
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.EmptyListScreen
import chat.schildi.revenge.compose.destination.conversation.userlist.ConversationDetailsTopNavigation
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.model.UserDetailsViewModel
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.viewModelKey
import io.element.android.libraries.matrix.api.MutualRoomsPagedInfo
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.room.RoomInfo
import kotlinx.collections.immutable.ImmutableList
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.pluralStringResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.empty_screen_placeholder_unexpected
import shire.res.generated.resources.n_mutual_rooms
import shire.res.generated.resources.n_mutual_rooms_header
import shire.res.generated.resources.n_mutual_rooms_such_as
import shire.res.generated.resources.room_type_space
import shire.res.generated.resources.room_type_tombstoned

@Composable
fun UserDetailsScreen(
    destination: Destination.UserDetails,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    val viewModel: UserDetailsViewModel =
        viewModel(
            key = viewModelKey(destination),
            factory =
                UserDetailsViewModel.factory(
                    destination.sessionId,
                    destination.userId,
                    destination.roomId,
                ),
        )

    val listState = rememberLazyListState()
    val listAction = rememberListActions(listState)
    FocusContainer(
        LocalUserIdSuggestionsProvider provides viewModel,
        LocalListActionProvider provides listAction,
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
        modifier = modifier.windowInsetsPadding(
            WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
        ).fillMaxSize(),
    ) {
        val info = viewModel.globalUserInfo.collectAsState().value
        val roomMemberInfo = viewModel.roomMember.collectAsState().value
        val mutualRoomsInfo = viewModel.mutualRooms.collectAsState(null).value
        val mutualRoomsPreview = viewModel.mutualRoomsPreview.collectAsState().value
        val expandRoomPreviews = remember { mutableStateOf(false) }
        Column(contentModifier.fillMaxSize()) {
            ConversationDetailsTopNavigation(info?.displayName ?: viewModel.userId.value)
            if (info == null && roomMemberInfo == null) {
                EmptyListScreen(
                    title = Res.string.empty_screen_placeholder_unexpected.toStringHolder(),
                    icon = rememberVectorPainter(Icons.Default.Person),
                    isSearching = false,
                    isLoading = true,
                    loadState = viewModel.loadState,
                    modifier = Modifier.fillMaxWidth().padding(Dimens.windowPadding).weight(1f),
                )
            } else {
                Box(
                    Modifier.fillMaxWidth().padding(Dimens.windowPadding).weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    LazyColumn(
                        state = listState,
                        verticalArrangement = Dimens.verticalArrangement,
                        contentPadding = WindowInsets.navigationBars
                            .only(WindowInsetsSides.Bottom)
                            .asPaddingValues(),
                    ) {
                        item {
                            val primaryAvatar = roomMemberInfo?.avatarUrl ?: info?.avatarUrl
                            Box(
                                Modifier.fillMaxWidth().keyFocusable(
                                    role = FocusRole.LIST_ITEM,
                                    actionProvider = actionProvider(
                                        copyActions = plainTextCopyActionWithMxcUrl(primaryAvatar),
                                    )
                                ),
                                contentAlignment = Alignment.Center,
                            ) {
                                AvatarImage(
                                    source = primaryAvatar?.let { MediaSource(it) },
                                    size = 104.dp,
                                    displayName = roomMemberInfo?.displayName ?: info?.displayName ?: viewModel.userId.value,
                                    shape = CircleShape,
                                    modifier = Modifier.keyFocusable(
                                        role = FocusRole.NESTED_AUX_ITEM,
                                        actionProvider = actionProvider(
                                            copyActions = plainTextCopyActionWithMxcUrl(primaryAvatar),
                                        )
                                    ),
                                    allowAnimated = true,
                                )
                            }
                        }
                        val displayName = roomMemberInfo?.displayName ?: info?.displayName
                        if (displayName != null) {
                            item {
                                SelectionContainer {
                                    Box(
                                        Modifier.fillMaxWidth().keyFocusable(
                                            role = FocusRole.LIST_ITEM,
                                            actionProvider = actionProvider(
                                                copyActions = plainTextCopyAction { displayName },
                                            )
                                        ),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            displayName,
                                            color = MaterialTheme.colorScheme.onSurface,
                                            style = MaterialTheme.typography.titleLarge,
                                            textAlign = TextAlign.Center,
                                        )
                                    }
                                }
                            }
                        }
                        item {
                            SelectionContainer {
                                Box(
                                    Modifier.fillMaxWidth().keyFocusable(
                                        role = FocusRole.LIST_ITEM,
                                        actionProvider = actionProvider(
                                            copyActions = plainTextCopyActionWithUserId(viewModel.userId) {
                                                viewModel.userId.value
                                            },
                                        )
                                    ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        viewModel.userId.value,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        style = MaterialTheme.typography.bodyMedium,
                                        textAlign = TextAlign.Center,
                                    )
                                }
                            }
                        }
                        if (mutualRoomsInfo != null) {
                            item {
                                MutualRoomsExpandHeader(
                                    expandRoomPreviews,
                                    mutualRoomsInfo,
                                    mutualRoomsPreview,
                                    Modifier.fillMaxSize(),
                                )
                            }
                        }
                        if (expandRoomPreviews.value && mutualRoomsPreview != null) {
                            items(mutualRoomsPreview, key = { "mutual_room_preview_${it.id}" }) { preview ->
                                MutualRoomsListItem(
                                    viewModel.sessionId,
                                    preview,
                                    Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun MutualRoomsExpandHeader(
    expandRoomPreviews: MutableState<Boolean>,
    mutualRoomsInfo: MutualRoomsPagedInfo,
    mutualRoomsPreview: ImmutableList<RoomInfo>?,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier.keyFocusable(
            role = FocusRole.LIST_ITEM,
            actionProvider = actionProvider(
                primaryAction = InteractionAction.Invoke {
                    expandRoomPreviews.value = !expandRoomPreviews.value
                    true
                }
            ),
        ),
        contentAlignment = Alignment.Center,
    ) {
        val text = if (mutualRoomsPreview.isNullOrEmpty()) {
            pluralStringResource(
                Res.plurals.n_mutual_rooms,
                mutualRoomsInfo.count.toInt(),
                mutualRoomsInfo.count,
            )
        } else if (expandRoomPreviews.value) {
            pluralStringResource(
                Res.plurals.n_mutual_rooms_header,
                mutualRoomsInfo.count.toInt(),
                mutualRoomsInfo.count,
            )
        } else {
            pluralStringResource(
                Res.plurals.n_mutual_rooms_such_as,
                mutualRoomsInfo.count.toInt(),
                mutualRoomsInfo.count,
                mutualRoomsPreview.joinToString(limit = 3) {
                    it.privateRoomName ?: it.name ?: it.id.value
                },
            )
        }
        Text(
            text,
            color = if (expandRoomPreviews.value && !mutualRoomsPreview.isNullOrEmpty())
                MaterialTheme.colorScheme.primary
            else
                MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
fun MutualRoomsListItem(
    sessionId: SessionId,
    preview: RoomInfo,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier.keyFocusable(
            role = FocusRole.LIST_ITEM,
            actionProvider = actionProvider(
                primaryAction = InteractionAction.OpenWindow(
                    preferNewTask = false,
                    initialTitle = {
                        ConversationViewModel.windowTitle(
                            preview,
                            sessionId = sessionId,
                        )
                    },
                ) {
                    if (preview.isSpace) {
                        Destination.SpaceDiscovery(
                            sessionId = sessionId,
                            roomId = preview.id,
                        )
                    } else {
                        Destination.Conversation(
                            sessionId = sessionId,
                            roomId = preview.id,
                        )
                    }
                }
            )
        ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            preview.toTitle(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun RoomInfo.toTitle(): String {
    val name = privateRoomName ?: name ?: id.value
    return if (isSpace || successorRoom != null) {
        val spaceString = if (isSpace) stringResource(Res.string.room_type_space) else null
        val tombstoneString = if (successorRoom != null) stringResource(Res.string.room_type_tombstoned) else null
        buildString {
            append(name)
            append(" [")
            append(
                listOfNotNull(
                    spaceString,
                    tombstoneString,
                ).joinToString()
            )
            append("]")
        }
    } else {
        name
    }
}
