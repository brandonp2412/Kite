package chat.schildi.revenge.notification

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import chat.schildi.revenge.Destination
import chat.schildi.revenge.MainActivity
import chat.schildi.revenge.RevengeAppGraph
import chat.schildi.revenge.RevengeApplication
import chat.schildi.revenge.actions.AppMessage
import chat.schildi.revenge.actions.fileProviderAuthority
import chat.schildi.revenge.compose.R
import chat.schildi.revenge.media.MediaDownloadRepo
import chat.schildi.revenge.model.ScopedRawRoomId
import chat.schildi.revenge.plaintext.AttachmentFormatMode
import chat.schildi.revenge.plaintext.NotificationEventTextFormat
import chat.schildi.revenge.serializedToString
import chat.schildi.revenge.util.MimeUtil
import co.touchlab.kermit.Logger
import coil3.BitmapImage
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.size.Precision
import io.element.android.libraries.androidutils.hash.hash
import io.element.android.libraries.matrix.api.core.RoomId
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.notification.NotificationContent
import io.element.android.libraries.matrix.api.notification.NotificationData
import io.element.android.libraries.matrix.api.room.CreateTimelineParams
import io.element.android.libraries.matrix.api.timeline.item.event.ImageLikeMessageType
import io.element.android.libraries.matrix.api.timeline.item.event.MessageTypeWithAttachment
import io.element.android.libraries.matrix.api.timeline.item.event.TextMessageType
import io.element.android.libraries.matrix.api.timeline.ReceiptType
import io.element.android.libraries.matrix.api.timeline.item.event.VideoMessageType
import io.element.android.libraries.matrix.ui.media.MediaRequestData
import io.element.android.libraries.matrix.ui.media.animated.allowAnimatedImageDecoding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.withTimeoutOrNull
import org.jetbrains.compose.resources.getString
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_mark_as_read
import shire.res.generated.resources.action_reply
import shire.res.generated.resources.notification_channel_app_notices
import shire.res.generated.resources.notification_channel_group_chat_messages
import java.util.UUID
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.measureTimedValue

// Category matching the <share-target> declaration in res/xml/shortcuts.xml
internal const val DIRECT_SHARE_TARGET_CATEGORY = "chat.schildi.revenge.category.DIRECT_SHARE"

object AndroidNotifier {

    private const val CHAT_MESSAGES_CHANNEL_ID_PREFIX = "session_"
    private const val CHAT_MESSAGES_CHANNEL_ID_GROUP = "chat_messages"
    private const val APP_NOTICES_CHANNEL_ID = "app_notices"
    private const val CONVERSATION_SHORTCUT_PREFIX = "room_"
    private const val MEDIA_TIMEOUT = 10_000L
    private const val LARGE_ICON_SIZE = 256

    private const val EXTRA_SESSION_ID = "session_id"
    private const val EXTRA_ROOM_ID = "room_id"
    private const val EXTRA_EVENT_IDS = "event_ids"
    private const val EXTRA_PREVIEW_EVENT_ID = "notification_preview_event_id"
    private const val EXTRA_PREVIEW_TEXT = "notification_preview_text"
    private const val EXTRA_PREVIEW_TOKEN = "notification_preview_token"
    private const val EXTRA_PREVIEW_POSTED_AT = "notification_preview_posted_at"
    private const val PREVIEW_TOKEN_PREFS = "notification_open_tokens"
    private const val PREVIEW_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000
    private const val EXTRA_COPY_CODE = "copy_code"
    private const val KEY_TEXT_REPLY = "text_reply"

    private const val ACTION_NOTIFICATION_REPLY = "chat.schildi.revenge.notification.REPLY"
    private const val ACTION_NOTIFICATION_MARK_READ = "chat.schildi.revenge.notification.MARK_READ"
    private const val ACTION_NOTIFICATION_COPY_CODE = "chat.schildi.revenge.notification.COPY_CODE"

    private val log = Logger.withTag("AndroidNotifier")

    // Same as UiState, but we want the notification path to not rely on UiState to save resources
    val knownSessionIds: Flow<List<SessionId>> = RevengeAppGraph.sessionStore.sessionsFlow().map {
        it.map { SessionId(it.userId) }
    }.distinctUntilChanged()

    fun messageChannelId(sessionId: SessionId) = CHAT_MESSAGES_CHANNEL_ID_PREFIX + sessionId.value

