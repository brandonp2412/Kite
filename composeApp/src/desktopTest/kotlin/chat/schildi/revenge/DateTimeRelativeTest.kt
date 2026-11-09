package chat.schildi.revenge

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals

class DateTimeRelativeTest {
    private val strings = DateTimeStrings(today = "Today", yesterday = "Yesterday")
    private val now = LocalDateTime.of(2026, 1, 2, 12, 0)

    @Test
    fun usesCalendarDaysIncludingYearBoundary() {
        fun label(days: Long) = DateTimeFormat.formatRelativeDate(now.minusDays(days), strings, now)

        assertEquals("Today", label(0))
        assertEquals("Yesterday", label(1))
        assertEquals("3 days ago", label(3))
        assertEquals("6 days ago", label(6))
        assertEquals("a week ago", label(7))
        assertEquals("a week ago", label(13))
        assertEquals("2 weeks ago", label(14))
        assertEquals("a month ago", label(30))
        assertEquals("3 months ago", label(90))
        assertEquals("a year ago", label(365))
        assertEquals("2 years ago", label(730))
    }

    @Test
    fun futureMessageKeepsAbsoluteDate() {
        assertEquals(
            "Sat, Jan 3",
            DateTimeFormat.formatRelativeDate(now.plusDays(1), strings, now),
        )
    }
}
