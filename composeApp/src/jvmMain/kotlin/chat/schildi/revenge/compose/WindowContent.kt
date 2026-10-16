package chat.schildi.revenge.compose

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Button
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Anim
import chat.schildi.revenge.DestinationStateHolder
import chat.schildi.revenge.actions.KeyboardActionMode
import chat.schildi.revenge.actions.ConfirmActionAppMessage
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.compose.command.CommandBar
import chat.schildi.revenge.compose.components.AppMessages
import chat.schildi.revenge.compose.components.thenIf
import chat.schildi.revenge.compose.destination.inbox.LocalInboxListState
import chat.schildi.revenge.compose.focus.windowFocusContainer
import chat.schildi.revenge.compose.search.SearchBar
import chat.schildi.revenge.compose.util.rememberInvalidating
import chat.schildi.theme.ScTheme
import kotlinx.collections.immutable.toPersistentList
import chat.schildi.theme.scExposures

@Composable
fun WindowContent(
    destinationHolder: DestinationStateHolder,
    modifier: Modifier = Modifier,
) {
    ScTheme {
        val retainedInboxListState = rememberLazyListState()
        val backgroundAlpha = if (MaterialTheme.scExposures.isDarkTheme) {
            ScPrefs.BACKGROUND_ALPHA_DARK.value()
        } else {
            ScPrefs.BACKGROUND_ALPHA_LIGHT.value()
        }

        // Global window bottom content (app messages, command bar, search)
        val keyboardActionHandler = LocalKeyboardActionHandler.current
        val publishedMessages = keyboardActionHandler.messageBoard.collectAsState().value
        // Confirmation is a real overlay, never a bottom message that reduces the
        // destination viewport or toggles the window's safe-area padding.
        val confirmation = publishedMessages.lastOrNull {
            it is ConfirmActionAppMessage && it.dismissedTimestamp == null
        } as? ConfirmActionAppMessage
        val bottomMessages = publishedMessages.filterNot { it is ConfirmActionAppMessage }
            .toPersistentList()
        val showSearchBar = ScPrefs.MINIMAL_MODE.value() &&
                keyboardActionHandler.needsKeyboardSearchBar(null).collectAsState().value
        val showCommandBar = keyboardActionHandler.mode.collectAsState().value is KeyboardActionMode.Command
        val showsBottomContent = showSearchBar || showCommandBar ||
                bottomMessages.any { it.dismissedTimestamp == null }

        Box(
            modifier
                .background(MaterialTheme.colorScheme.surface.copy(alpha = backgroundAlpha))
                .thenIf(showsBottomContent) {
                    // If we're showing bottom bar content, we need to consume safe insets here already,
                    // otherwise we can delegate to destination content to allow edge-to-edge rendering
                    safeDrawingPadding()
                }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .windowFocusContainer(),
            ) {
                // Actual destination content

                Box(Modifier.fillMaxWidth().weight(1f)) {
                    CompositionLocalProvider(LocalInboxListState provides retainedInboxListState) {
                        DestinationContent(destinationHolder, Modifier.fillMaxSize())
                    }
                }

                // Conditional global bottom content

                Column(
                    //if (showsBottomContent) Modifier.navigationBarsPadding() else Modifier,
                ) {
                    rememberInvalidating(
                        500L.takeIf { publishedMessages.any { it.dismissedTimestamp == null && it.autoDismissDuration != null } },
                        publishedMessages
                    ) {
                        keyboardActionHandler.cleanUpMessageBoard()
                    }
                    AppMessages(bottomMessages, destinationHolder)

                    // Search bar
                    AnimatedVisibility(
                        visible = showSearchBar,
                        enter = slideInVertically(tween(Anim.DURATION)) { it } +
                                expandVertically(tween(Anim.DURATION), expandFrom = Alignment.Bottom),
                        exit = slideOutVertically(tween(Anim.DURATION)) { it } +
                                shrinkVertically(tween(Anim.DURATION), shrinkTowards = Alignment.Bottom),
                    ) {
                        SearchBar(null, null)
                    }

                    // Command bar
                    AnimatedVisibility(
                        visible = showCommandBar,
                        enter = slideInVertically(tween(Anim.DURATION)) { it } +
                                expandVertically(tween(Anim.DURATION), expandFrom = Alignment.Bottom),
                        exit = slideOutVertically(tween(Anim.DURATION)) { it } +
                                shrinkVertically(tween(Anim.DURATION), shrinkTowards = Alignment.Bottom),
                    ) {
                        CommandBar()
                    }
                }
            }
            if (confirmation != null) {
                AlertDialog(
                    onDismissRequest = { keyboardActionHandler.dismissMessage(confirmation.uniqueId) },
                    title = { Text(confirmation.message.render()) },
                    confirmButton = {
                        Button(onClick = confirmation.action) {
                            Text(confirmation.confirmText.render())
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = {
                            keyboardActionHandler.dismissMessage(confirmation.uniqueId)
                        }) {
                            Text(confirmation.cancelText.render())
                        }
                    },
                )
            }
            // Do not paint Revenge's global frame-drop spinner over Kite. It can flash
            // during ordinary navigation and makes otherwise-stable screens look like they
            // are loading. Performance remains measured with Android frame tooling instead.
        }
    }
}