    suspend fun notify(
        id: NotificationId,
        title: String,
        message: String,
        largeImage: MediaSource?,
        context: Context = RevengeApplication.instance,
    ) {
        val notificationManager = NotificationManagerCompat.from(context)
        if (!context.canPostNotifications() || !notificationManager.areNotificationsEnabled()) return

        val notificationId = id.androidNotificationId()
        val largeIcon = largeImage?.let { loadMediaBitmap(id.sessionId, it) }

        val channelId = when (id) {
            is NotificationId.VerificationRequest -> {
                // While we don't have push for these, and don't auto-dismiss either,
                // no huge benefit in showing these
                return
            }
            is NotificationId.Event -> messageChannelId(id.sessionId)
            // is NotificationId.Room -> // What is this for without event ID?
            else -> APP_NOTICES_CHANNEL_ID
        }

        val notification = NotificationCompat.Builder(context, channelId)
            .setContentIntent(id.createPendingIntent(context, notificationId))
            .setSmallIcon(if (id is NotificationId.Event) R.drawable.ic_notification_message else R.drawable.ic_notification)
            .setLargeIcon(largeIcon)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()

        try {
            notificationManager.notify(notificationId, notification)
        } catch (failure: SecurityException) {
            log.w("Notification permission was revoked before the notification could be posted", failure)
        }
    }

    suspend fun notifyMessage(
        id: NotificationId.Event,
        data: NotificationData,
        context: Context = RevengeApplication.instance,
    ) {
        val notificationManager = NotificationManagerCompat.from(context)
        if (!context.canPostNotifications() || !notificationManager.areNotificationsEnabled()) return

        val notificationId = id.androidNotificationId()

        val existingNotification = runCatching {
            notificationManager.activeNotifications
                .firstOrNull { it.id == notificationId }
                ?.notification
        }.onFailure {
            log.w("Failed to inspect active notifications", it)
        }.getOrNull()

        val roomAvatar = data.roomAvatarUrl?.let { loadMediaBitmap(id.sessionId, MediaSource(it))?.circularAvatar() }
        val senderAvatar = data.senderAvatarUrl?.let { loadMediaBitmap(id.sessionId, MediaSource(it))?.circularAvatar() }

        // TODO look up
        val ownUser = Person.Builder()
            .setKey(id.sessionId.value)
            .setName(id.sessionId.value)
            .build()

        val senderName = data.getDisambiguatedDisplayName(data.senderId)
        val sender = Person.Builder()
            .setKey(data.senderId.value)
            .setName(senderName)
            .setIcon(senderAvatar?.let(IconCompat::createWithBitmap))
            .build()

        val previousEventIds =
            existingNotification?.extras?.getStringArrayList(EXTRA_EVENT_IDS)?.toList()
                ?: emptyList()
        val extractedStyle = existingNotification?.let {
            NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it)
        }
        val historyIsAligned = existingNotification == null ||
                extractedStyle != null && previousEventIds.size == extractedStyle.messages.size
        if (!historyIsAligned) {
            log.w {
                "Discarding misaligned notification history for $id: " +
                        "${extractedStyle?.messages?.size ?: 0} messages, ${previousEventIds.size} tracked event IDs"
            }
        }
        val messagingStyle = if (historyIsAligned) {
            extractedStyle ?: NotificationCompat.MessagingStyle(ownUser)
        } else {
            NotificationCompat.MessagingStyle(ownUser)
        }
        // Bridge rooms can be one-to-one even when Matrix does not mark them as direct.
        val isGroupConversation = isGroupNotification(
            isDirect = data.isDirect,
            isDm = data.isDm,
            roomName = data.roomDisplayName,
            senderName = senderName,
            senderId = data.senderId.value,
            previousSenderIds = messagingStyle.messages.map { it.person?.key },
        )
        messagingStyle
            .setConversationTitle(data.roomDisplayName.takeIf { isGroupConversation })
            .setGroupConversation(isGroupConversation)
        val previousMessageCount = messagingStyle.messages.size
        val alignedPreviousEventIds = if (historyIsAligned) previousEventIds else emptyList()

        val plainMessageText = NotificationEventTextFormat.notificationToText(
            data,
            attachmentMode = AttachmentFormatMode.Auto,
            prefixSenderInGroupChats = isGroupConversation,
        )

        suspend fun textMessage(
            attachmentMode: AttachmentFormatMode = AttachmentFormatMode.Auto
        ): NotificationCompat.MessagingStyle.Message {
            val text = NotificationEventTextFormat.notificationToText(
                data,
                attachmentMode = attachmentMode,
                prefixSenderInGroupChats = false,
            )
            return NotificationCompat.MessagingStyle.Message(text, data.timestamp, sender)
        }

