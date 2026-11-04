package chat.schildi.revenge.compose.composer

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.model.ComposerViewModel

@Composable
actual fun Modifier.keyboardImageContentReceiver(
    viewModel: ComposerViewModel,
    context: ActionContext,
    enabled: Boolean,
): Modifier = this
