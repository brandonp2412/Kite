package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.DateTimeFormat
import chat.schildi.revenge.compose.components.KiteModalBottomSheet
import chat.schildi.revenge.toPrettyJson
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.LocalEventSendState
import io.element.android.libraries.matrix.api.timeline.item.event.getDisplayName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_message_info
import shire.res.generated.resources.message_info_sender
import shire.res.generated.resources.message_info_source
import shire.res.generated.resources.message_info_status
import shire.res.generated.resources.message_info_time

@Composable
fun MessageInfoSheet(
    event: EventTimelineItem,
    onDismiss: () -> Unit,
) {
    val source by produceState(initialValue = "", event) {
        value = withContext(Dispatchers.Default) {
            event.timelineItemDebugInfoProvider().originalJson?.toPrettyJson().orEmpty()
        }
    }
    val senderName = event.senderProfile.getDisplayName()
    val status = remember(event.eventId, event.localSendState) {
        when (event.localSendState) {
            null -> if (event.eventId != null) "sent" else "pending"
            is LocalEventSendState.Sending -> "sending"
            is LocalEventSendState.Failed -> "failed"
            is LocalEventSendState.Sent -> "sent"
        }
    }

    KiteModalBottomSheet(
        onDismissRequest = onDismiss,
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(
                text = stringResource(Res.string.action_message_info),
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                style = MaterialTheme.typography.titleLarge,
            )
            InfoItem(
                label = stringResource(Res.string.message_info_sender),
                value = buildString {
                    senderName?.let {
                        append(it)
                        append(" [")
                    }
                    append(event.sender.value)
                    if (senderName != null) append("]")
                },
            )
            InfoItem(
                label = stringResource(Res.string.message_info_time),
                value = DateTimeFormat.formatTimeOrDateTime(event.timestamp),
            )
            InfoItem(
                label = stringResource(Res.string.message_info_status),
                value = status,
            )
            if (source.isNotBlank()) {
                Text(
                    text = stringResource(Res.string.message_info_source),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.titleSmall,
                )
                Surface(
                    modifier = Modifier.padding(horizontal = 12.dp).fillMaxWidth(),
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.colorScheme.surfaceContainer,
                ) {
                    SelectionContainer {
                        Text(
                            text = source,
                            modifier = Modifier
                                .horizontalScroll(rememberScrollState())
                                .padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

@Composable
private fun InfoItem(label: String, value: String) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 2.dp),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectionContainer {
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}