        when (val content = data.content) {
            is NotificationContent.MessageLike.RoomMessage -> {
                when (val messageType = content.messageType) {
                    is ImageLikeMessageType -> {
                        // Thumbnail
                        val messageMedia = messageType.info?.thumbnailSource?.let { thumbnailSource ->
                            loadNotificationMediaUri(
                                context,
                                data,
                                thumbnailSource,
                                messageType.info?.thumbnailInfo?.mimetype,
                                messageType.filename,
                            )
                        } ?: loadNotificationMediaUri(
                            context,
                            data,
                            messageType.source,
                            messageType.info?.mimetype,
                            messageType.filename,
                        )

                        // Media message
                        messagingStyle.addMessage(
                            textMessage(AttachmentFormatMode.FilenameOrFallback).apply {
                                messageMedia?.let { (uri, mimeType) ->
                                    setData(mimeType, uri)
                                }
                            }
                        )

                        // Caption message needs to be separate to be rendered
                        if (!messageType.caption.isNullOrBlank()) {
                            messagingStyle.addMessage(textMessage(AttachmentFormatMode.Caption))
                        }
                    }
                    is VideoMessageType -> {
                        // Thumbnail
                        val messageMedia = messageType.info?.thumbnailSource?.let { thumbnailSource ->
                            loadNotificationMediaUri(
                                context,
                                data,
                                thumbnailSource,
                                messageType.info?.thumbnailInfo?.mimetype,
                                messageType.filename,
                            )
                        }

                        // Media message
                        messagingStyle.addMessage(
                            textMessage(AttachmentFormatMode.FilenameOrFallback).apply {
                                messageMedia?.let { (uri, mimeType) ->
                                    setData(mimeType, uri)
                                }
                            }
                        )

                        // Caption message needs to be separate to be rendered
                        if (!messageType.caption.isNullOrBlank()) {
                            messagingStyle.addMessage(textMessage(AttachmentFormatMode.Caption))
                        }
                    }
                    is MessageTypeWithAttachment -> {
                        // To make it clear this is an attachment, render both caption (if exists) and filename/fallback
                        if (messageType.caption.isNullOrBlank()) {
                            messagingStyle.addMessage(textMessage())
                        } else {
                            messagingStyle.addMessage(textMessage(AttachmentFormatMode.FilenameOrFallback))
                            messagingStyle.addMessage(textMessage(AttachmentFormatMode.Caption))
                        }
                    }
                    else -> messagingStyle.addMessage(textMessage())
                }
            }
            else -> messagingStyle.addMessage(textMessage())
        }

        // Track one event ID per rendered notification message, including the two
        // messages produced by media-with-caption events. Keeping these lists aligned
        // lets later redaction remove every rendered part of the Matrix event.
        val addedMessageCount = messagingStyle.messages.size - previousMessageCount
        val eventIds = alignedPreviousEventIds +
                List(addedMessageCount) { data.eventId.value }

        val shortcut = createConversationShortcut(
            sessionId = id.sessionId,
            roomId = id.roomId,
            label = data.roomDisplayName ?: senderName.takeUnless { isGroupConversation },
            icon = roomAvatar ?: senderAvatar?.takeUnless { isGroupConversation },
            person = sender.takeUnless { isGroupConversation },
            context = context,
        )
        shortcut?.let {
            runCatching {
                ShortcutManagerCompat.pushDynamicShortcut(context, it)
            }.onSuccess { published ->
                if (!published) {
                    log.w { "Conversation shortcut ${it.id} was rejected" }
                }
            }.onFailure { failure ->
                log.w("Failed to publish conversation shortcut ${it.id}", failure)
            }
        }

        val builder = existingNotification?.let {
            NotificationCompat.Builder(context, it)
        } ?: NotificationCompat.Builder(context, messageChannelId(id.sessionId))
        val openPreview = (data.content as? NotificationContent.MessageLike.RoomMessage)
            ?.takeIf { it.messageType is TextMessageType }
            ?.let {
                NotificationOpenPreview(
                    sessionId = id.sessionId.value,
                    roomId = id.roomId.value,
                    eventId = data.eventId.value,
                    text = plainMessageText.take(4096),
                )
            }
        // Update on every event: grouped notifications otherwise keep the first event's intent.
        builder.setContentIntent(id.createPendingIntent(context, notificationId, openPreview))

