package chat.schildi.revenge.compose.destination

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The IME inset is animated while the keyboard hides. A binary choice between IME and
 * navigation-bar padding adds the *entire* navigation inset on the final keyboard frame,
 * jolting the composer (and the timeline above it). Compensate only for the portion of
 * the navigation bar not already covered by the current, animated IME inset.
 */
internal fun imeAwareBottomPadding(navigationBarBottom: Dp, imeBottom: Dp): Dp =
    12.dp + (navigationBarBottom - imeBottom).coerceAtLeast(0.dp)
