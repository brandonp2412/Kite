package chat.schildi.revenge.compose.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Destination
import chat.schildi.revenge.DestinationStateHolder
import chat.schildi.revenge.NavigationPreference
import chat.schildi.revenge.actions.AbstractAppMessage
import chat.schildi.revenge.actions.AppMessage
import chat.schildi.revenge.actions.ConfirmActionAppMessage
import chat.schildi.revenge.actions.InteractionAction.Invoke
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.actions.VerificationRequestAppMessage
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.toCopyAction
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.model.verification.RevengeDeviceVerificationProvider
import kotlinx.collections.immutable.ImmutableList
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_dismiss
import shire.res.generated.resources.action_view
import shire.res.generated.resources.verification_failed

@Composable
fun AppMessages(
    messages: ImmutableList<AbstractAppMessage>,
    destinationHolder: DestinationStateHolder,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(
            items = messages,
            key = { it.uniqueId ?: it.timestamp },
            contentType = {
                when (it) {
                    is ConfirmActionAppMessage -> "confirm"
                    is VerificationRequestAppMessage -> "verification"
                    is AppMessage -> if (it.isError) "error" else "message"
                }
            },
        ) { message ->
            if (message.dismissedTimestamp == null) {
                AppMessageCard(message, destinationHolder)
            }
        }
    }
}

@Composable
private fun AppMessageCard(
    message: AbstractAppMessage,
    destinationHolder: DestinationStateHolder,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    val messageText = message.message.render()
    val isError = (message as? AppMessage)?.isError == true

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        shape = RoundedCornerShape(20.dp),
        color = if (isError) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerHigh
        },
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                messageText,
                color = if (isError) {
                    MaterialTheme.colorScheme.onErrorContainer
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .fillMaxWidth()
                    .keyFocusable(
                        actionProvider = actionProvider(
                            copyActions = messageText.toCopyAction(),
                        ),
                    ),
            )
            when (message) {
                is AppMessage -> Unit
                is ConfirmActionAppMessage -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(
                            onClick = { keyHandler.dismissMessage(message.uniqueId) },
                            modifier = Modifier.keyFocusable(
                                actionProvider = actionProvider(
                                    primaryAction = Invoke {
                                        keyHandler.dismissMessage(message.uniqueId)
                                        true
                                    },
                                    copyActions = messageText.toCopyAction(),
                                ),
                            ),
                        ) {
                            Text(message.cancelText.render())
                        }
                        Button(
                            onClick = message.action,
                            modifier = Modifier
                                .heightIn(min = 40.dp)
                                .keyFocusable(
                                    actionProvider = actionProvider(
                                        primaryAction = Invoke {
                                            message.action()
                                            true
                                        },
                                        copyActions = messageText.toCopyAction(),
                                    ),
                                ),
                            shape = RoundedCornerShape(20.dp),
                        ) {
                            Text(message.confirmText.render())
                        }
                    }
                }
                is VerificationRequestAppMessage -> {
                    fun viewRequest() {
                        if (RevengeDeviceVerificationProvider.setActiveRequest(message.request)) {
                            destinationHolder.navigate(
                                Destination.VerificationRequest(message.request.sessionId),
                                NavigationPreference.NEW_WINDOW_SAME_TASK,
                            )
                            keyHandler.dismissMessage(message.uniqueId)
                        } else {
                            keyHandler.publishMessage(
                                AppMessage(
                                    Res.string.verification_failed.toStringHolder(),
                                    uniqueId = message.uniqueId,
                                    isError = true,
                                )
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(
                            onClick = { keyHandler.dismissMessage(message.uniqueId) },
                            modifier = Modifier.keyFocusable(
                                actionProvider = actionProvider(
                                    primaryAction = Invoke {
                                        keyHandler.dismissMessage(message.uniqueId)
                                        true
                                    },
                                    copyActions = messageText.toCopyAction(),
                                ),
                            ),
                        ) {
                            Text(stringResource(Res.string.action_dismiss))
                        }
                        Button(
                            onClick = ::viewRequest,
                            colors = ButtonDefaults.buttonColors(),
                            modifier = Modifier
                                .heightIn(min = 40.dp)
                                .keyFocusable(
                                    actionProvider = actionProvider(
                                        primaryAction = Invoke {
                                            viewRequest()
                                            true
                                        },
                                        copyActions = messageText.toCopyAction(),
                                    ),
                                ),
                            shape = RoundedCornerShape(20.dp),
                        ) {
                            Text(stringResource(Res.string.action_view))
                        }
                    }
                }
            }
        }
    }
}
