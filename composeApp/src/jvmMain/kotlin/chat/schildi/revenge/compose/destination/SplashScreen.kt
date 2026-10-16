package chat.schildi.revenge.compose.destination

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.compose.components.ScreenLoadProgressDetails
import chat.schildi.revenge.compose.components.rememberTransientLoadingVisible
import chat.schildi.revenge.compose.components.TransientLoadingGracePeriodMillis
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.model.CheckpointLoadState
import chat.schildi.revenge.model.LoadState
import kotlinx.coroutines.flow.StateFlow

@Composable
fun SplashScreen(
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    FocusContainer(
        modifier = modifier.safeDrawingPadding().fillMaxSize(),
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
    ) {
        SplashScreenContent(contentModifier, UiState.globalLoadState.state)
    }
}

@Composable
fun SplashScreenContent(
    modifier: Modifier = Modifier,
    loadState: StateFlow<LoadState>? = null,
    delayMillis: Long = TransientLoadingGracePeriodMillis,
) {
    // Room and inbox data frequently arrives within a frame or two. Keep those fast
    // transitions visually silent. Sustained work uses a restrained linear indicator instead
    // of a circular spinner, while failures still surface immediately with their details.
    val currentLoadState = loadState?.collectAsState()?.value
    val hasFailure = currentLoadState?.any { it.state == CheckpointLoadState.FAILED } == true
    val showLoadingChrome = rememberTransientLoadingVisible(forceVisible = hasFailure, delayMillis = delayMillis)
    if (showLoadingChrome) {
        Column(
            modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Dimens.verticalArrangementBig,
        ) {
            if (!hasFailure) {
                LinearProgressIndicator(
                    modifier = Modifier
                        .width(64.dp)
                        .height(2.dp),
                )
            }
            if (currentLoadState != null) {
                ScreenLoadProgressDetails(currentLoadState)
            }
        }
    }
}
