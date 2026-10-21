package chat.schildi.revenge.model.conversation

/** Display-only conversion; the original Matrix body remains intact for edit/copy. */
private val textEmoticon = Regex(
    """(?<![\p{L}\p{N}/@])(:'\)|:-\)|:\)|:-\(|:\(|;-\)|;\)|:-[DPp]|:[DPp]|<3|:3)(?![\p{L}\p{N}])"""
)

internal fun renderTextEmoticons(body: String): String = textEmoticon.replace(body) {
    when (it.value) {
        ":)", ":-)" -> "🙂"
        ":(", ":-(" -> "🙁"
        ";)", ";-)" -> "😉"
        ":D", ":-D" -> "😃"
        ":P", ":-P", ":p", ":-p" -> "😛"
        ":')" -> "🥲"
        "<3" -> "❤️"
        ":3" -> "😺"
        else -> it.value
    }
}
