package chat.schildi.revenge.compose.destination.conversation.virtual

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.compose.components.rememberTransientLoadingVisible

@Composable
fun PagingIndicator(modifier: Modifier = Modifier) {
    // Keep the pagination slot stable so a genuinely slow page load cannot move the
    // timeline. Fast loads stay visually silent; sustained loads use a restrained
    // Messages-style progress line rather than a circular spinner inside the history.
    Box(
        modifier.fillMaxWidth().height(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (rememberTransientLoadingVisible()) {
            LinearProgressIndicator(
                modifier = Modifier
                    .width(56.dp)
                    .height(2.dp),
            )
        }
    }
}
