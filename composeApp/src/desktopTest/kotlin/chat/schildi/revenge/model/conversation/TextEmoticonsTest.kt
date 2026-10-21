package chat.schildi.revenge.model.conversation

import kotlin.test.Test
import kotlin.test.assertEquals

class TextEmoticonsTest {
    @Test
    fun translatesClassicEmoticonsInPlainMessages() {
        assertEquals("🙂 ❤️ 😉", renderTextEmoticons(":) <3 ;)"))
        assertEquals("🙁 😃 😛 🥲 😺", renderTextEmoticons(":-( :D :-p :') :3"))
    }

    @Test
    fun keepsWordsLinksAndActualEmojiUnchanged() {
        val text = "look at https://example.org/:) or x<3, hi🙂!"
        assertEquals(text, renderTextEmoticons(text))
        assertEquals("thanks, 🙂!", renderTextEmoticons("thanks, :)!"))
    }
}
