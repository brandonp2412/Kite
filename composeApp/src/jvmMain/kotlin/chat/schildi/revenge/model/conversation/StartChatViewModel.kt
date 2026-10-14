package chat.schildi.revenge.model.conversation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.Destination
import chat.schildi.revenge.NavigationPreference
import chat.schildi.revenge.TitleProvider
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.actions.AppMessage
import io.element.android.libraries.matrix.api.core.MatrixPatterns
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.room.StartDMResult
import io.element.android.libraries.matrix.api.room.startDM
import io.element.android.libraries.matrix.api.user.MatrixUser
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_start_chat
import shire.res.generated.resources.toast_start_chat_error

sealed interface StartChatSearchState {
    data object Idle : StartChatSearchState

    data class Loading(
        val query: String,
    ) : StartChatSearchState

    data class Results(
        val query: String,
        val users: ImmutableList<MatrixUser>,
        val limited: Boolean,
    ) : StartChatSearchState

    data class Failure(
        val query: String,
        val message: String?,
    ) : StartChatSearchState
}

@OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
class StartChatViewModel(
    initialSessionId: SessionId? = null,
) : ViewModel(), TitleProvider {
    private val _sessionId = MutableStateFlow(initialSessionId)
    val sessionId = _sessionId.asStateFlow()

    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()

    private val _startingUserId = MutableStateFlow<UserId?>(null)
    val startingUserId = _startingUserId.asStateFlow()

    val availableSessionIds = combine(
        UiState.matrixClients,
        UiState.sessionIdComparator,
    ) { clients, comparator ->
        clients.keys.sortedWith(comparator).also { sessionIds ->
            if (sessionIds.isNotEmpty() && _sessionId.value == null) {
                _sessionId.value = sessionIds.first()
            }
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val clientFlow = sessionId
        .flatMapLatest { selectedSessionId ->
            selectedSessionId?.let { UiState.selectClient(it, viewModelScope) } ?: flowOf(null)
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val searchState = combine(
        clientFlow,
        query.debounce(220).distinctUntilChanged(),
    ) { client, rawQuery ->
        client to rawQuery.trim()
    }.transformLatest { (client, renderedQuery) ->
        if (renderedQuery.isBlank()) {
            emit(StartChatSearchState.Idle)
            return@transformLatest
        }

        emit(StartChatSearchState.Loading(renderedQuery))
        if (client == null) {
            return@transformLatest
        }

        val result = client.searchUsers(renderedQuery, SEARCH_LIMIT)
        result.fold(
            onSuccess = { searchResults ->
                val exactUser = if (
                    MatrixPatterns.isUserId(renderedQuery) &&
                    searchResults.results.none { it.userId.value == renderedQuery }
                ) {
                    client.getProfile(UserId(renderedQuery)).getOrNull()
                } else {
                    null
                }
                val users = buildList {
                    exactUser?.let(::add)
                    addAll(searchResults.results)
                }.distinctBy(MatrixUser::userId).toPersistentList()
                emit(
                    StartChatSearchState.Results(
                        query = renderedQuery,
                        users = users,
                        limited = searchResults.limited,
                    )
                )
            },
            onFailure = { error ->
                emit(
                    StartChatSearchState.Failure(
                        query = renderedQuery,
                        message = error.message,
                    )
                )
            },
        )
    }
        .flowOn(Dispatchers.IO)
        .stateIn(viewModelScope, SharingStarted.Lazily, StartChatSearchState.Idle)

    override val windowTitle = flowOf(Res.string.action_start_chat.toStringHolder())

    override fun verifyDestination(destination: Destination) = destination is Destination.StartChat

    fun setQuery(query: String) {
        _query.value = query
    }

    fun selectSession(sessionId: SessionId) {
        _sessionId.value = sessionId
    }

    fun startChat(
        userId: UserId,
        context: ActionContext,
    ) {
        if (_startingUserId.value != null) {
            return
        }
        val selectedSessionId = sessionId.value ?: return
        val client = clientFlow.value?.takeIf { it.sessionId == selectedSessionId } ?: return

        _startingUserId.value = userId
        viewModelScope.launch(Dispatchers.IO) {
            try {
                when (
                    val result = client.startDM(
                        userId = userId,
                        createIfDmDoesNotExist = true,
                        isEncryped = true,
                    )
                ) {
                    is StartDMResult.Success -> {
                        context.destinationStateHolder?.navigate(
                            Destination.Conversation(selectedSessionId, result.roomId),
                            NavigationPreference.REPLACE,
                        )
                    }
                    is StartDMResult.Failure -> {
                        context.publishMessage(
                            AppMessage(
                                message = result.throwable.message
                                    ?.takeIf(String::isNotBlank)
                                    ?.toStringHolder()
                                    ?: Res.string.toast_start_chat_error.toStringHolder(),
                                isError = true,
                            )
                        )
                    }
                    StartDMResult.DmDoesNotExist -> {
                        context.publishMessage(
                            AppMessage(
                                message = Res.string.toast_start_chat_error.toStringHolder(),
                                isError = true,
                            )
                        )
                    }
                }
            } finally {
                _startingUserId.update { current ->
                    current?.takeUnless { it == userId }
                }
            }
        }
    }

    companion object {
        private const val SEARCH_LIMIT = 50L

        fun factory(initialSessionId: SessionId?) = viewModelFactory {
            initializer {
                StartChatViewModel(initialSessionId)
            }
        }
    }
}
