package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.MessageForward
import chat.schildi.revenge.model.PendingMessageForward
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_close
import shire.res.generated.resources.forward_choose_room

@Composable
fun MessageForwardNoticeCard(
    forward: PendingMessageForward,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainerHighest, Dimens.Inbox.noticeShape)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Dimens.horizontalArrangement,
    ) {
        Icon(
            Icons.AutoMirrored.Default.Forward,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = stringResource(Res.string.forward_choose_room, forward.eventIds.size),
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        IconButton(
            onClick = { MessageForward.clear(forward) },
            modifier = Modifier
                .size(40.dp)
                .keyFocusable(
                    FocusRole.AUX_ITEM,
                    actionProvider = actionProvider(
                        primaryAction = InteractionAction.Invoke {
                            MessageForward.clear(forward)
                            true
                        },
                    ),
                ),
        ) {
            Icon(
                Icons.Default.Clear,
                stringResource(Res.string.action_close),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
