package chat.schildi.revenge.model

private data class KiteInboxSearchMatch<T>(
    val item: T,
    val matchIndex: Int,
    val latestEventTimestamp: Long?,
    val sessionOrder: Int,
)

/**
 * Keeps Kite's personal inbox space-free and performs cheap local room-name search
 * without changing Revenge's Matrix room-list source or introducing UI-owned state.
 */
internal fun <T> filterKiteInboxItems(
    items: Iterable<T>,
    searchTerm: String?,
    isSpace: (T) -> Boolean,
    primaryName: (T) -> String?,
    secondaryName: (T) -> String?,
    latestEventTimestamp: (T) -> Long?,
    sessionOrder: (T) -> Int,
): List<T> {
    if (searchTerm.isNullOrBlank()) {
        return items.filterNot(isSpace)
    }

    val query = searchTerm.lowercase()
    return items.mapNotNull { item ->
        if (isSpace(item)) {
            return@mapNotNull null
        }

        val primaryIndex = primaryName(item)
            ?.lowercase()
            ?.indexOf(query)
            ?.takeIf { it >= 0 }
            ?: Int.MAX_VALUE
        val secondaryIndex = secondaryName(item)
            ?.lowercase()
            ?.indexOf(query)
            ?.takeIf { it >= 0 }
            ?: Int.MAX_VALUE
        val matchIndex = minOf(primaryIndex, secondaryIndex)
        if (matchIndex == Int.MAX_VALUE) {
            null
        } else {
            KiteInboxSearchMatch(
                item = item,
                matchIndex = matchIndex,
                latestEventTimestamp = latestEventTimestamp(item),
                sessionOrder = sessionOrder(item),
            )
        }
    }.sortedWith(
        compareBy<KiteInboxSearchMatch<T>>(
            { it.matchIndex },
            { it.latestEventTimestamp == null },
            { it.latestEventTimestamp?.let { timestamp -> -timestamp } },
            { it.sessionOrder },
        ),
    ).map { it.item }
}
