package chat.schildi.revenge.compose.composer

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.NoEncryption
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.MessageFormatDefaults
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.currentActionContext
import chat.schildi.revenge.compose.components.ScIconButton
import chat.schildi.revenge.compose.components.WithTooltip
import chat.schildi.revenge.compose.destination.conversation.event.message.ReplyContent
import chat.schildi.revenge.compose.destination.conversation.event.message.TextLikeMessageContent
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.Attachment
import chat.schildi.lib.preferences.ComposerFormat
import chat.schildi.revenge.model.ComposerRoomInfo
import chat.schildi.revenge.model.ComposerState
import chat.schildi.revenge.model.ComposerViewModel
import chat.schildi.revenge.model.DraftType
import chat.schildi.revenge.model.DraftValue
import chat.schildi.revenge.util.filepicker.AttachmentPickerKind
import chat.schildi.revenge.util.filepicker.availableAttachmentPickerKinds
import chat.schildi.theme.scExposures
import com.beeper.android.messageformat.MatrixBodyParseResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.compose.resources.stringResource
import org.matrix.rustcomponents.sdk.markdownToHtml
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_add_attachment
import shire.res.generated.resources.action_clear_reply
import shire.res.generated.resources.action_reply
import shire.res.generated.resources.hint_composer_audio
import shire.res.generated.resources.hint_composer_caption
import shire.res.generated.resources.hint_composer_edit
import shire.res.generated.resources.hint_composer_edit_caption
import shire.res.generated.resources.hint_composer_emote
import shire.res.generated.resources.hint_composer_file
import shire.res.generated.resources.hint_composer_format_html
import shire.res.generated.resources.hint_composer_format_markdown
import shire.res.generated.resources.hint_composer_format_plain
import shire.res.generated.resources.hint_composer_image
import shire.res.generated.resources.hint_composer_missing_send_permission
import shire.res.generated.resources.hint_composer_notice
import shire.res.generated.resources.hint_composer_reaction
import shire.res.generated.resources.hint_composer_sticker
import shire.res.generated.resources.hint_composer_sticker_shortcode
import shire.res.generated.resources.hint_composer_text
import shire.res.generated.resources.hint_composer_video
import shire.res.generated.resources.hint_not_encrypted
import shire.res.generated.resources.hint_public_room
import kotlin.math.min

@Composable
fun ComposerRow(viewModel: ComposerViewModel, modifier: Modifier = Modifier) {
    when (val draftState = viewModel.composerState.collectAsState().value) {
        is DraftValue -> ComposerRow(draftState, viewModel, modifier)
        is ComposerState.ComposerLessTimeline -> {}
        is ComposerState.NoSendPermission -> BlockedComposer(stringResource(Res.string.hint_composer_missing_send_permission))
    }
}