        builder.clearActions()
        val supportsRoomActions = data.content is NotificationContent.MessageLike
        val supportsQuickReply = when (data.content) {
            is NotificationContent.MessageLike.RoomMessage,
            NotificationContent.MessageLike.Sticker,
            is NotificationContent.MessageLike.Poll -> true
            else -> false
        }
        if (supportsQuickReply) {
            builder.addAction(
                buildReplyAction(
                    context = context,
                    notificationId = notificationId,
                    sessionId = id.sessionId,
                    roomId = id.roomId,
                    label = getString(Res.string.action_reply),
                )
            )
        }
        if (supportsRoomActions) {
            builder.addAction(
                buildMarkReadAction(
                    context = context,
                    notificationId = notificationId,
                    sessionId = id.sessionId,
                    roomId = id.roomId,
                    label = getString(Res.string.action_mark_as_read),
                )
            )
        }
        if (supportsQuickReply) {
            extractNotificationVerificationCode(plainMessageText)?.let { code ->
                builder.addAction(
                    buildCopyCodeAction(
                        context = context,
                        notificationId = notificationId,
                        code = code,
                    )
                )
            }
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_notification_message)
            .setContentTitle(data.roomDisplayName.takeIf { isGroupConversation })
            .setContentText(plainMessageText)
            .setTicker(plainMessageText)
            .setStyle(messagingStyle)
            .setNumber(messagingStyle.messages.size)
            .setLargeIcon(roomAvatar ?: senderAvatar)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setWhen(minOf(data.timestamp, System.currentTimeMillis()))
            .apply {
                addExtras(
                    Bundle().apply {
                        putString(EXTRA_SESSION_ID, id.sessionId.value)
                        putString(EXTRA_ROOM_ID, id.roomId.value)
                        putStringArrayList(EXTRA_EVENT_IDS, ArrayList(eventIds))
                    }
                )
                shortcut?.let { setShortcutId(it.id) }
            }
            .build()

