package chat.schildi.revenge.compose.destination.conversation.event.reaction

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.kodein.emoji.Emoji
import org.kodein.emoji.list

/** Actual emoji selection instead of switching the composer to reaction-text mode. */
@Composable
fun ReactionPickerDialog(onDismiss: () -> Unit, onSelect: (String) -> Unit) {
    var query by remember { mutableStateOf("") }
    val emojis = remember {
        Emoji.list().map { it.details }
    }
    val results = remember(emojis, query) {
        val search = query.trim()
        if (search.isBlank()) emojis else {
            val pattern = reactionEmojiSearchPattern(search)
            emojis.filter { details ->
                pattern.containsMatchIn(details.description) ||
                    details.aliases.any(pattern::containsMatchIn) ||
                    (details.string == "🪩" && pattern.containsMatchIn("disco ball")) ||
                    (details.string == "🎃" && pattern.containsMatchIn("pumpkin"))
            }
        }
    }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    Dialog(
        onDismissRequest = {
            focusManager.clearFocus(force = true)
            keyboardController?.hide()
            onDismiss()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            val gridMaxHeight = (maxHeight - 224.dp).coerceIn(44.dp, 420.dp)
            Surface(
                modifier = Modifier.fillMaxWidth(0.94f).padding(top = 88.dp),
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surface,
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("React", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text("Search emoji") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(44.dp),
                        modifier = Modifier.fillMaxWidth().height(gridMaxHeight),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        items(results, key = { it.string }) { emoji ->
                            IconButton(
                                onClick = {
                                    focusManager.clearFocus(force = true)
                                    keyboardController?.hide()
                                    onSelect(emoji.string)
                                },
                                modifier = Modifier.size(44.dp),
                            ) {
                                Text(
                                    emoji.string,
                                    fontSize = 26.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Clip,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

internal fun reactionEmojiSearchPattern(query: String): Regex =
    Regex("(?<![\\p{L}\\p{N}])${Regex.escape(query)}", RegexOption.IGNORE_CASE)
