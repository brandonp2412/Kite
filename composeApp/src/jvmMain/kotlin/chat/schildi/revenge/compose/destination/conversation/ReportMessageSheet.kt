package chat.schildi.revenge.compose.destination.conversation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_cancel
import shire.res.generated.resources.action_report_message
import shire.res.generated.resources.report_message_reason
import shire.res.generated.resources.report_message_title

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportMessageSheet(
    onDismiss: () -> Unit,
    onReport: (String) -> Unit,
) {
    var reason by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(Res.string.report_message_title))
            OutlinedTextField(
                value = reason,
                onValueChange = { reason = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(Res.string.report_message_reason)) },
                minLines = 2,
                maxLines = 4,
                singleLine = false,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) {
                    Text(stringResource(Res.string.action_cancel))
                }
                Button(
                    onClick = {
                        val trimmed = reason.trim()
                        if (trimmed.isNotEmpty()) {
                            onDismiss()
                            onReport(trimmed)
                        }
                    },
                    enabled = reason.isNotBlank(),
                ) {
                    Text(stringResource(Res.string.action_report_message))
                }
            }
            androidx.compose.foundation.layout.Spacer(Modifier.navigationBarsPadding())
        }
    }
}
