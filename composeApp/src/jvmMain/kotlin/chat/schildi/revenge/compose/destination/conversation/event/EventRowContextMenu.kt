package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddReaction
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.input.key.Key
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.compose.components.ContextMenuActionEntry
import chat.schildi.revenge.compose.components.ContextMenuActionRowEntry
import chat.schildi.revenge.compose.components.ContextMenuCallbackEntry
import chat.schildi.revenge.compose.components.ContextMenuDecoration
import chat.schildi.revenge.compose.components.ContextMenuEntry
import chat.schildi.revenge.compose.components.LocalSessionId
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.model.conversation.ConversationPermissions
import chat.schildi.resources.toStringHolder
import io.element.android.libraries.matrix.api.timeline.item.event.EventTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.MessageContent
import io.element.android.libraries.matrix.api.timeline.item.event.PollContent
import io.element.android.libraries.matrix.api.timeline.item.event.StickerContent
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toPersistentList
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_deselect_message
import shire.res.generated.resources.action_select_message
import shire.res.generated.resources.action_redact
import shire.res.generated.resources.action_react

/**
 * Kite's deliberately minimal long-press surface: quick emoji reactions,
 * then Select, Copy, Delete. Delete remains visible even in rooms where
 * redaction is unavailable, but stays disabled until Matrix permits it.
 */
@Composable
fun EventTimelineItem.contextMenu(
    permissions: ConversationPermissions?,
    isSelected: Boolean = false,
    onToggleSelection: (() -> Unit)? = null,
): ImmutableList<ContextMenuEntry> {
    val isMessage = content is MessageContent
    val isUserMessage = isMessage || content is StickerContent || content is PollContent
    if (!isUserMessage) return persistentListOf()

    val canReact = eventId != null && permissions?.canSendReactions == true
    val canRedact = canDeleteMessage(
        eventHasId = eventId != null || transactionId != null,
        isOwn = isOwn,
        permissions = permissions,
    )
    val ownUserId = LocalSessionId.current
    val reactionsRow = ContextMenuActionRowEntry(
        title = "Quick reactions".toStringHolder(),
        showTitle = false,
        actions = (
            listOf("❤️", "👍", "😂", "😮", "😢").map { reaction ->
                val selected = reactions.any { eventReaction ->
                    eventReaction.key == reaction &&
                        eventReaction.senders.any { it.senderId == ownUserId }
                }
                ContextMenuActionEntry(
                    title = "React $reaction".toStringHolder(),
                    action = Action.Event.ToggleReactionKey,
                    actionArgs = persistentListOf(reaction),
                    decoration = ContextMenuDecoration.Toggle(selected),
                    autoCloseMenu = true,
                    dismissParentsOnAutoClose = true,
                    compactLabel = reaction,
                )
            } + ContextMenuActionEntry(
                title = Res.string.action_react.toStringHolder(),
                icon = rememberVectorPainter(Icons.Default.AddReaction),
                action = Action.Event.ComposeReaction,
                autoCloseMenu = true,
                dismissParentsOnAutoClose = true,
            )
        ).toPersistentList(),
    ).takeIf { canReact }

    return listOfNotNull<ContextMenuEntry>(
        reactionsRow,
        ContextMenuCallbackEntry(
            title = if (isSelected) {
                Res.string.action_deselect_message.toStringHolder()
            } else {
                Res.string.action_select_message.toStringHolder()
            },
            icon = rememberVectorPainter(
                if (isSelected) Icons.Default.CheckCircle else Icons.Outlined.RadioButtonUnchecked
            ),
            action = {
                onToggleSelection?.invoke()
                ActionResult.Success()
            },
        ).takeIf { onToggleSelection != null },
        ContextMenuActionEntry(
            "Copy".toStringHolder(),
            rememberVectorPainter(Icons.Default.ContentCopy),
            Action.Event.CopyContent,
            keyboardShortcut = Key.Y,
        ).takeIf { isMessage },
        ContextMenuActionEntry(
            Res.string.action_redact.toStringHolder(),
            rememberVectorPainter(Icons.Default.Delete),
            Action.Event.Redact,
            keyboardShortcut = Key.D,
            enabled = canRedact,
            critical = true,
        ),
    ).toPersistentList()
}

/** Kept separate from menu presentation so permission-specific visibility is testable. */
internal fun canDeleteMessage(
    eventHasId: Boolean,
    isOwn: Boolean,
    permissions: ConversationPermissions?,
): Boolean = eventHasId && if (isOwn) {
    permissions?.canRedactOwn ?: true
} else {
    permissions?.canRedactOther ?: false
}
