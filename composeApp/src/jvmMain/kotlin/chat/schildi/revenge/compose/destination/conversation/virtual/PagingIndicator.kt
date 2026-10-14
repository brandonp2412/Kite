package chat.schildi.revenge.compose.destination.conversation.virtual

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.compose.components.rememberTransientLoadingVisible

@Composable
fun PagingIndicator(modifier: Modifier = Modifier) {
    // Keep the pagination slot stable so a genuinely slow page load cannot move the
    // timeline when its indicator appears. Fast page loads stay visually silent.
    Box(
        modifier.fillMaxWidth().height(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (rememberTransientLoadingVisible()) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
            )
        }
    }
}
