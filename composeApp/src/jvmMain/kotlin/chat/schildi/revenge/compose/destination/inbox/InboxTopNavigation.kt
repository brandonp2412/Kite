package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.runtime.Composable
import chat.schildi.revenge.compose.components.TopNavigation
import chat.schildi.revenge.compose.components.TopNavigationTitle
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.app_title_short

@Composable
fun InboxTopNavigation(title: String?) {
    TopNavigation {
        TopNavigationTitle(title ?: stringResource(Res.string.app_title_short))
    }
}
