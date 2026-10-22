package chat.schildi.revenge.compose.composer

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.compose.destination.conversation.event.message.FileMessageContent
import chat.schildi.revenge.compose.destination.conversation.event.message.FileMessageRenderType
import chat.schildi.revenge.compose.destination.conversation.event.message.ImageMessageContent
import chat.schildi.revenge.compose.destination.conversation.event.message.VideoMessageContent
import chat.schildi.revenge.model.Attachment
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_clear_attachment

@Composable
fun ComposerAttachment(
    attachment: Attachment,
    onRemoveClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isVisual = attachment is Attachment.VisualAttachment
    Row(
        modifier
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .then(
                if (isVisual) Modifier else Modifier.background(
                    MaterialTheme.colorScheme.surfaceContainerHighest,
                    RoundedCornerShape(20.dp),
                )
            )
            .padding(start = if (isVisual) 0.dp else 10.dp, end = 2.dp, top = 8.dp, bottom = 8.dp),
        horizontalArrangement = if (isVisual) Arrangement.Center else Arrangement.Start,
        verticalAlignment = if (isVisual) Alignment.Top else Alignment.CenterVertically,
    ) {
        ComposerAttachmentContent(
            attachment = attachment,
            modifier = if (isVisual) Modifier else Modifier.weight(1f),
        )
        IconButton(
            onClick = onRemoveClick,
            modifier = Modifier.size(36.dp),
        ) {
            Icon(
                Icons.Default.Clear,
                stringResource(Res.string.action_clear_attachment),
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
fun ComposerAttachmentContent(
    attachment: Attachment,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        when (attachment) {
            is Attachment.Image -> {
                ImageMessageContent(
                    model = attachment.file,
                    width = attachment.imageInfo.width,
                    height = attachment.imageInfo.height,
                    minWidth = 72.dp,
                    minHeight = 72.dp,
                    maxWidth = 256.dp,
                    maxHeight = 196.dp,
                    shape = RoundedCornerShape(16.dp),
                )
            }

            is Attachment.Video -> {
                VideoMessageContent(
                    model = attachment.thumbnail?.data ?: attachment.file,
                    width = attachment.videoInfo.width,
                    height = attachment.videoInfo.height,
                    minWidth = 72.dp,
                    minHeight = 72.dp,
                    maxWidth = 256.dp,
                    maxHeight = 196.dp,
                    shape = RoundedCornerShape(16.dp),
                )
            }

            is Attachment.Audio -> {
                FileMessageContent(
                    type = FileMessageRenderType.AUDIO,
                    filename = attachment.file.name,
                    messageMetadata = null,
                )
            }

            is Attachment.Generic -> {
                FileMessageContent(
                    type = FileMessageRenderType.FILE,
                    filename = attachment.file.name,
                    messageMetadata = null,
                )
            }
        }
    }
}
