package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.runtime.Composable
import chat.schildi.revenge.Destination
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.compose.components.TopNavigation
import chat.schildi.revenge.compose.components.TopNavigationIcon
import chat.schildi.revenge.compose.components.TopNavigationTitle
import io.element.android.libraries.matrix.api.core.SessionId
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.app_title_short
import shire.res.generated.resources.action_start_chat

@Composable
fun InboxTopNavigation(
    title: String?,
    preferredSessionId: SessionId? = null,
) {
    TopNavigation {
        val destinationState = LocalDestinationState.current
        TopNavigationTitle(title ?: stringResource(Res.string.app_title_short))
        if (destinationState != null) {
            TopNavigationIcon(
                Icons.Outlined.ChatBubbleOutline,
                stringResource(Res.string.action_start_chat),
                tonal = true,
            ) {
                destinationState.navigate(Destination.StartChat(preferredSessionId))
            }
        }
    }
}
