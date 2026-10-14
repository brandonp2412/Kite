package chat.schildi.revenge.model

import kotlin.test.Test
import kotlin.test.assertEquals

class KiteInboxFilterTest {
    private data class Item(
        val id: String,
        val name: String?,
        val privateName: String? = null,
        val isSpace: Boolean = false,
        val isPinned: Boolean = false,
        val latestEventTimestamp: Long? = null,
        val sessionOrder: Int = 0,
    )

    @Test
    fun blankSearchSortsByRecentActivityDespiteSdkPriorityAndExcludesSpaces() {
        val items = listOf(
            Item("old-facebook", "Archived chat", latestEventTimestamp = 1_458_589_914_555L),
            Item("space", "Workspace", isSpace = true, latestEventTimestamp = 1_900_000_000_000L),
            Item("recent", "Recent", latestEventTimestamp = 1_760_000_000_000L),
            Item("no-latest-event", "Unknown"),
            Item("newest", "Newest", latestEventTimestamp = 1_790_000_000_000L),
        )

        assertEquals(
            listOf("newest", "recent", "old-facebook", "no-latest-event"),
            filter(items, "").map(Item::id),
        )
        assertEquals(
            listOf("newest", "recent", "old-facebook", "no-latest-event"),
            filter(items, null).map(Item::id),
        )
    }

    @Test
    fun pinnedRoomsStayFirstButSortByActivityWithinTheirGroup() {
        val items = listOf(
            Item("unread-recent", "Unread", latestEventTimestamp = 1_800_000_000_000L),
            Item("pinned-old", "Pinned old", isPinned = true, latestEventTimestamp = 1_458_589_914_555L),
            Item("normal-recent", "Recent", latestEventTimestamp = 1_790_000_000_000L),
            Item("pinned-new", "Pinned new", isPinned = true, latestEventTimestamp = 1_700_000_000_000L),
        )

        assertEquals(
            listOf("pinned-new", "pinned-old", "unread-recent", "normal-recent"),
            filter(items, null).map(Item::id),
        )
    }

    @Test
    fun blankSearchUsesSessionOrderOnlyForEqualTimestamps() {
        val items = listOf(
            Item("second-session", "Other", latestEventTimestamp = 200, sessionOrder = 1),
            Item("first-session", "Main", latestEventTimestamp = 200, sessionOrder = 0),
            Item("older", "Old", latestEventTimestamp = 100, sessionOrder = 0),
        )

        assertEquals(
            listOf("first-session", "second-session", "older"),
            filter(items, null).map(Item::id),
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
        isPinned = Item::isPinned,
        primaryName = Item::name,
        secondaryName = Item::privateName,
        latestEventTimestamp = Item::latestEventTimestamp,
        sessionOrder = Item::sessionOrder,
    )
}
