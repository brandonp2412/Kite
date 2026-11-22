package io.element.android.libraries.matrix.impl.notification

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** An m.replace event updates an existing message; it must never become a standalone preview. */
fun isMatrixReplacementEvent(rawEvent: String): Boolean = runCatching {
    Json.parseToJsonElement(rawEvent).jsonObject["content"]?.jsonObject
        ?.get("m.relates_to")?.jsonObject
        ?.get("rel_type")?.jsonPrimitive?.contentOrNull == "m.replace"
}.getOrDefault(false)
