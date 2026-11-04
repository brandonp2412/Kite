package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.content.MediaType
import androidx.compose.foundation.content.consume
import androidx.compose.foundation.content.contentReceiver
import androidx.compose.foundation.content.hasMediaType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import chat.schildi.resources.HardcodedStringHolder
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.actions.AppMessage
import chat.schildi.revenge.model.ComposerViewModel
import chat.schildi.revenge.util.filepicker.FilePicker
import co.touchlab.kermit.Logger
import kotlinx.coroutines.launch

private val log = Logger.withTag("KeyboardImageContentReceiver")

@OptIn(ExperimentalFoundationApi::class)
@Composable
actual fun Modifier.keyboardImageContentReceiver(
    viewModel: ComposerViewModel,
    context: ActionContext,
    enabled: Boolean,
): Modifier {
    if (!enabled) return this
    val scope = rememberCoroutineScope()
    val currentViewModel by rememberUpdatedState(viewModel)
    val currentContext by rememberUpdatedState(context)

    return contentReceiver { content ->
        if (!content.hasMediaType(MediaType.Image)) {
            return@contentReceiver content
        }

        // Gboard sends GIFs as content:// items, not text. Consume only one image:
        // the composer supports one attachment, and other clipboard content must
        // remain available to the normal text field.
        var accepted = false
        content.consume { item ->
            val uri = item.uri ?: return@consume false
            if (accepted) return@consume false
            accepted = true
            scope.launch {
                val result = FilePicker.copyUriToCache(uri)
                result.onSuccess { file ->
                    val queued = currentViewModel.attachFile(
                        currentContext,
                        file.file.toURI().toString(),
                        file.mimeType,
                        file.isAppOwned,
                    )
                    if (!queued) {
                        file.file.parentFile?.deleteRecursively()
                        currentContext.publishMessage(
                            AppMessage(HardcodedStringHolder("Could not attach image from keyboard"), isError = true)
                        )
                    }
                }.onFailure { error ->
                    log.w("Failed to import keyboard image", error)
                    currentContext.publishMessage(
                        AppMessage(HardcodedStringHolder("Could not read image from keyboard"), isError = true)
                    )
                }
            }
            true
        }
    }
}
