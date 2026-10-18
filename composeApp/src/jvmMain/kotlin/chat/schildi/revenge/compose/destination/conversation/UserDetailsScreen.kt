package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import chat.schildi.revenge.Destination
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.LocalUserIdSuggestionsProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.actions.plainTextCopyActionWithMxcUrl
import chat.schildi.revenge.actions.plainTextCopyActionWithUserId
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.LocalAvatarOverrides
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
import chat.schildi.revenge.util.filepicker.AttachmentPickerKind
import chat.schildi.revenge.util.filepicker.FilePicker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.collections.immutable.ImmutableList
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
    val scope = rememberCoroutineScope()
    val actionContext = currentActionContext()
    var photoError by remember { mutableStateOf<String?>(null) }
    var photoNote by remember { mutableStateOf<String?>(null) }
    FocusContainer(
        LocalUserIdSuggestionsProvider provides viewModel,
        LocalListActionProvider provides listAction,
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .fillMaxSize(),
    ) {
        val info = viewModel.globalUserInfo.collectAsState().value
        val roomMemberInfo = viewModel.roomMember.collectAsState().value
        val mutualRoomsInfo = viewModel.mutualRooms.collectAsState(null).value
        val mutualRoomsPreview = viewModel.mutualRoomsPreview.collectAsState().value
        val expandRoomPreviews = remember { mutableStateOf(false) }
        Column(Modifier.fillMaxSize()) {
            ConversationDetailsTopNavigation(info?.displayName ?: viewModel.userId.value)
            Surface(
                modifier = contentModifier.fillMaxSize(),
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                if (info == null && roomMemberInfo == null) {
                    EmptyListScreen(
                        title = Res.string.empty_screen_placeholder_unexpected.toStringHolder(),
                        icon = rememberVectorPainter(Icons.Default.Person),
                        isSearching = false,
                        isLoading = true,
                        loadState = viewModel.loadState,
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = WindowInsets.navigationBars
                            .only(WindowInsetsSides.Bottom)
                            .asPaddingValues(),
                    ) {
                        item(key = "profile", contentType = "profile") {
                            val primaryAvatar = roomMemberInfo?.avatarUrl ?: info?.avatarUrl
                            val displayName = roomMemberInfo?.displayName ?: info?.displayName
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp),
                                shape = RoundedCornerShape(24.dp),
                                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 24.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    AvatarImage(
                                        source = primaryAvatar?.let { MediaSource(it) },
                                        userId = viewModel.userId,
                                        sessionId = viewModel.sessionId,
                                        size = 96.dp,
                                        displayName = displayName ?: viewModel.userId.value,
                                        shape = CircleShape,
                                        modifier = Modifier.clickable {
                                            scope.launch {
                                                photoError = null
                                                photoNote = null
                                                val result = FilePicker.requestFilePicker(
                                                    "Choose profile image",
                                                    actionContext.windowId,
                                                    AttachmentPickerKind.GALLERY,
                                                )
                                                val selected = result.getOrNull()
                                                if (result.isFailure) {
                                                    photoError = result.exceptionOrNull()?.message ?: "Couldn't open image picker"
                                                } else if (selected != null) {
                                                    try {
                                                        require(selected.mimeType?.startsWith("image/") == true) {
                                                            "Select an image file"
                                                        }
                                                        require(selected.file.length() in 1..20_000_000) {
                                                            "Image must be smaller than 20 MB"
                                                        }
                                                        val own = viewModel.userId.value == viewModel.sessionId.value
                                                        val uploaded = if (own) {
                                                            val client = UiState.currentClientFor(viewModel.sessionId)
                                                            client?.uploadAvatar(
                                                                selected.mimeType,
                                                                withContext(Dispatchers.IO) { selected.file.readBytes() },
                                                            )?.isSuccess == true
                                                        } else false
                                                        LocalAvatarOverrides.set(
                                                            viewModel.sessionId, viewModel.userId, selected.file,
                                                        )
                                                        photoNote = if (uploaded) "Profile image updated" else "Image saved on this device"
                                                    } catch (error: Exception) {
                                                        photoError = error.message ?: "Couldn't save image"
                                                    } finally {
                                                        if (selected.isAppOwned) {
                                                            withContext(Dispatchers.IO) {
                                                                selected.file.parentFile?.deleteRecursively()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        },
                                        contentDescription = "Change profile image",
                                        allowAnimated = true,
                                    )
                                    if (LocalAvatarOverrides.photo(viewModel.sessionId, viewModel.userId) != null) {
                                        TextButton(onClick = {
                                            scope.launch {
                                                LocalAvatarOverrides.clear(viewModel.sessionId, viewModel.userId)
                                                photoNote = "Local image removed"
                                                photoError = null
                                            }
                                        }) { Text("Remove local image") }
                                    }
                                    photoError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                                    photoNote?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                                    if (displayName != null) {
                                        SelectionContainer {
                                            Text(
                                                text = displayName,
                                                color = MaterialTheme.colorScheme.onSurface,
                                                style = MaterialTheme.typography.headlineSmall,
                                                textAlign = TextAlign.Center,
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.keyFocusable(
                                                    role = FocusRole.LIST_ITEM,
                                                    actionProvider = actionProvider(
                                                        copyActions = plainTextCopyAction { displayName },
                                                    ),
                                                ),
                                            )
                                        }
                                    }
                                    SelectionContainer {
                                        Text(
                                            text = viewModel.userId.value,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            style = MaterialTheme.typography.bodyMedium,
                                            textAlign = TextAlign.Center,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.keyFocusable(
                                                role = FocusRole.LIST_ITEM,
                                                actionProvider = actionProvider(
                                                    copyActions = plainTextCopyActionWithUserId(viewModel.userId) {
                                                        viewModel.userId.value
                                                    },
                                                ),
                                            ),
                                        )
                                    }
                                }
                            }
                        }
                        if (mutualRoomsInfo != null) {
                            item(key = "mutual_rooms_header", contentType = "section") {
                                MutualRoomsExpandHeader(
                                    expandRoomPreviews,
                                    mutualRoomsInfo,
                                    mutualRoomsPreview,
                                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                                )
                            }
                        }
                        if (expandRoomPreviews.value && mutualRoomsPreview != null) {
                            items(
                                items = mutualRoomsPreview,
                                key = { "mutual_room_preview_" + it.id },
                                contentType = { "mutual_room" },
                            ) { preview ->
                                MutualRoomsListItem(
                                    viewModel.sessionId,
                                    preview,
                                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
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
    Surface(
        modifier = modifier.keyFocusable(
            role = FocusRole.LIST_ITEM,
            actionProvider = actionProvider(
                primaryAction = InteractionAction.Invoke {
                    expandRoomPreviews.value = !expandRoomPreviews.value
                    true
                }
            ),
        ),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(10.dp).size(20.dp),
                )
            }
            Text(
                text = text,
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            if (!mutualRoomsPreview.isNullOrEmpty()) {
                Icon(
                    imageVector = if (expandRoomPreviews.value) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
fun MutualRoomsListItem(
    sessionId: SessionId,
    preview: RoomInfo,
    modifier: Modifier = Modifier,
) {
    val displayName = preview.privateRoomName ?: preview.name ?: preview.id.value
    Surface(
        modifier = modifier.keyFocusable(
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
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarImage(
                source = preview.avatarUrl?.let { MediaSource(it) },
                size = 44.dp,
                displayName = displayName,
                sessionId = sessionId,
                shape = CircleShape,
            )
            Text(
                text = preview.toTitle(),
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }
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
