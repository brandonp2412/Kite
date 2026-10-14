package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.TopNavigation
import chat.schildi.revenge.compose.components.TopNavigationCloseOrNavigateToInboxIcon
import chat.schildi.revenge.compose.components.TopNavigationTitle
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.conversation.StartChatSearchState
import chat.schildi.revenge.model.conversation.StartChatViewModel
import chat.schildi.revenge.publishTitle
import chat.schildi.revenge.viewModelKey
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.user.MatrixUser
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_clear_search
import shire.res.generated.resources.action_start_chat
import shire.res.generated.resources.create_room
import shire.res.generated.resources.hint_search_people
import shire.res.generated.resources.start_chat_account
import shire.res.generated.resources.start_chat_no_results
import shire.res.generated.resources.start_chat_people
import shire.res.generated.resources.start_chat_search_hint

private val StartChatSearchShape = RoundedCornerShape(28.dp)
private val StartChatPanelShape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)

@Composable
fun StartChatScreen(
    destination: Destination.StartChat,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    val viewModel: StartChatViewModel = viewModel(
        key = viewModelKey(destination),
        factory = StartChatViewModel.factory(destination.initialSessionId),
    )
    publishTitle(viewModel)

    val query = viewModel.query.collectAsState().value
    val searchState = viewModel.searchState.collectAsState().value
    val selectedSessionId = viewModel.sessionId.collectAsState().value
    val availableSessionIds = viewModel.availableSessionIds.collectAsState().value
    val startingUserId = viewModel.startingUserId.collectAsState().value
    val destinationState = LocalDestinationState.current
    val actionContext = currentActionContext()
    val listState = rememberLazyListState()

    FocusContainer(
        LocalListActionProvider provides rememberListActions(listState),
        modifier = modifier
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .fillMaxSize(),
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
    ) {
        Column(
            Modifier.fillMaxSize(),
        ) {
            TopNavigation(forceVisible = true) {
                TopNavigationCloseOrNavigateToInboxIcon(backStyle = true)
                TopNavigationTitle(stringResource(Res.string.action_start_chat))
            }

            Surface(
                modifier = contentModifier.fillMaxSize(),
                shape = StartChatPanelShape,
                color = MaterialTheme.colorScheme.surface,
                tonalElevation = 0.dp,
            ) {
                Column(
                    Modifier.fillMaxSize(),
                ) {
                    TextField(
                        value = query,
                        onValueChange = viewModel::setQuery,
                        placeholder = {
                            Text(
                                text = stringResource(Res.string.hint_search_people),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        leadingIcon = {
                            Icon(Icons.Default.Search, contentDescription = null)
                        },
                        trailingIcon = if (query.isNotEmpty()) {
                            {
                                IconButton(onClick = { viewModel.setQuery("") }) {
                                    Icon(
                                        Icons.Default.Clear,
                                        contentDescription = stringResource(Res.string.action_clear_search),
                                    )
                                }
                            }
                        } else {
                            null
                        },
                        singleLine = true,
                        shape = StartChatSearchShape,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = {}),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(
                                start = Dimens.windowPadding,
                                end = Dimens.windowPadding,
                                top = 12.dp,
                                bottom = 8.dp,
                            )
                            .heightIn(min = 56.dp)
                            .keyFocusable(role = FocusRole.SEARCH_BAR),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                            disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            disabledIndicatorColor = Color.Transparent,
                        ),
                    )

                    if (availableSessionIds.size > 1) {
                        Text(
                            text = stringResource(Res.string.start_chat_account),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(
                                start = Dimens.windowPadding,
                                end = Dimens.windowPadding,
                                top = 4.dp,
                            ),
                        )
                        LazyRow(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            contentPadding = PaddingValues(
                                start = Dimens.windowPadding,
                                end = Dimens.windowPadding,
                                bottom = 8.dp,
                            ),
                        ) {
                            items(availableSessionIds, key = SessionId::value) { sessionId ->
                                FilterChip(
                                    selected = sessionId == selectedSessionId,
                                    onClick = { viewModel.selectSession(sessionId) },
                                    label = {
                                        Text(
                                            sessionId.value,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    },
                                )
                            }
                        }
                    }

                    FilledTonalButton(
                        onClick = {
                            destinationState?.navigate(Destination.CreateRoom(selectedSessionId))
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = Dimens.windowPadding, vertical = 4.dp)
                            .heightIn(min = 52.dp),
                        shape = RoundedCornerShape(20.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        ),
                    ) {
                        Icon(Icons.Default.GroupAdd, contentDescription = null)
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = stringResource(Res.string.create_room),
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }

                    when (val state = searchState) {
                        StartChatSearchState.Idle -> {
                            StartChatCenteredState(
                                text = stringResource(Res.string.start_chat_search_hint),
                            )
                        }
                        is StartChatSearchState.Loading -> {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(28.dp),
                                    strokeWidth = 2.dp,
                                )
                            }
                        }
                        is StartChatSearchState.Failure -> {
                            StartChatCenteredState(
                                text = state.message
                                    ?.takeIf(String::isNotBlank)
                                    ?: stringResource(Res.string.start_chat_no_results),
                                error = true,
                            )
                        }
                        is StartChatSearchState.Results -> {
                            if (state.users.isEmpty()) {
                                StartChatCenteredState(
                                    text = stringResource(Res.string.start_chat_no_results),
                                )
                            } else {
                                Text(
                                    text = stringResource(Res.string.start_chat_people),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(
                                        start = Dimens.windowPadding,
                                        end = Dimens.windowPadding,
                                        top = 12.dp,
                                        bottom = 4.dp,
                                    ),
                                )
                                LazyColumn(
                                    modifier = Modifier.fillMaxSize(),
                                    state = listState,
                                    contentPadding = WindowInsets.navigationBars
                                        .only(WindowInsetsSides.Bottom)
                                        .asPaddingValues(),
                                ) {
                                    items(
                                        state.users,
                                        key = { it.userId.value },
                                    ) { user ->
                                        StartChatUserRow(
                                            user = user,
                                            sessionId = selectedSessionId,
                                            starting = startingUserId == user.userId,
                                            enabled = startingUserId == null,
                                            onClick = {
                                                viewModel.startChat(user.userId, actionContext)
                                            },
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
private fun StartChatUserRow(
    user: MatrixUser,
    sessionId: SessionId?,
    starting: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val displayName = user.displayName?.takeIf(String::isNotBlank) ?: user.userId.value

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 76.dp)
            .keyFocusable(
                role = FocusRole.LIST_ITEM,
                actionProvider = actionProvider(
                    primaryAction = if (enabled) {
                        InteractionAction.Invoke {
                            onClick()
                            true
                        }
                    } else {
                        null
                    },
                ),
                enableClicks = enabled,
            )
            .padding(horizontal = Dimens.windowPadding, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarImage(
            source = user.avatarUrl?.let(::MediaSource),
            size = 52.dp,
            sessionId = sessionId,
            shape = CircleShape,
            displayName = displayName,
            contentDescription = user.userId.value,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = displayName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = user.userId.value,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (starting) {
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                strokeWidth = 2.dp,
            )
        }
    }
}

@Composable
private fun StartChatCenteredState(
    text: String,
    error: Boolean = false,
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = if (error) {
                MaterialTheme.colorScheme.errorContainer
            } else {
                MaterialTheme.colorScheme.surfaceContainerLow
            },
            tonalElevation = 0.dp,
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = if (error) {
                    MaterialTheme.colorScheme.onErrorContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp),
            )
        }
    }
}
