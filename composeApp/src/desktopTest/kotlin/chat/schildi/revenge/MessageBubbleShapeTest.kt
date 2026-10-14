package chat.schildi.revenge

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class MessageBubbleShapeTest {
    @Test
    fun standaloneBubbleKeepsFullRadius() {
        assertEquals(
            RoundedCornerShape(20.dp),
            Dimens.Conversation.messageBubbleShape(
                isOwn = false,
                joinsPrevious = false,
                joinsNext = false,
            ),
        )
    }

    @Test
    fun incomingRunKeepsFullRadius() {
        assertEquals(
            RoundedCornerShape(20.dp),
            Dimens.Conversation.messageBubbleShape(
                isOwn = false,
                joinsPrevious = true,
                joinsNext = true,
            ),
        )
    }

    @Test
    fun outgoingRunKeepsFullRadius() {
        assertEquals(
            RoundedCornerShape(20.dp),
            Dimens.Conversation.messageBubbleShape(
                isOwn = true,
                joinsPrevious = true,
                joinsNext = true,
            ),
        )
    }
}
