package chat.schildi.revenge.compose.destination.inbox

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LowPriority
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.lib.util.formatUnreadCount
import chat.schildi.revenge.DateTimeFormat
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.UiState
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.buildNavigationActionProvider
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.ComposeSessionScope
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.ScopedRoomSummary
import chat.schildi.revenge.plaintext.EventTextFormat
import chat.schildi.revenge.plaintext.sanitizeDirection
import chat.schildi.revenge.actions.HierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.hierarchicalKeyboardActionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.compose.components.WithContextMenu
import chat.schildi.revenge.compose.components.isAllowed
import chat.schildi.revenge.compose.components.thenIf
import chat.schildi.revenge.compose.focus.rememberFocusId
import chat.schildi.revenge.model.conversation.ConversationViewModel
import chat.schildi.revenge.model.InboxViewModel
import chat.schildi.revenge.model.PendingAction
import chat.schildi.revenge.model.PendingMessageForward
import chat.schildi.revenge.model.ScopedRoomKey
import chat.schildi.theme.scExposures
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.room.CurrentUserMembership
import io.element.android.libraries.matrix.api.room.RoomNotificationMode
import io.element.android.libraries.matrix.api.roomlist.LatestEventValue
import io.element.android.libraries.matrix.api.roomlist.RoomSummary
import io.element.android.libraries.matrix.api.timeline.item.event.getDisplayName
import io.element.android.libraries.matrix.api.user.MatrixUser
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.membership_change_invited
import shire.res.generated.resources.message_placeholder_invite
import shire.res.generated.resources.message_placeholder_invite_by
import shire.res.generated.resources.message_placeholder_invite_by_disambiguated
import shire.res.generated.resources.message_placeholder_tombstone
import kotlin.math.max

