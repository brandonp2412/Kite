package chat.schildi.revenge.compose.destination

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.compose.components.ScreenLoadProgressDetails
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.model.CheckpointLoadState
import chat.schildi.revenge.model.LoadState
import kotlinx.coroutines.delay
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
) {
    // Room and inbox data frequently arrives within a frame or two. Rendering the
    // spinner immediately causes an obvious one-frame flash on every navigation.
    // Delay this transient placeholder, but never delay visibility of load failures.
    val currentLoadState = loadState?.collectAsState()?.value
    var gracePeriodElapsed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(LoadingIndicatorGracePeriodMillis)
        gracePeriodElapsed = true
    }
    if (shouldShowLoadingIndicator(gracePeriodElapsed, currentLoadState)) {
        Column(
            modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Dimens.verticalArrangementBig,
        ) {
            CircularProgressIndicator()
            if (currentLoadState != null) {
                ScreenLoadProgressDetails(currentLoadState)
            }
        }
    }
}

internal const val LoadingIndicatorGracePeriodMillis = 350L

internal fun shouldShowLoadingIndicator(gracePeriodElapsed: Boolean, loadState: LoadState?): Boolean =
    gracePeriodElapsed || loadState?.any { it.state == CheckpointLoadState.FAILED } == true
