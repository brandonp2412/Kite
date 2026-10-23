package chat.schildi.revenge.compose.destination.conversation.userlist

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import chat.schildi.revenge.Destination
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.LocalKeyboardActionProvider
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.LocalRoomContextSuggestionsProvider
import chat.schildi.revenge.actions.LocalUserIdSuggestionsProvider
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.EmptyListScreen
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.search.LocalSearchProvider
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.model.userlist.RoomMemberListViewModel
import chat.schildi.revenge.publishTitle
import chat.schildi.revenge.viewModelKey
import org.jetbrains.compose.resources.pluralStringResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.empty_screen_placeholder_room_members
import shire.res.generated.resources.room_members_title_loaded
import shire.res.generated.resources.room_members_title_loading

@Composable
fun RoomMembersScreen(
    destination: Destination.RoomMembers,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    val viewModel: RoomMemberListViewModel =
        viewModel(
            key = viewModelKey(destination),
            factory = RoomMemberListViewModel.factory(destination.sessionId, destination.roomId),
        )
    publishTitle(viewModel)

    val listState = rememberLazyListState()
    val listAction = rememberListActions(listState)
    FocusContainer(
        LocalSearchProvider provides viewModel,
        LocalUserIdSuggestionsProvider provides viewModel,
        LocalRoomContextSuggestionsProvider provides viewModel.roomContextSuggestionsProvider,
        LocalKeyboardActionProvider provides viewModel.actionProvider.hierarchicalKeyboardActionProvider(),
        LocalListActionProvider provides listAction,
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .fillMaxSize(),
    ) {
        val membersState = viewModel.entries.collectAsState(null).value
        val members = membersState?.items
        Column(contentModifier.fillMaxSize()) {
            ConversationDetailsTopNavigation(
                if (members == null)
                    stringResource(Res.string.room_members_title_loading)
                else
                    pluralStringResource(Res.plurals.room_members_title_loaded, members.size, members.size)
            )
            Surface(
                modifier = contentModifier.fillMaxWidth().weight(1f),
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                if (members.isNullOrEmpty()) {
                    EmptyListScreen(
                        title = Res.string.empty_screen_placeholder_room_members.toStringHolder(),
                        icon = rememberVectorPainter(Icons.Default.Groups),
                        renderedSearchTerm = membersState?.searchTerm,
                        isLoading = members == null,
                        loadState = viewModel.loadState,
                        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                    )
                } else {
                    LazyColumn(
                        Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 12.dp),
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = WindowInsets.navigationBars
                            .only(WindowInsetsSides.Bottom)
                            .asPaddingValues(),
                    ) {
                        items(
                            members,
                            key = { item -> item.userId },
                            contentType = { "room-member" },
                        ) { roomMember ->
                            RoomMemberRow(
                                roomMember = roomMember,
                                viewModel = viewModel,
                            )
                        }
                    }
                }
            }
        }
    }
}