@Composable
fun InboxRow(
    viewModel: InboxViewModel,
    room: ScopedRoomSummary,
    hasDraft: Boolean,
    user: MatrixUser?,
    needsAccountDisambiguation: Boolean,
    pendingForward: PendingMessageForward?,
    unreadCountPreferences: RoomUnreadCountPreferences,
    modifier: Modifier = Modifier,
) {
    ComposeSessionScope(room.sessionId) {
        val focusId = rememberFocusId()
        val actionContext = currentActionContext()
        val unreadCounts = room.summary.unreadCounts(unreadCountPreferences)
        WithContextMenu(
            focusId = focusId,
            entries = room.contextMenu(),
        ) { openContextMenu ->
            Row(
                modifier = modifier
                    .fillMaxWidth()
                    .heightIn(min = Dimens.Inbox.rowMinHeight)
                    .keyFocusable(
                        FocusRole.LIST_ITEM,
                        focusId,
                        actionProvider = if (pendingForward != null) {
                            val validForwardTarget = pendingForward.sessionId == room.sessionId &&
                                    room.summary.info.currentUserMembership == CurrentUserMembership.JOINED &&
                                    !room.summary.info.isSpace
                            actionProvider(
                                primaryAction = if (validForwardTarget) {
                                    InteractionAction.Invoke {
                                        viewModel.forwardPendingMessages(
                                            actionContext,
                                            room.sessionId,
                                            room.summary.roomId,
                                        ) is ActionResult.Actioned
                                    }
                                } else {
                                    null
                                },
                                secondaryAction = openContextMenu,
                                copyActions = plainTextCopyAction { room.summary.info.name },
                                keyActions = inboxRowKeyboardActionProvider(
                                    viewModel,
                                    room.key,
                                    isInvite = room.summary.isInvite(),
                                ),
                            )
                        } else if (room.summary.isInvite()) {
                            val destinationStateHolder = LocalDestinationState.current
                            val canJoin = PendingAction.RoomJoin(room.summary.roomId).isAllowed()
                            actionProvider(
                                primaryAction = if (canJoin) {
                                    InteractionAction.Invoke {
                                        val result = viewModel.joinRoom(
                                            actionContext,
                                            room.sessionId,
                                            room.summary.roomId,
                                        )
                                        if (result is ActionResult.Success) {
                                            destinationStateHolder?.navigate(
                                                Destination.Conversation(room.sessionId, room.summary.roomId)
                                            )
                                        }
                                        result is ActionResult.Actioned
                                    }
                                } else {
                                    null
                                },
                                secondaryAction = openContextMenu,
                                copyActions = plainTextCopyAction { room.summary.info.name },
                                keyActions = inboxRowKeyboardActionProvider(
                                    viewModel,
                                    room.key,
                                    isInvite = true,
                                ),
                            )
                        } else {
                            buildNavigationActionProvider(
                                initialTitle = {
                                    ConversationViewModel.windowTitle(
                                        roomInfo = room.summary.info,
                                        accountUserDisplayName = user?.displayName,
                                        sessionId = room.sessionId,
                                    )
                                },
                                keyActions = inboxRowKeyboardActionProvider(
                                    viewModel,
                                    room.key,
                                    isInvite = false,
                                ),
                                secondaryAction = openContextMenu,
                                copyActions = plainTextCopyAction { room.summary.info.name },
                            ) {
                                viewModel.consumePendingShareIntoDraft(
                                    actionContext,
                                    room.sessionId,
                                    room.summary.roomId,
                                )
                                Destination.Conversation(room.sessionId, room.summary.roomId)
                            }
                        },
                    )
                    .padding(
                        horizontal = Dimens.windowPadding,
                        vertical = Dimens.Inbox.rowVerticalPadding,
                    ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box {
                    AvatarImage(
                        source = room.summary.info.avatarUrl?.let(::MediaSource)
                            ?: room.summary.info.heroes.singleOrNull()?.avatarUrl?.let(::MediaSource),
                        userId = room.summary.info.heroes.singleOrNull()?.userId
                            ?.takeIf { room.summary.info.avatarUrl == null },
                        size = Dimens.Inbox.avatar,
                        shape = CircleShape,
                        displayName = room.summary.info.name ?: "",
                    )
                    user?.avatarUrl?.takeIf { needsAccountDisambiguation }?.let { userAvatar ->
                        AvatarImage(
                            source = MediaSource(userAvatar),
                            userId = user.userId,
                            size = Dimens.Inbox.accountAvatar,
                            shape = Dimens.ownAccountAvatarShape,
                            displayName = user.displayName ?: user.userId.value,
                            modifier = Modifier.align(Alignment.BottomStart),
                        )
                    }
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = Dimens.Inbox.avatarItemPadding)
                ) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        ScNameAndTimestampRow(room.summary, unreadCounts)
                    }
                    Row(modifier = Modifier.fillMaxWidth()) {
                        ScLastMessageAndIndicatorRow(
                            scopedRoom = room,
                            hasDraft = hasDraft,
                            unreadCounts = unreadCounts,
                            dualMentionUnreadCounts = unreadCountPreferences.dualMentionUnreadCounts,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.ScNameAndTimestampRow(
    room: RoomSummary,
    unreadCounts: RoomUnreadCounts,
) {
    val displayName = room.info.privateRoomName ?: room.info.name ?: room.roomId.value
    val hasUnread = unreadCounts.hasUnread()
    Text(
        modifier = Modifier.weight(1f),
        style = MaterialTheme.typography.bodyLarge,
        text = displayName,
        color = MaterialTheme.colorScheme.onSurface,
        fontWeight = if (hasUnread) FontWeight.SemiBold else FontWeight.Medium,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )

    room.latestEventTimestamp?.let { timestamp ->
        Text(
            text = DateTimeFormat.formatTimestampAsDateOrTime(timestamp),
            style = MaterialTheme.typography.labelMedium,
            color = if (hasUnread) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = Dimens.horizontalItemPadding),
        )
    }
}

@Composable
private fun RowScope.ScLastMessageAndIndicatorRow(
    scopedRoom: ScopedRoomSummary,
    hasDraft: Boolean,
    unreadCounts: RoomUnreadCounts,
    dualMentionUnreadCounts: Boolean,
) {
    val room = scopedRoom.summary
    // Last Message
    val messagePreview = if (room.isInvite()) {
        room.info.inviter?.let { inviter ->
            val displayName = inviter.displayName
            if (displayName != null && room.info.name != displayName) {
                stringResource(Res.string.message_placeholder_invite_by_disambiguated, displayName, inviter.userId.value)
            } else {
                stringResource(Res.string.message_placeholder_invite_by, inviter.userId.value)
            }
        }?.let(::AnnotatedString) ?: AnnotatedString(stringResource(Res.string.message_placeholder_invite))
    } else if (room.info.successorRoom != null) {
        AnnotatedString(stringResource(Res.string.message_placeholder_tombstone))
    } else {
        when (val event = room.latestEvent) {
            is LatestEventValue.Local -> EventTextFormat.eventToText(
                event.content,
                scopedRoom.latestEventMessageMetadata,
                event.senderProfile,
                event.senderId
            ).let(::AnnotatedString)
            LatestEventValue.None -> null
            is LatestEventValue.Remote -> {
                val eventText = EventTextFormat.eventToText(
                    event.content,
                    scopedRoom.latestEventMessageMetadata,
                    event.senderProfile,
                    event.senderId,
                )
                AnnotatedString(eventText.sanitizeDirection())
            }
            is LatestEventValue.RoomInvite -> event.inviterId?.let { inviterId ->
                event.invitedProfile.getDisplayName()?.let {
                    stringResource(
                        Res.string.membership_change_invited,
                        inviterId,
                        it
                    )
                }?.let(::AnnotatedString)
            } ?: AnnotatedString(stringResource(Res.string.message_placeholder_invite))
        } ?: AnnotatedString("")
    }
    Row(
        modifier = Modifier
            .weight(1f)
            .padding(end = Dimens.horizontalItemPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (room.isInvite()) {
            val inviter = room.info.inviter
            inviter?.avatarUrl?.let {
                AvatarImage(
                    source = MediaSource(it),
                    size = 12.dp,
                    displayName = inviter.displayName ?: inviter.userId.value,
                    modifier = Modifier.padding(end = Dimens.horizontalItemPadding),
                )
            }
        }
        Text(
            text = messagePreview,
            color = if (unreadCounts.hasUnread()) MaterialTheme.colorScheme.onSurface
            else MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium.copy(
                textDirection = TextDirection.Content,
                fontWeight = if (unreadCounts.hasUnread()) FontWeight.Medium else FontWeight.Normal,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }

    ScRoomStateIndicators(
        room = room,
        hasDraft = hasDraft,
        modifier = Modifier.padding(end = Dimens.horizontalItemPadding),
    )

    Row(
        modifier = Modifier.heightIn(min = Dimens.Inbox.smallIcon),
        horizontalArrangement = Dimens.horizontalArrangement,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ScUnreadCounter(scopedRoom, unreadCounts, dualMentionUnreadCounts)
    }
}

@Composable
private fun ScRoomStateIndicators(
    room: RoomSummary,
    hasDraft: Boolean,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(Dimens.horizontalItemPaddingSmall),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (hasDraft) {
            Icon(
                imageVector = Icons.Default.Edit,
                contentDescription = null,
                modifier = Modifier.size(Dimens.Inbox.smallIcon),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        val notificationMode = room.info.userDefinedNotificationMode
        if (
            notificationMode == RoomNotificationMode.MENTIONS_AND_KEYWORDS_ONLY ||
            notificationMode == RoomNotificationMode.MUTE
        ) {
            Icon(
                imageVector = Icons.Default.NotificationsOff,
                contentDescription = null,
                modifier = Modifier.size(Dimens.Inbox.smallIcon),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (room.info.isLowPriority) {
            Icon(
                imageVector = Icons.Default.LowPriority,
                contentDescription = null,
                modifier = Modifier.size(Dimens.Inbox.smallIcon),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (room.info.isFavorite) {
            Icon(
                imageVector = Icons.Default.PushPin,
                contentDescription = null,
                modifier = Modifier.size(Dimens.Inbox.smallIcon),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

data class RoomUnreadCountPreferences(
    val allowSilentUnreadCount: Boolean,
    val clientGeneratedUnreadCounts: Boolean,
    val renderUnderestimates: Boolean,
    val dualMentionUnreadCounts: Boolean,
)

data class RoomUnreadCounts(
    val highlightCount: Long,
    val notificationCount: Long,
    val unreadCount: Long,
    val markedUnread: Boolean,
    val unreadUnderestimate: Boolean,
) {
    fun hasUnread() = markedUnread || notificationCount > 0L || highlightCount > 0L || unreadCount > 0L || unreadUnderestimate
    fun canMarkUnread() = !markedUnread && notificationCount == 0L && highlightCount == 0L
}

fun RoomSummary.unreadCounts(preferences: RoomUnreadCountPreferences): RoomUnreadCounts {
    return if (preferences.clientGeneratedUnreadCounts) {
        RoomUnreadCounts(
            highlightCount = info.numUnreadMentions,
            notificationCount = info.numUnreadNotifications,
            unreadCount = if (preferences.allowSilentUnreadCount) info.numUnreadMessages else 0,
            markedUnread = info.isMarkedUnread,
            unreadUnderestimate = preferences.renderUnderestimates && info.unreadCountUnderestimate,
        )
    } else {
        RoomUnreadCounts(
            highlightCount = info.highlightCount,
            notificationCount = info.notificationCount,
            unreadCount = if (preferences.allowSilentUnreadCount) info.unreadCount else 0,
            markedUnread = info.isMarkedUnread,
            unreadUnderestimate = false,
        )
    }
}

@Composable
fun RoomSummary.unreadCounts(): RoomUnreadCounts = unreadCounts(
    RoomUnreadCountPreferences(
        allowSilentUnreadCount = ScPrefs.RENDER_SILENT_UNREAD.value(),
        clientGeneratedUnreadCounts = ScPrefs.CLIENT_GENERATED_UNREAD_COUNTS.value(),
        renderUnderestimates = ScPrefs.INDICATE_UNREAD_COUNT_UNDERESTIMATES.value(),
        dualMentionUnreadCounts = ScPrefs.DUAL_MENTION_UNREAD_COUNTS.value(),
    )
)

@Composable
private fun ScUnreadCounter(
    scopedRoom: ScopedRoomSummary,
    unreadCounts: RoomUnreadCounts,
    dualMentionUnreadCounts: Boolean,
) {
    val room = scopedRoom.summary
    val (highlightCount, notificationCount, unreadCount, markedUnread, underestimate) = unreadCounts
    val count: String
    val badgeColor: Color
    var outlinedBadge = false
    when {
        room.isInvite() -> {
            if (UiState.appStateStore.isInviteSeenFlow(scopedRoom.key).collectAsState(false).value) {
                return
            }
            count = "!"
            badgeColor = MaterialTheme.scExposures.notificationBadgeColor
        }
        dualMentionUnreadCounts && highlightCount > 0 && (notificationCount > highlightCount || unreadCount > highlightCount) -> {
            val fullUnreadToUse = max(unreadCount, notificationCount)
            count = "${formatUnreadCount(highlightCount)}/${formatUnreadCount(fullUnreadToUse, underestimate)}"
            badgeColor = MaterialTheme.scExposures.mentionBadgeColor
        }
        notificationCount > 0 -> {
            count = formatUnreadCount(notificationCount, underestimate)
            badgeColor = if (highlightCount > 0)
                MaterialTheme.scExposures.mentionBadgeColor
            else
                MaterialTheme.scExposures.notificationBadgeColor
        }
        highlightCount > 0 -> {
            count = formatUnreadCount(highlightCount, underestimate)
            badgeColor = MaterialTheme.scExposures.mentionBadgeColor
        }
        markedUnread -> {
            count = "!"
            badgeColor = MaterialTheme.scExposures.notificationBadgeColor
            outlinedBadge = true
        }
        unreadCount > 0 -> {
            count = formatUnreadCount(unreadCount, underestimate)
            badgeColor = MaterialTheme.scExposures.unreadBadgeColor
        }
        underestimate -> {
            count = "?"
            badgeColor = MaterialTheme.scExposures.unreadBadgeColor
        }
        else -> {
            // No badge to show
            return
        }
    }
    Box (
        modifier = Modifier
            .let {
                if (outlinedBadge)
                    it.border(2.dp, badgeColor, RoundedCornerShape(30.dp))
                else
                    it.background(badgeColor, RoundedCornerShape(30.dp))
            }
            .sizeIn(
                minWidth = Dimens.Inbox.unreadBadgeMinSize,
                minHeight = Dimens.Inbox.unreadBadgeMinSize,
            )
    ) {
        Text(
            text = count,
            color = if (outlinedBadge) badgeColor else MaterialTheme.scExposures.colorOnAccent,
            style = MaterialTheme.typography.labelSmall.let {
                if (outlinedBadge) it.copy(fontWeight = FontWeight.Bold)
                else it.copy(fontWeight = FontWeight.SemiBold)
            },
            maxLines = 1,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 4.dp)
        )
    }
}

fun RoomSummary.isInvite() = info.currentUserMembership == CurrentUserMembership.INVITED

@Composable
private fun inboxRowKeyboardActionProvider(
    viewModel: InboxViewModel,
    room: ScopedRoomKey,
    isInvite: Boolean,
): HierarchicalKeyboardActionProvider {
    val ownHandler = remember(viewModel, room, isInvite) {
        viewModel.getKeyboardActionProviderForRoom(room.sessionId, room.roomId, isInvite)
    }
    return ownHandler.hierarchicalKeyboardActionProvider()
}
