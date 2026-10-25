package chat.schildi.revenge.compose.destination.conversation.event.reaction

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReactionEmojiSearchTest {
    @Test
    fun catMatchesEmojiWordsButNotSubstringsInsideUnrelatedWords() {
        val pattern = reactionEmojiSearchPattern("cat")
        assertTrue(pattern.containsMatchIn("smiling cat with heart-eyes"))
        assertTrue(pattern.containsMatchIn("black_cat"))
        assertFalse(pattern.containsMatchIn("identification card"))
        assertFalse(pattern.containsMatchIn("multiplication sign"))
        assertFalse(pattern.containsMatchIn("Japanese application button"))
    }

    @Test
    fun partialWordsAndMultiwordAliasesStillMatch() {
        assertTrue(reactionEmojiSearchPattern("shak").containsMatchIn("shaking face"))
        assertTrue(reactionEmojiSearchPattern("disco ball").containsMatchIn("disco ball"))
        assertFalse(reactionEmojiSearchPattern("ball").containsMatchIn("footballer"))
    }
}
