package chat.schildi.revenge

import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import chat.schildi.lib.preferences.ScPrefs
import androidx.compose.runtime.remember
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.datetime_today
import shire.res.generated.resources.datetime_yesterday
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** A single preference source for all visible timestamps, without per-row subscriptions. */
val LocalTimeDisplayFormat = compositionLocalOf { ScPrefs.TimeFormat.TWELVE_HOUR }

object DateTimeFormat {

    fun timestampToDateTime(timestamp: Long) =
        LocalDateTime.ofInstant(Instant.ofEpochMilli(timestamp), ZoneId.systemDefault())

    fun formatDate(
        dateTime: LocalDateTime,
        strings: DateTimeStrings,
        now: LocalDateTime = LocalDateTime.now(),
    ): String {
        return if (now.year == dateTime.year) {
            if (now.dayOfYear == dateTime.dayOfYear) {
                strings.today
            } else if (now.dayOfYear == dateTime.dayOfYear + 1) {
                strings.yesterday
            } else {
                DateTimeFormatter.ofPattern("EEE, MMM d").format(dateTime)
            }
        } else {
            DateTimeFormatter.ofPattern("EEE, MMM d, yyyy").format(dateTime)
        }
    }

    private fun timePattern(format: String): String = when (format) {
        ScPrefs.TimeFormat.TWENTY_FOUR_HOUR -> "HH:mm"
        ScPrefs.TimeFormat.TWELVE_HOUR_SECONDS -> "h:mm:ss a"
        ScPrefs.TimeFormat.TWENTY_FOUR_HOUR_SECONDS -> "HH:mm:ss"
        else -> "h:mm a"
    }

    fun formatTime(dateTime: LocalDateTime, format: String = ScPrefs.TimeFormat.TWELVE_HOUR): String =
        DateTimeFormatter.ofPattern(timePattern(format), Locale.getDefault()).format(dateTime)

    fun formatFullDateTime(dateTime: LocalDateTime, format: String = ScPrefs.TimeFormat.TWELVE_HOUR): String =
        DateTimeFormatter.ofPattern("d MMM yyyy, ${timePattern(format)}", Locale.getDefault()).format(dateTime)

    fun formatDateOrTime(
        dateTime: LocalDateTime,
        strings: DateTimeStrings,
        now: LocalDateTime = LocalDateTime.now(),
        format: String = ScPrefs.TimeFormat.TWELVE_HOUR,
    ): String {
        return if (now.year == dateTime.year && now.dayOfYear == dateTime.dayOfYear) {
            formatTime(dateTime, format)
        } else {
            formatDate(dateTime, strings, now)
        }
    }

    fun formatDatetime(
        dateTime: LocalDateTime,
        strings: DateTimeStrings,
        now: LocalDateTime = LocalDateTime.now(),
        format: String = ScPrefs.TimeFormat.TWELVE_HOUR,
    ): String = buildString {
        append(formatDate(dateTime, strings, now))
        append(" ")
        append(formatTime(dateTime, format))
    }

    fun formatTimeOrDateTime(
        dateTime: LocalDateTime,
        strings: DateTimeStrings,
        now: LocalDateTime = LocalDateTime.now(),
        format: String = ScPrefs.TimeFormat.TWELVE_HOUR,
    ): String {
        return if (now.year == dateTime.year && now.dayOfYear == dateTime.dayOfYear) {
            formatTime(dateTime, format)
        } else {
            formatDatetime(dateTime, strings, now, format)
        }
    }

    @Composable
    fun dateTimeStrings() = DateTimeStrings(
        today = stringResource(Res.string.datetime_today),
        yesterday = stringResource(Res.string.datetime_yesterday),
    )

    @Composable
    fun formatTimestampAsDate(timestamp: Long): String {
        val strings = dateTimeStrings()
        return remember(timestamp) {
            formatDate(timestampToDateTime(timestamp), strings)
        }
    }

    @Composable
    fun formatTimestampAsDateOrTime(timestamp: Long): String {
        val strings = dateTimeStrings()
        val format = LocalTimeDisplayFormat.current
        return remember(timestamp, format, strings) {
            formatDateOrTime(timestampToDateTime(timestamp), strings, format = format)
        }
    }

    @Composable
    fun formatTimeOrDateTime(timestamp: Long): String {
        val strings = dateTimeStrings()
        val format = LocalTimeDisplayFormat.current
        return remember(timestamp, format, strings) {
            formatTimeOrDateTime(timestampToDateTime(timestamp), strings, format = format)
        }
    }
}

data class DateTimeStrings(
    val today: String,
    val yesterday: String,
)
