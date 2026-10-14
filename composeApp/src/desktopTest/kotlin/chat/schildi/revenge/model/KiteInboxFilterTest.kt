package chat.schildi.revenge.model

import kotlin.test.Test
import kotlin.test.assertEquals

class KiteInboxFilterTest {
    private data class Item(
        val id: String,
        val name: String?,
        val privateName: String? = null,
        val isSpace: Boolean = false,
        val latestEventTimestamp: Long? = null,
        val sessionOrder: Int = 0,
    )

    @Test
    fun blankSearchPreservesRoomOrderAndExcludesSpaces() {
        val items = listOf(
            Item("first", "First"),
            Item("space", "Workspace", isSpace = true),
            Item("second", "Second"),
        )

        assertEquals(
            listOf("first", "second"),
            filter(items, "").map(Item::id),
        )
    }

    @Test
    fun searchMatchesPrivateAndPublicNamesCaseInsensitively() {
        val items = listOf(
            Item("public", "Project Kite"),
            Item("private", "Unrelated", privateName = "KITE DM"),
            Item("space", "Kite Space", isSpace = true),
            Item("miss", "Revenge"),
        )

        assertEquals(
            listOf("private", "public"),
            filter(items, "kite").map(Item::id),
        )
    }

    @Test
    fun searchRanksMatchPositionThenActivityThenSessionOrder() {
        val items = listOf(
            Item("late-match", "My Kite", latestEventTimestamp = 500, sessionOrder = 0),
            Item("older", "Kite old", latestEventTimestamp = 100, sessionOrder = 0),
            Item("newer", "Kite new", latestEventTimestamp = 300, sessionOrder = 1),
            Item("same-time-first-session", "Kite tie", latestEventTimestamp = 300, sessionOrder = 0),
            Item("no-time", "Kite unknown", latestEventTimestamp = null, sessionOrder = 0),
        )

        assertEquals(
            listOf(
                "same-time-first-session",
                "newer",
                "older",
                "no-time",
                "late-match",
            ),
            filter(items, "kite").map(Item::id),
        )
    }

    private fun filter(items: List<Item>, query: String?) = filterKiteInboxItems(
        items = items,
        searchTerm = query,
        isSpace = Item::isSpace,
        primaryName = Item::name,
        secondaryName = Item::privateName,
        latestEventTimestamp = Item::latestEventTimestamp,
        sessionOrder = Item::sessionOrder,
    )
}
