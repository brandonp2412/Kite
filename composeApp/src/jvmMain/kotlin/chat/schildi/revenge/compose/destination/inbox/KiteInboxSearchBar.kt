package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Destination
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.PlatformBackHandler
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.InboxAccount
import chat.schildi.revenge.model.InboxViewModel
import io.element.android.libraries.matrix.api.media.MediaSource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_clear_search
import shire.res.generated.resources.hint_settings

private val KiteSearchShape = RoundedCornerShape(12.dp)

@Composable
fun KiteInboxSearchBar(
    viewModel: InboxViewModel,
    query: String?,
    account: InboxAccount?,
    modifier: Modifier = Modifier,
) {
    val handler = LocalKeyboardActionHandler.current
    val destinationState = LocalDestinationState.current
    val searchActive = query != null

    PlatformBackHandler(enabled = searchActive) {
        handler.clearSearch()
    }

    TextField(
        value = query.orEmpty(),
        onValueChange = { value ->
            handler.onSearchType(value, viewModel, null)
        },
        placeholder = {
            Text(
                text = "Search...",
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        },
        leadingIcon = {
            if (searchActive) {
                IconButton(
                    onClick = handler::clearSearch,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = stringResource(Res.string.action_clear_search),
                    )
                }
            } else {
                Icon(
                    Icons.Default.Search,
                    contentDescription = null,
                )
            }
        },
        trailingIcon = {
            IconButton(
                onClick = {
                    destinationState?.navigate(Destination.Settings())
                },
                modifier = Modifier.size(56.dp),
            ) {
                if (account != null) {
                    AvatarImage(
                        source = account.avatarUrl?.let(::MediaSource),
                        size = 44.dp,
                        sessionId = account.sessionId,
                        shape = KiteSearchShape,
                        displayName = account.displayName ?: account.sessionId.value,
                        contentDescription = stringResource(Res.string.hint_settings),
                    )
                } else {
                    Icon(
                        Icons.Default.Settings,
                        contentDescription = stringResource(Res.string.hint_settings),
                    )
                }
            }
        },
        singleLine = true,
        shape = KiteSearchShape,
        keyboardActions = KeyboardActions {
            handler.onSearchEnter(viewModel, null)
        },
        modifier = modifier
            .keyFocusable(role = FocusRole.SEARCH_BAR),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
            unfocusedContainerColor = MaterialTheme.colorScheme.secondaryContainer,
            disabledContainerColor = MaterialTheme.colorScheme.secondaryContainer,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}