@Composable
fun ComposerRow(
    draftState: DraftValue,
    viewModel: ComposerViewModel,
    modifier: Modifier = Modifier
) {
    val suggestionsState = viewModel.composerSuggestions.collectAsState().value
    val composerInfo = viewModel.composerRoomInfo.collectAsState().value
    val isSendInProgress = viewModel.isSendInProgress.collectAsState().value
    var showAttachmentPicker by remember { mutableStateOf(false) }
    val draftTheme = MaterialTheme.scExposures.draftTheme
    LaunchedEffect(draftTheme) {
        viewModel.updateDraftTheme(draftTheme)
    }
    if (showAttachmentPicker) {
        val actionContext = currentActionContext()
        ComposerAttachmentPicker(
            availableKinds = availableAttachmentPickerKinds,
            onPick = { viewModel.launchAttachmentPicker(actionContext, it) },
            onDismiss = { showAttachmentPicker = false },
        )
    }
    Column(modifier) {
        ComposerSuggestions(
            suggestionsState,
            viewModel::onConfirmSuggestion,
            modifier = Modifier.heightIn(max = 200.dp),
        )
        val bodyValidationError = remember(draftState.rawBody) { draftState.bodyValidationError() }
        if (bodyValidationError != null) {
            Text(
                bodyValidationError,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    start = Dimens.windowPadding,
                    end = Dimens.windowPadding,
                    top = 8.dp,
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val actionContext = currentActionContext()
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(
                        MaterialTheme.colorScheme.surfaceContainerHigh,
                        RoundedCornerShape(28.dp),
                    ),
            ) {
                if (draftState.inReplyTo != null) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, end = 6.dp, top = 8.dp, bottom = 2.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = stringResource(Res.string.action_reply),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.scExposures.accentColor,
                                modifier = Modifier.weight(1f),
                            )
                            ComposerContextClearButton(
                                contentDescription = stringResource(Res.string.action_clear_reply),
                            ) {
                                viewModel.onComposerUpdate(draftState.copy(inReplyTo = null))
                            }
                        }
                        ReplyContent(
                            draftState.inReplyTo,
                            null,
                            Modifier
                                .fillMaxWidth()
                                .padding(end = 10.dp, bottom = 6.dp),
                        )
                    }
                } else if (draftState.type == DraftType.EDIT || draftState.type == DraftType.EDIT_CAPTION) {
                    ComposerModeHeader(
                        label = if (draftState.type == DraftType.EDIT_CAPTION) {
                            stringResource(Res.string.hint_composer_edit_caption)
                        } else {
                            stringResource(Res.string.hint_composer_edit)
                        },
                        onClear = { viewModel.onComposerUpdate(DraftValue()) },
                    )
                }

                if (draftState.attachment != null) {
                    ComposerAttachment(
                        attachment = draftState.attachment,
                        onRemoveClick = viewModel::clearAttachment,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AnimatedVisibility(
                        draftState.canAddAttachment(),
                    ) {
                        WithTooltip(stringResource(Res.string.action_add_attachment)) {
                            ScIconButton(
                                onClick = { showAttachmentPicker = true },
                                enabled = !isSendInProgress,
                                minWidth = Dimens.Conversation.Composer.buttonWidth,
                                minHeight = Dimens.Conversation.Composer.buttonHeight,
                            ) {
                                val color = animateColorAsState(
                                    if (isSendInProgress)
                                        MaterialTheme.colorScheme.tertiary
                                    else
                                        MaterialTheme.colorScheme.onSurfaceVariant,
                                ).value
                                Icon(
                                    Icons.Default.Add,
                                    stringResource(Res.string.action_add_attachment),
                                    modifier = Modifier.size(24.dp),
                                    tint = color,
                                )
                            }
                        }
                    }
                if (ScPrefs.FORMATTED_COMPOSER_PREVIEW.value() && draftState.format != ComposerFormat.PLAIN) {
                    val content = formattedMessagePreview(draftState)
                    TextLikeMessageContent(
                        content,
                        Modifier
                            .fillMaxWidth(fraction = 0.4f)
                            .padding(horizontal = Dimens.horizontalItemPadding)
                            .border(1.dp, MaterialTheme.scExposures.accentColor, Dimens.Conversation.messageBubbleShape)
                            .padding(Dimens.Conversation.messageBubbleInnerPadding),
                    )
                }
                var isFocused by remember { mutableStateOf(false) }
                val maxLinesFocused = ScPrefs.COMPOSER_MAX_LINES.value()
                val maxLinesUnfocused = ScPrefs.COMPOSER_MAX_LINES_UNFOCUSED.value()
                val composerHint = when (draftState.type) {
                    DraftType.TEXT -> stringResource(Res.string.hint_composer_text)
                    DraftType.NOTICE -> stringResource(Res.string.hint_composer_notice).appendComposerFormat(draftState)
                    DraftType.EMOTE -> stringResource(Res.string.hint_composer_emote).appendComposerFormat(draftState)
                    DraftType.EDIT -> stringResource(Res.string.hint_composer_edit)
                    DraftType.EDIT_CAPTION -> stringResource(Res.string.hint_composer_edit_caption)
                    DraftType.REACTION -> stringResource(Res.string.hint_composer_reaction)
                    DraftType.STICKER -> stringResource(Res.string.hint_composer_sticker_shortcode)
                    DraftType.ATTACHMENT -> when (draftState.attachment) {
                        is Attachment.Audio -> stringResource(Res.string.hint_composer_audio)
                        is Attachment.Generic -> stringResource(Res.string.hint_composer_file)
                        is Attachment.Image -> stringResource(Res.string.hint_composer_image)
                        is Attachment.Video -> stringResource(Res.string.hint_composer_video)
                        null -> stringResource(Res.string.hint_composer_caption)
                    }
                    DraftType.CUSTOM_EVENT -> draftState.customEventType ?: ""
                    DraftType.CUSTOM_STATE_EVENT -> {
                        if (draftState.stateKey == null) {
                            draftState.customEventType ?: ""
                        } else {
                            buildString {
                                append(draftState.customEventType ?: "")
                                append(" ")
                                append(draftState.stateKey)
                            }
                        }
                    }
                }
                val composerHintColor = animateColorAsState(
                    when (draftState.type) {
                        DraftType.TEXT,
                        DraftType.EDIT,
                        DraftType.EDIT_CAPTION,
                        DraftType.ATTACHMENT -> MaterialTheme.colorScheme.onSurfaceVariant

                        DraftType.STICKER,
                        DraftType.REACTION -> MaterialTheme.scExposures.reactHint

                        DraftType.NOTICE,
                        DraftType.EMOTE,
                        DraftType.CUSTOM_EVENT,
                        DraftType.CUSTOM_STATE_EVENT -> MaterialTheme.scExposures.customEventHint
                    }
                ).value
                BasicTextField(
                    value = draftState.textFieldValue,
                    onValueChange = {
                        viewModel.onComposerUpdate(draftState.copy(textFieldValue = it))
                    },
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 56.dp)
                        .keyFocusable(role = FocusRole.MESSAGE_COMPOSER)
                        .onFocusChanged {
                            isFocused = it.isFocused
                        },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Send,
                    ),
                    keyboardActions = KeyboardActions(
                        onSend = {
                            if (draftState.canSend() && !isSendInProgress && bodyValidationError == null) {
                                viewModel.sendMessage(actionContext)
                            }
                        },
                    ),
                    maxLines = if (isFocused) maxLinesFocused else min(maxLinesUnfocused, maxLinesFocused),
                    minLines = 1,
                    cursorBrush = SolidColor(MaterialTheme.scExposures.accentColor),
                    decorationBox = { innerTextField ->
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 2.dp, end = 4.dp),
                            contentAlignment = Alignment.CenterStart,
                        ) {
                            if (draftState.textFieldValue.text.isEmpty()) {
                                Text(
                                    composerHint,
                                    color = composerHintColor,
                                    style = MaterialTheme.typography.bodyLarge,
                                    maxLines = 1,
                                )
                            }
                            innerTextField()
                        }
                    },
                )
                AnimatedVisibility(
                    draftState.type == DraftType.STICKER ||
                            draftState.type == DraftType.TEXT && composerInfo?.canSendStickers == true &&
                                    (draftState.isEmpty() || draftState.isValidSticker)
                ) {
                    WithTooltip(stringResource(Res.string.hint_composer_sticker)) {
                        ScIconButton(
                            onClick = { viewModel.toggleStickerMode() },
                            enabled = !isSendInProgress,
                            minWidth = Dimens.Conversation.Composer.buttonWidth,
                            minHeight = Dimens.Conversation.Composer.buttonHeight,
                        ) {
                            val color = animateColorAsState(
                                if (draftState.type == DraftType.STICKER)
                                    MaterialTheme.scExposures.accentColor
                                else
                                    MaterialTheme.colorScheme.onSurfaceVariant,
                            ).value
                            Icon(
                                Icons.Outlined.EmojiEmotions,
                                stringResource(Res.string.hint_composer_sticker),
                                tint = color,
                            )
                        }
                    }
                }
                AnimatedVisibility(
                    draftState.type == DraftType.TEXT &&
                            draftState.attachment == null &&
                            AttachmentPickerKind.GALLERY in availableAttachmentPickerKinds
                ) {
                    WithTooltip(stringResource(Res.string.action_add_attachment)) {
                        ScIconButton(
                            onClick = { viewModel.launchAttachmentPicker(actionContext, AttachmentPickerKind.GALLERY) },
                            enabled = !isSendInProgress,
                            minWidth = Dimens.Conversation.Composer.buttonWidth,
                            minHeight = Dimens.Conversation.Composer.buttonHeight,
                        ) {
                            Icon(
                                Icons.Outlined.PhotoLibrary,
                                stringResource(Res.string.action_add_attachment),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(24.dp),
                            )
                        }
                    }
                }
                }
            }
            if (isSendInProgress || draftState.type.needsClearButton() && draftState.isEmpty()) {
                Spacer(Modifier.width(6.dp))
                AnimatedContent(isSendInProgress) { sending ->
                    if (sending) {
                        Box(Modifier.minimumInteractiveComponentSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(32.dp),
                                color = MaterialTheme.scExposures.accentColor,
                            )
                        }
                    } else {
                        ClearButton {
                            viewModel.onComposerUpdate(DraftValue())
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ComposerModeHeader(
    label: String,
    onClear: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 6.dp, top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.scExposures.accentColor,
            modifier = Modifier.weight(1f),
        )
        ComposerContextClearButton(
            contentDescription = label,
            onClick = onClear,
        )
    }
}

@Composable
private fun ComposerContextClearButton(
    contentDescription: String,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(36.dp),
    ) {
        Icon(
            Icons.Default.Clear,
            contentDescription,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun DraftType.needsClearButton() = when (this) {
    // Default composer type
    DraftType.TEXT,
    // Can be cleared via dedicated UI already
    DraftType.ATTACHMENT,
    DraftType.STICKER -> false
    // Non-standard composer types, non-keyboard users may get lost without clear button
    DraftType.EDIT,
    DraftType.EDIT_CAPTION,
    DraftType.NOTICE,
    DraftType.EMOTE,
    DraftType.REACTION,
    DraftType.CUSTOM_EVENT,
    DraftType.CUSTOM_STATE_EVENT -> true
}

@Composable
private fun BlockedComposer(reason: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(horizontal = Dimens.horizontalItemPaddingBig, vertical = Dimens.listPaddingBig),
        contentAlignment = Alignment.Center,
    ) {
        Text(reason)
    }
}

@Composable
private fun String.appendComposerFormat(draftState: DraftValue): String {
    val host = this
    return buildString {
        append(host)
        append(" (")
        append(
            when (draftState.format) {
                ComposerFormat.PLAIN -> stringResource(Res.string.hint_composer_format_plain)
                ComposerFormat.MARKDOWN -> stringResource(Res.string.hint_composer_format_markdown)
                ComposerFormat.HTML -> stringResource(Res.string.hint_composer_format_html)
            }
        )
        append(")")
    }
}

@Composable
fun RoomPrivacyIndicator(
    composerInfo: ComposerRoomInfo?,
    hintColor: Color,
) {
    val tint = if (hintColor == Color.Unspecified) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        hintColor
    }
    if (composerInfo?.isPublic == true) {
        Icon(
            Icons.Outlined.Public,
            stringResource(Res.string.hint_public_room),
            Modifier.size(12.dp),
            tint = tint,
        )
    } else if (composerInfo?.isEncrypted != true) {
        Icon(
            Icons.Default.NoEncryption,
            stringResource(Res.string.hint_not_encrypted),
            Modifier.size(12.dp),
            tint = tint,
        )
    }
}

@Composable
fun ClearButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = modifier) {
        Icon(
            Icons.Default.Clear,
            stringResource(Res.string.action_clear_reply),
            tint = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
fun formattedMessagePreview(draft: DraftValue): MatrixBodyParseResult {
    val preview = remember { mutableStateOf<MatrixBodyParseResult?>(null) }
    LaunchedEffect(draft.rawBody, draft.format) {
        withContext(Dispatchers.IO) {
            val parser = MessageFormatDefaults.parser
            val parseStyle = MessageFormatDefaults.parseStyle
            val allowRoomMention = draft.hasRoomMention
            val messageContent = when (draft.format) {
                ComposerFormat.HTML -> parser.parseHtml(draft.htmlBody ?: "", parseStyle, allowRoomMention = allowRoomMention)
                ComposerFormat.PLAIN -> parser.parsePlaintext(draft.body, parseStyle, allowRoomMention = allowRoomMention)
                ComposerFormat.MARKDOWN -> {
                    val body = draft.body
                    val html = markdownToHtml(body) ?: body
                    parser.parseHtml(html, parseStyle, allowRoomMention = allowRoomMention)
                }
            }
            preview.value = messageContent
        }
    }
    return preview.value ?: MatrixBodyParseResult(draft.rawBody)
}
