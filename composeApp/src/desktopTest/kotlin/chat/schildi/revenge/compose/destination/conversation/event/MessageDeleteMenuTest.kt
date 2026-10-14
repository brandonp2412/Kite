package chat.schildi.revenge.compose.destination.conversation.event

import chat.schildi.revenge.model.conversation.ConversationPermissions
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MessageDeleteMenuTest {
    private fun permissions(own: Boolean, other: Boolean) = ConversationPermissions(
        canSendMessages = true,
        canSendReactions = true,
        canPinUnpin = false,
        canRedactOwn = own,
        canRedactOther = other,
    )

    @Test
    fun ownMessageCanDeleteWhenPermitted() {
        assertTrue(canDeleteMessage(eventHasId = true, isOwn = true, permissions = permissions(true, false)))
    }

    @Test
    fun permissionsGateForeignMessageRedaction() {
        assertFalse(canDeleteMessage(eventHasId = true, isOwn = false, permissions = permissions(true, false)))
        assertTrue(canDeleteMessage(eventHasId = true, isOwn = false, permissions = permissions(false, true)))
    }

    @Test
    fun deleteRemainsUnavailableWithoutEventIdOrPermission() {
        assertFalse(canDeleteMessage(eventHasId = false, isOwn = true, permissions = permissions(true, true)))
        assertFalse(canDeleteMessage(eventHasId = true, isOwn = true, permissions = permissions(false, true)))
        assertFalse(canDeleteMessage(eventHasId = true, isOwn = false, permissions = null))
        assertTrue(canDeleteMessage(eventHasId = true, isOwn = true, permissions = null))
    }
}
