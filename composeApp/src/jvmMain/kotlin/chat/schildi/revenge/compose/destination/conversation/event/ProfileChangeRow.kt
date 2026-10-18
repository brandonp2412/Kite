package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import chat.schildi.revenge.plaintext.EventTextFormat
import io.element.android.libraries.matrix.api.core.UserId
import io.element.android.libraries.matrix.api.timeline.item.event.ProfileChangeContent
import io.element.android.libraries.matrix.api.timeline.item.event.ProfileDetails

@Composable
fun ProfileChangeRow(
    content: ProfileChangeContent,
    senderId: UserId,
    senderProfile: ProfileDetails,
    modifier: Modifier = Modifier,
) {
    val text = EventTextFormat.profileChangeToText(content, senderProfile, senderId)
    StateUpdateRow(
        text = AnnotatedString(text),
        senderProfile = senderProfile,
        senderId = senderId,
        modifier = modifier,
    )
}
