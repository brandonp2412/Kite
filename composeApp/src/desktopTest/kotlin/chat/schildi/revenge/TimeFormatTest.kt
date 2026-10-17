package chat.schildi.revenge

import chat.schildi.lib.preferences.ScPrefs
import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TimeFormatTest {
    private val morning = LocalDateTime.of(2026, 10, 18, 8, 45, 30)
    private val midnight = LocalDateTime.of(2026, 10, 18, 0, 5, 6)
    private val evening = LocalDateTime.of(2026, 10, 18, 20, 45, 30)

    @Test
    fun defaultIsTwelveHourAndCoversNoonAndMidnight() {
        val format = ScPrefs.TIME_FORMAT.defaultValue
        assertEquals(ScPrefs.TimeFormat.TWELVE_HOUR, format)
        assertTrue(DateTimeFormat.formatTime(morning, format).contains("8:45"))
        assertTrue(DateTimeFormat.formatTime(morning, format).contains("AM", ignoreCase = true))
        assertTrue(DateTimeFormat.formatTime(midnight, format).startsWith("12:05"))
        assertTrue(DateTimeFormat.formatTime(evening, format).contains("PM", ignoreCase = true))
    }

    @Test
    fun twentyFourHourAndSecondsOptions() {
        assertEquals("08:45", DateTimeFormat.formatTime(morning, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR))
        assertEquals("20:45:30", DateTimeFormat.formatTime(evening, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR_SECONDS))
        assertEquals("00:05", DateTimeFormat.formatTime(midnight, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR))
        assertTrue(DateTimeFormat.formatTime(morning, ScPrefs.TimeFormat.TWELVE_HOUR_SECONDS).startsWith("8:45:30"))
    }

    @Test
    fun dateAndTimeUseSameSelection() {
        assertTrue(DateTimeFormat.formatFullDateTime(morning, ScPrefs.TimeFormat.TWELVE_HOUR).contains("8:45"))
        assertTrue(DateTimeFormat.formatFullDateTime(morning, ScPrefs.TimeFormat.TWELVE_HOUR).contains("AM", ignoreCase = true))
        assertEquals("18 Oct 2026, 08:45", DateTimeFormat.formatFullDateTime(morning, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR))
        val labels = DateTimeStrings("Today", "Yesterday")
        assertEquals("20:45", DateTimeFormat.formatTimeOrDateTime(evening, labels, morning, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR))
        assertEquals("20:45", DateTimeFormat.formatDateOrTime(evening, labels, morning, ScPrefs.TimeFormat.TWENTY_FOUR_HOUR))
    }
}
