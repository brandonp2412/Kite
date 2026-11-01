package chat.schildi.revenge.compose.destination

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.imeAnimationSource
import androidx.compose.foundation.layout.imeAnimationTarget
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalDensity

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal actual fun isImeTransitionInProgress(): Boolean {
    val density = LocalDensity.current
    return WindowInsets.imeAnimationSource.getBottom(density) !=
        WindowInsets.imeAnimationTarget.getBottom(density)
}