        try {
            notificationManager.notify(notificationId, notification)
        } catch (failure: SecurityException) {
            log.w("Notification permission was revoked before the notification could be posted", failure)
        }
    }

    suspend fun notifyAppMessage(
        id: NotificationId.AppMessage,
        data: AppMessage,
        transient: Boolean,
    ) {
        if (transient) {
            Toast.makeText(RevengeApplication.instance, data.message.renderSuspend(), Toast.LENGTH_LONG).show()
        } else {
            notify(
                id,
                title = (data.notificationTitle ?: data.message).renderSuspend(),
                message = data.message.renderSuspend(),
                largeImage = null,
            )
        }
    }

    fun activeNotificationRooms(): List<ScopedRawRoomId> {
        val notificationManager = NotificationManagerCompat.from(RevengeApplication.instance)
        return runCatching {
            notificationManager.activeNotifications.mapNotNull { active ->
                val extras = active.notification.extras
                val sessionId = extras.getString(EXTRA_SESSION_ID)
                val roomId = extras.getString(EXTRA_ROOM_ID)
                if (sessionId != null && roomId != null) ScopedRawRoomId(sessionId, roomId) else null
            }
        }.onFailure { failure ->
            log.w("Failed to inspect active notifications", failure)
        }.getOrDefault(emptyList())
    }

    fun maybeAutoDismiss(sessionId: String, roomId: String, latestRead: List<String>): Boolean {
        val notificationManager = NotificationManagerCompat.from(RevengeApplication.instance)
        val notificationId = NotificationId.Room(SessionId(sessionId), RoomId(roomId)).androidNotificationId()
        val active = runCatching {
            notificationManager.activeNotifications.firstOrNull { it.id == notificationId }
        }.onFailure { failure ->
            log.w("Failed to inspect active notifications", failure)
        }.getOrNull() ?: return false
        val latestPosted =
            active.notification.extras.getStringArrayList(EXTRA_EVENT_IDS)?.lastOrNull() ?: return false
        log.d { "Comparing posted notification for $sessionId, $roomId, $latestPosted against [${latestRead.joinToString()}]" }
        if (latestPosted in latestRead) {
            runCatching { notificationManager.cancel(notificationId) }
                .onFailure { failure ->
                    log.w("Failed to cancel auto-dismissed notification for $sessionId/$roomId", failure)
                }
            return true
        }
        return false
    }

    fun dismiss(sessionId: String, roomId: String): Boolean {
        val notificationManager = NotificationManagerCompat.from(RevengeApplication.instance)
        val notificationId = NotificationId.Room(SessionId(sessionId), RoomId(roomId)).androidNotificationId()
        val active = runCatching {
            notificationManager.activeNotifications.filter { posted ->
                posted.id == notificationId ||
                        (posted.notification.extras.getString(EXTRA_SESSION_ID) == sessionId &&
                         posted.notification.extras.getString(EXTRA_ROOM_ID) == roomId)
            }
        }.onFailure { failure ->
            log.w("Failed to inspect active notifications", failure)
        }.getOrNull() ?: return false
        active.forEach { posted ->
            runCatching { notificationManager.cancel(posted.tag, posted.id) }
                .onFailure { failure ->
                    log.w("Failed to cancel notification ${posted.id} for $sessionId/$roomId", failure)
                }
        }
        return active.isNotEmpty()
    }

    fun redactMessage(
        sessionId: String,
        roomId: String,
        eventId: String,
        context: Context = RevengeApplication.instance,
    ): Boolean {
        val notificationManager = NotificationManagerCompat.from(context)
        if (!context.canPostNotifications() || !notificationManager.areNotificationsEnabled()) return false

        val notificationId = NotificationId.Room(SessionId(sessionId), RoomId(roomId)).androidNotificationId()
        val active = runCatching {
            notificationManager.activeNotifications.firstOrNull { it.id == notificationId }
        }.onFailure { failure ->
            log.w("Failed to inspect active notifications", failure)
        }.getOrNull() ?: return false
        val extras = active.notification.extras

        val messagingStyle = active.notification?.let {
            NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it)
        } ?: return false
        val eventIds = extras.getStringArrayList(EXTRA_EVENT_IDS)
        if (eventIds == null || eventIds.size != messagingStyle.messages.size) {
            log.e { "Existing notification for $notificationId has ${messagingStyle.messages.size} messages but tracks ${eventIds?.size} event IDs" }
            return false
        }
        if (eventIds.none { it == eventId }) {
            return false
        }
        if (eventIds.all { it == eventId }) {
            log.d("Dismissing notification for $sessionId, $roomId, size=${eventIds.size}")
            runCatching { notificationManager.cancel(notificationId) }
                .onFailure { failure ->
                    log.w("Failed to cancel dismissed notification for $sessionId/$roomId", failure)
                }
            return true
        }
        // MessagingStyle has no remove-message API, so rebuild it without the removed messages
        val newStyle = NotificationCompat.MessagingStyle(messagingStyle.user)
            .setConversationTitle(messagingStyle.conversationTitle)
            .setGroupConversation(messagingStyle.isGroupConversation())
        messagingStyle.messages.forEachIndexed { index, message ->
            if (eventIds[index] == eventId) return@forEachIndexed
            val newMessage = NotificationCompat.MessagingStyle.Message(
                message.text,
                message.timestamp,
                message.person,
            )
            message.dataMimeType?.let { mime -> message.dataUri?.let { uri -> newMessage.setData(mime, uri) } }
            newStyle.addMessage(newMessage)
        }
        val remainingIds = ArrayList(eventIds.filter { it != eventId })
        val notification = NotificationCompat.Builder(context, active.notification)
            .setStyle(newStyle)
            .setOnlyAlertOnce(true)
            .setNumber(newStyle.messages.size)
            .setContentText(newStyle.messages.last().text)
            .apply {
                addExtras(
                    Bundle().apply {
                        putString(EXTRA_SESSION_ID, sessionId)
                        putString(EXTRA_ROOM_ID, roomId)
                        putStringArrayList(EXTRA_EVENT_IDS, remainingIds)
                    }
                )
            }
            .build()
        return try {
            notificationManager.notify(notificationId, notification)
            true
        } catch (failure: SecurityException) {
            log.w("Failed to repost dismissed notification for $sessionId/$roomId", failure)
            false
        }
    }

    private fun NotificationId.conversationDestination() = when (this) {
        is NotificationId.Event -> Destination.Conversation(sessionId, roomId)
        is NotificationId.Room -> Destination.Conversation(sessionId, roomId)
        is NotificationId.AppMessage,
        NotificationId.DebugMessage,
        is NotificationId.VerificationRequest -> null
    }

    private fun NotificationId.androidNotificationId(): Int = when (this) {
        is NotificationId.Event -> NotificationId.Room(sessionId, roomId).hashCode()
        else -> hashCode()
    }

    private fun previewTokenKey(sessionId: String, roomId: String) =
        "${sessionId.length}:$sessionId:$roomId"

    /** Accept preview text only when it belongs to a notification created by this app. */
    fun captureOpenedPreview(intent: Intent) {
        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: return
        val roomId = intent.getStringExtra(EXTRA_ROOM_ID) ?: return
        val token = intent.getStringExtra(EXTRA_PREVIEW_TOKEN) ?: return
        val eventId = intent.getStringExtra(EXTRA_PREVIEW_EVENT_ID) ?: return
        val text = intent.getStringExtra(EXTRA_PREVIEW_TEXT)?.takeIf { it.isNotBlank() } ?: return
        val postedAt = intent.getLongExtra(EXTRA_PREVIEW_POSTED_AT, 0L)
        if (postedAt <= 0 || System.currentTimeMillis() - postedAt !in 0L..PREVIEW_MAX_AGE_MS) return
        val prefs = RevengeApplication.instance.getSharedPreferences(PREVIEW_TOKEN_PREFS, Context.MODE_PRIVATE)
        val key = previewTokenKey(sessionId, roomId)
        if (prefs.getString(key, null) != token) return
        prefs.edit().remove(key).apply()
        NotificationOpenPreviews.show(NotificationOpenPreview(sessionId, roomId, eventId, text))
    }

    private fun NotificationId.createIntent(
        context: Context,
        preview: NotificationOpenPreview? = null,
    ): Intent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        conversationDestination()?.let { destination ->
            intent.putExtra(MainActivity.EXTRA_DESTINATION, destination.serializedToString())
        }
        when (this) {
            is NotificationId.Event -> {
                intent.putExtra(EXTRA_SESSION_ID, sessionId.value)
                intent.putExtra(EXTRA_ROOM_ID, roomId.value)
            }
            is NotificationId.Room -> {
                intent.putExtra(EXTRA_SESSION_ID, sessionId.value)
                intent.putExtra(EXTRA_ROOM_ID, roomId.value)
            }
            else -> Unit
        }
        if (this is NotificationId.Event && preview != null &&
            preview.sessionId == sessionId.value && preview.roomId == roomId.value &&
            preview.eventId == eventId.value && preview.text.isNotBlank()
        ) {
            val token = UUID.randomUUID().toString()
            val prefs = context.getSharedPreferences(PREVIEW_TOKEN_PREFS, Context.MODE_PRIVATE)
            if (prefs.edit().putString(previewTokenKey(sessionId.value, roomId.value), token).commit()) {
                intent.putExtra(EXTRA_PREVIEW_EVENT_ID, preview.eventId)
                intent.putExtra(EXTRA_PREVIEW_TEXT, preview.text)
                intent.putExtra(EXTRA_PREVIEW_TOKEN, token)
                intent.putExtra(EXTRA_PREVIEW_POSTED_AT, System.currentTimeMillis())
            }
        }
        return intent
    }

    private fun NotificationId.createPendingIntent(
        context: Context,
        notificationId: Int,
        preview: NotificationOpenPreview? = null,
    ): PendingIntent? {
        val intent = createIntent(context, preview) ?: return null
        return PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildReplyAction(
        context: Context,
        notificationId: Int,
        sessionId: SessionId,
        roomId: RoomId,
        label: String,
    ): NotificationCompat.Action {
        val intent = notificationActionIntent(
            context = context,
            action = ACTION_NOTIFICATION_REPLY,
            sessionId = sessionId,
            roomId = roomId,
        )
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationActionRequestCode(notificationId, 1),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel(label)
            .build()
        return NotificationCompat.Action.Builder(0, label, pendingIntent)
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .setShowsUserInterface(false)
            .build()
    }

    private fun buildMarkReadAction(
        context: Context,
        notificationId: Int,
        sessionId: SessionId,
        roomId: RoomId,
        label: String,
    ): NotificationCompat.Action {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationActionRequestCode(notificationId, 2),
            notificationActionIntent(
                context = context,
                action = ACTION_NOTIFICATION_MARK_READ,
                sessionId = sessionId,
                roomId = roomId,
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action.Builder(0, label, pendingIntent)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()
    }

    private fun buildCopyCodeAction(
        context: Context,
        notificationId: Int,
        code: String,
    ): NotificationCompat.Action {
        val intent = Intent(context, NotificationActionReceiver::class.java)
            .setAction(ACTION_NOTIFICATION_COPY_CODE)
            .putExtra(EXTRA_COPY_CODE, code)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationActionRequestCode(notificationId, 3),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action.Builder(
            0,
            context.getString(R.string.notification_action_copy_code),
            pendingIntent,
        )
            .setShowsUserInterface(false)
            .build()
    }

    private fun notificationActionIntent(
        context: Context,
        action: String,
        sessionId: SessionId,
        roomId: RoomId,
    ) = Intent(context, NotificationActionReceiver::class.java)
        .setAction(action)
        .putExtra(EXTRA_SESSION_ID, sessionId.value)
        .putExtra(EXTRA_ROOM_ID, roomId.value)

    private fun notificationActionRequestCode(notificationId: Int, actionIndex: Int): Int =
        notificationId * 31 + actionIndex

    internal suspend fun handleNotificationAction(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_NOTIFICATION_COPY_CODE -> {
                val code = intent.getStringExtra(EXTRA_COPY_CODE)?.takeIf(String::isNotBlank) ?: return
                val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
                clipboard.setPrimaryClip(ClipData.newPlainText("Verification code", code))
                return
            }

            ACTION_NOTIFICATION_REPLY,
            ACTION_NOTIFICATION_MARK_READ -> Unit

            else -> return
        }

        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)?.let(::SessionId) ?: return
        val roomId = intent.getStringExtra(EXTRA_ROOM_ID)?.let(::RoomId) ?: return
        val client = RevengeAppGraph.sessionCache.getOrRestore(sessionId)
            .onFailure { failure -> log.w("Failed to restore $sessionId for notification action", failure) }
            .getOrNull()
            ?: return
        val room = client.getJoinedRoom(roomId) ?: run {
            log.w { "Cannot handle notification action for non-joined room $roomId" }
            return
        }
        room.use { joinedRoom ->
            if (intent.action == ACTION_NOTIFICATION_REPLY) {
                val reply = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(KEY_TEXT_REPLY)
                    ?.toString()
                    ?.trim()
                    ?.takeIf(String::isNotEmpty)
                    ?: return
                val result = joinedRoom.liveTimeline.sendMessage(
                    body = reply,
                    htmlBody = null,
                    intentionalMentions = emptyList(),
                    asPlainText = true,
                )
                if (result.isFailure) {
                    log.w("Notification quick reply failed for $roomId", result.exceptionOrNull())
                    return
                }
            }

            joinedRoom.liveTimeline.markAsRead(ReceiptType.READ_PRIVATE)
                .onFailure { failure -> log.w("Notification mark-read receipt failed for $roomId", failure) }
            joinedRoom.liveTimeline.markAsRead(ReceiptType.FULLY_READ)
                .onFailure { failure -> log.w("Notification fully-read marker failed for $roomId", failure) }
        }
        dismiss(sessionId.value, roomId.value)
    }

    private suspend fun loadNotificationMediaUri(
        context: Context,
        data: NotificationData,
        source: MediaSource,
        mimeType: String?,
        filename: String?,
    ): Pair<Uri, String?>? {
        return withTimeoutOrNull(MEDIA_TIMEOUT.milliseconds) {
            val mediaLoader = RevengeAppGraph.sessionCache.getOrRestore(data.sessionId).getOrNull()
                ?.matrixMediaLoader
                ?: return@withTimeoutOrNull null
            val file = MediaDownloadRepo.requestAttachmentDownload(
                sessionId = data.sessionId,
                roomId = data.roomId,
                sourceTimestamp = data.timestamp,
                mediaSource = source,
                mimeType = mimeType,
                filename = filename,
                mediaLoader = mediaLoader,
            ).onFailure { failure ->
                log.w("Failed to load media for notification ${data.eventId}", failure)
            }.getOrNull() ?: return@withTimeoutOrNull null
            val mimeType = mimeType?.takeIf { it.startsWith("image/") }
                ?: MimeUtil.detectMimeType(file).takeIf { it.startsWith("image/") }
                ?: return@withTimeoutOrNull null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !ImageDecoder.isMimeTypeSupported(mimeType)) {
                log.d { "Notification media MIME type $mimeType is not supported" }
                return@withTimeoutOrNull null
            }
            val uri = runCatching {
                FileProvider.getUriForFile(context, context.fileProviderAuthority, file)
            }.onFailure { failure ->
                log.w("Failed to expose media for notification ${data.eventId}", failure)
            }.getOrNull() ?: return@withTimeoutOrNull null
            Pair(uri, mimeType)
        }
    }

    private suspend fun createConversationShortcut(
        sessionId: SessionId,
        roomId: RoomId,
        label: String?,
        icon: Bitmap?,
        person: Person?,
        context: Context,
    ): ShortcutInfoCompat? {
        val intent = NotificationId.Room(sessionId, roomId).createIntent(context) ?: return null
        val safeLabel = label?.takeIf(String::isNotBlank) ?: roomId.value
        return ShortcutInfoCompat.Builder(context, conversationShortcutId(sessionId, roomId))
            .setShortLabel(safeLabel)
            .setLongLabel(safeLabel)
            .setIntent(intent)
            .setIsConversation()
            .setLongLived(true)
            .setCategories(setOf(DIRECT_SHARE_TARGET_CATEGORY))
            .apply {
                icon?.let { setIcon(IconCompat.createWithBitmap(it)) }
                person?.let { setPerson(person) }
            }
            .build()
    }

    private fun conversationShortcutSessionPrefix(sessionId: SessionId): String {
        return "$CONVERSATION_SHORTCUT_PREFIX${sessionId.value.hash().take(32)}_"
    }

    internal fun conversationShortcutId(sessionId: SessionId, roomId: RoomId): String {
        return conversationShortcutSessionPrefix(sessionId) + roomId.value.hash().take(32)
    }

    private fun removeConversationShortcutsForUnknownSessions(context: Context, sessionIds: List<SessionId>) {
        val knownSessionPrefixes = sessionIds.map(::conversationShortcutSessionPrefix)
        val shortcutIds = runCatching {
            ShortcutManagerCompat.getShortcuts(
                context,
                ShortcutManagerCompat.FLAG_MATCH_DYNAMIC or ShortcutManagerCompat.FLAG_MATCH_CACHED,
            ).mapNotNull { shortcut ->
                shortcut.id.takeIf { id ->
                    id.startsWith(CONVERSATION_SHORTCUT_PREFIX) &&
                        knownSessionPrefixes.none { prefix -> id.startsWith(prefix) }
                }
            }.distinct()
        }.onFailure { failure ->
            log.w("Failed to fetch conversation shortcuts", failure)
        }.getOrNull() ?: return

        if (shortcutIds.isEmpty()) return
        runCatching {
            ShortcutManagerCompat.removeLongLivedShortcuts(context, shortcutIds)
        }.onSuccess {
            log.d { "Removed ${shortcutIds.size} conversation shortcuts for deleted sessions" }
        }.onFailure { failure ->
            log.w("Failed to remove conversation shortcuts for deleted sessions", failure)
        }
    }

    private fun createSessionNotificationChannels(
        context: Context = RevengeApplication.instance,
        sessionIds: List<SessionId>,
    ) {
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        log.d { "Create ${sessionIds.size} session notification channels" }
        notificationManager.createNotificationChannels(
            sessionIds.map { sessionId ->
                NotificationChannel(
                    messageChannelId(sessionId),
                    sessionId.value,
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    enableVibration(true)
                    enableLights(true)
                    group = CHAT_MESSAGES_CHANNEL_ID_GROUP
                }
            }
        )
    }

    suspend fun launchCreateNotificationChannelsLoop(
        scope: CoroutineScope,
        context: Context = RevengeApplication.instance,
    ) {
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    APP_NOTICES_CHANNEL_ID,
                    getString(Res.string.notification_channel_app_notices),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        )
        notificationManager.createNotificationChannelGroup(
            NotificationChannelGroup(
                CHAT_MESSAGES_CHANNEL_ID_GROUP,
                getString(Res.string.notification_channel_group_chat_messages),
            )
        )
        knownSessionIds.onEach { sessionIds ->
            removeConversationShortcutsForUnknownSessions(context, sessionIds)
            val expectSessionChannelIds = sessionIds.map(::messageChannelId).toSet()
            // Clean up old channels
            notificationManager.notificationChannels.forEach { channel ->
                if (channel.id != APP_NOTICES_CHANNEL_ID && channel.id !in expectSessionChannelIds) {
                    log.d { "Delete old notification channel ${channel.id}" }
                    notificationManager.deleteNotificationChannel(channel.id)
                }
            }
            // Create/update channels for current sessions
            createSessionNotificationChannels(context, sessionIds)
        }.launchIn(scope)
    }

    private fun Context.canPostNotifications(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

    private fun Bitmap.circularAvatar(): Bitmap {
        // Large notification icons, MessagingStyle senders, and conversation shortcuts should
        // all have the same circular silhouette, regardless of the source image's aspect ratio.
        val diameter = minOf(width, height)
        val bitmap = if (config == Bitmap.Config.HARDWARE) copy(Bitmap.Config.ARGB_8888, false) else this
        val shader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(Matrix().apply {
                setTranslate((diameter - width) / 2f, (diameter - height) / 2f)
            })
        }
        return Bitmap.createBitmap(diameter, diameter, Bitmap.Config.ARGB_8888).also { output ->
            Canvas(output).drawCircle(
                diameter / 2f,
                diameter / 2f,
                diameter / 2f,
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader },
            )
        }
    }

    private suspend fun loadMediaBitmap(sessionId: SessionId?, source: MediaSource): Bitmap? {
        sessionId ?: return null
        return measureTimedValue {
            withTimeoutOrNull(MEDIA_TIMEOUT.milliseconds) {
                val imageLoaderHolder = RevengeAppGraph.imageLoaderHolder
                val imageLoader = imageLoaderHolder.getIfExists(sessionId) ?: run {
                    val client = RevengeAppGraph.sessionCache.getOrRestore(sessionId).getOrNull()
                        ?: return@withTimeoutOrNull null
                    imageLoaderHolder.get(client)
                }
                val requestData = MediaRequestData(source, MediaRequestData.Kind.Content)
                val context = RevengeApplication.instance
                val request = ImageRequest.Builder(context)
                    .data(requestData)
                    .size(LARGE_ICON_SIZE)
                    .precision(Precision.INEXACT)
                    .allowAnimatedImageDecoding(false)
                    .build()
                ((imageLoader.execute(request) as? SuccessResult)?.image as? BitmapImage)?.bitmap
            }
        }.let {
            log.d { "Bitmap load for $sessionId, ${source.safeUrl} took ${it.duration}, success=${it.value != null}" }
            it.value
        }
    }
}

