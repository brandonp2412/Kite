package chat.schildi.revenge.compose.composer

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.model.ComposerViewModel

/** Accept images committed by keyboards on Android; desktop input is unchanged. */
@Composable
expect fun Modifier.keyboardImageContentReceiver(
    viewModel: ComposerViewModel,
    context: ActionContext,
    enabled: Boolean,
): Modifier
