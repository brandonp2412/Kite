package chat.schildi.revenge.compose.destination.verification

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.DateTimeFormat
import chat.schildi.revenge.Destination
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.LocalDestinationState
import chat.schildi.revenge.actions.FocusRole
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.actions.LocalListActionProvider
import chat.schildi.revenge.actions.actionProvider
import chat.schildi.revenge.actions.plainTextCopyAction
import chat.schildi.revenge.actions.plainTextCopyActionWithMxcUrl
import chat.schildi.revenge.actions.rememberListActions
import chat.schildi.revenge.compose.components.AvatarImage
import chat.schildi.revenge.compose.components.TopNavigation
import chat.schildi.revenge.compose.components.TopNavigationCloseOrNavigateToInboxIcon
import chat.schildi.revenge.compose.components.TopNavigationTitle
import chat.schildi.revenge.compose.focus.FocusContainer
import chat.schildi.revenge.compose.focus.keyFocusable
import chat.schildi.revenge.model.verification.ScIncomingVerificationRequest
import chat.schildi.revenge.model.verification.ScOutgoingVerificationRequest
import chat.schildi.revenge.model.verification.ScVerificationRequest
import chat.schildi.revenge.model.verification.VerificationRequestViewModel
import chat.schildi.revenge.model.verification.toEmojiResource
import chat.schildi.revenge.publishTitle
import chat.schildi.revenge.viewModelKey
import io.element.android.libraries.matrix.api.media.MediaSource
import io.element.android.libraries.matrix.api.verification.SessionVerificationData
import io.element.android.libraries.matrix.api.verification.VerificationEmoji
import io.element.android.libraries.matrix.api.verification.VerificationFlowState
import io.element.android.libraries.matrix.api.verification.VerificationRequest
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_accept
import shire.res.generated.resources.action_cancel
import shire.res.generated.resources.action_decline
import shire.res.generated.resources.action_done
import shire.res.generated.resources.action_start_emoji_verification
import shire.res.generated.resources.action_verification_match
import shire.res.generated.resources.action_verification_mismatch
import shire.res.generated.resources.verification_cancelled
import shire.res.generated.resources.verification_compare_decimals_match
import shire.res.generated.resources.verification_compare_emoji_match
import shire.res.generated.resources.verification_device_details_device_id
import shire.res.generated.resources.verification_device_details_device_name
import shire.res.generated.resources.verification_device_details_flow_id
import shire.res.generated.resources.verification_device_details_own_device_id
import shire.res.generated.resources.verification_device_details_user_id
import shire.res.generated.resources.verification_device_first_seen
import shire.res.generated.resources.verification_device_header_type_other_user
import shire.res.generated.resources.verification_device_header_type_self
import shire.res.generated.resources.verification_failed
import shire.res.generated.resources.verification_no_active_request
import shire.res.generated.resources.verification_request_title
import shire.res.generated.resources.verification_successful

@Composable
fun VerificationRequestScreen(
    destination: Destination.VerificationRequest,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
) {
    val viewModel: VerificationRequestViewModel = viewModel(
        key = viewModelKey(destination, allowShare = true),
        factory = viewModelFactory { initializer { VerificationRequestViewModel(destination.sessionId) } },
    )
    publishTitle(viewModel)

    DisposableEffect(viewModel) {
        viewModel.registerRenderer()
        onDispose {
            viewModel.unregisterRenderer()
        }
    }

    val verificationFlowState = viewModel.verificationFlowState.collectAsState().value
    val listState = rememberLazyListState()
    val listAction = rememberListActions(listState)
    FocusContainer(
        LocalListActionProvider provides listAction,
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
            )
            .fillMaxSize(),
        role = FocusRole.DESTINATION_ROOT_CONTAINER,
    ) {
        Column(Modifier.fillMaxSize()) {
            TopNavigation {
                TopNavigationCloseOrNavigateToInboxIcon(backStyle = true)
                TopNavigationTitle(stringResource(Res.string.verification_request_title))
            }
            Surface(
                modifier = contentModifier.fillMaxSize(),
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    val request = viewModel.activeVerificationRequest.collectAsState().value
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize().padding(Dimens.windowPadding),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = WindowInsets.navigationBars
                            .only(WindowInsetsSides.Bottom)
                            .asPaddingValues(),
                    ) {
                        if (request == null) {
                            item(key = "no_request", contentType = "verification") {
                                VerificationNoActiveRequestContent(viewModel)
                            }
                        } else {
                            when (verificationFlowState) {
                                VerificationFlowState.Initial -> item(key = "initial", contentType = "verification") {
                                    VerificationInitialContent(request, viewModel)
                                }
                                VerificationFlowState.DidAcceptVerificationRequest -> item(key = "accepted", contentType = "verification") {
                                    VerificationAcceptedContent(request, viewModel)
                                }
                                VerificationFlowState.DidStartSasVerification -> item(key = "sas_started", contentType = "verification") {
                                    VerificationSasStartedContent(request, viewModel)
                                }
                                is VerificationFlowState.DidReceiveVerificationData -> item(key = "data", contentType = "verification") {
                                    VerificationDataContent(verificationFlowState, request, viewModel)
                                }
                                VerificationFlowState.DidFinish -> item(key = "finished", contentType = "verification") {
                                    VerificationFinishedContent(request, viewModel)
                                }
                                VerificationFlowState.DidCancel -> item(key = "cancelled", contentType = "verification") {
                                    VerificationCancelledContent(request, viewModel)
                                }
                                VerificationFlowState.DidFail -> item(key = "failed", contentType = "verification") {
                                    VerificationFailedContent(request, viewModel)
                                }
                                null -> item(key = "idle", contentType = "verification") {
                                    VerificationNoActiveRequestContent(viewModel)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VerificationMetadataInfo(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
    modifier: Modifier = Modifier,
) {
    VerificationCard(modifier) {
        when (request) {
            is ScIncomingVerificationRequest ->
                IncomingVerificationMetadataInfo(request, viewModel, Modifier.fillMaxWidth())
            is ScOutgoingVerificationRequest ->
                OutgoingVerificationMetadataInfo(request, viewModel, Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun OutgoingVerificationMetadataInfo(
    request: ScOutgoingVerificationRequest,
    viewModel: VerificationRequestViewModel,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Dimens.verticalArrangement) {
        Text(
            when (request.request) {
                is VerificationRequest.Outgoing.CurrentSession -> stringResource(Res.string.verification_device_header_type_self)
                is VerificationRequest.Outgoing.User -> stringResource(Res.string.verification_device_header_type_other_user)
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
        )

        val userId = when (request.request) {
            is VerificationRequest.Outgoing.CurrentSession -> request.sessionId
            is VerificationRequest.Outgoing.User -> request.request.userId
        }
        VerificationMetadataInfoRow(
            stringResource(Res.string.verification_device_details_user_id),
            userId.value,
        )
        if (ScPrefs.SHOW_DEV_INFOS.value()) {
            VerificationMetadataInfoRow(
                stringResource(Res.string.verification_device_details_own_device_id),
                viewModel.ownDeviceId.collectAsState().value?.value.toString(),
            )
        }
    }
}

@Composable
private fun IncomingVerificationMetadataInfo(
    request: ScIncomingVerificationRequest,
    viewModel: VerificationRequestViewModel,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Dimens.verticalArrangement) {
        Text(
            when (request.request) {
                is VerificationRequest.Incoming.OtherSession -> stringResource(Res.string.verification_device_header_type_self)
                is VerificationRequest.Incoming.User -> stringResource(Res.string.verification_device_header_type_other_user)
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
        )

        val details = request.request.details
        if (details.senderProfile.userId != request.sessionId) {
            details.senderProfile.avatarUrl?.let { avatarUrl ->
                AvatarImage(
                    source = MediaSource(avatarUrl),
                    size = 88.dp,
                    displayName = details.senderProfile.displayName ?: details.senderProfile.userId.value,
                    shape = CircleShape,
                    modifier = Modifier.keyFocusable(
                        role = FocusRole.LIST_ITEM,
                        actionProvider = actionProvider(
                            copyActions = plainTextCopyActionWithMxcUrl(avatarUrl),
                        )
                    ),
                    allowAnimated = true,
                )
            }
        }
        VerificationMetadataInfoRow(
            stringResource(Res.string.verification_device_details_user_id),
            details.senderProfile.userId.value,
        )
        VerificationMetadataInfoRow(
            stringResource(Res.string.verification_device_details_device_name),
            details.deviceDisplayName,
        )
        if (ScPrefs.SHOW_DEV_INFOS.value()) {
            VerificationMetadataInfoRow(
                stringResource(Res.string.verification_device_details_device_id),
                details.deviceId.value,
            )
            VerificationMetadataInfoRow(
                stringResource(Res.string.verification_device_details_own_device_id),
                viewModel.ownDeviceId.collectAsState().value?.value.toString(),
            )
            VerificationMetadataInfoRow(
                stringResource(Res.string.verification_device_details_flow_id),
                details.flowId.value,
            )
        }
        VerificationMetadataInfoRow(
            stringResource(Res.string.verification_device_first_seen),
            DateTimeFormat.formatTimeOrDateTime(details.firstSeenTimestamp),
        )
    }
}

@Composable
private fun VerificationMetadataInfoRow(
    title: String,
    value: String?,
    modifier: Modifier = Modifier,
) {
    value ?: return
    Column(
        modifier
            .fillMaxWidth()
            .keyFocusable(
                role = FocusRole.LIST_ITEM,
                actionProvider = actionProvider(
                    copyActions = plainTextCopyAction { value },
                )
            ),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            title,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelMedium,
        )
        Text(
            value,
            color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

@Composable
private fun VerificationStateText(
    text: String,
    critical: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .keyFocusable(
                role = FocusRole.LIST_ITEM,
                actionProvider = actionProvider(
                    copyActions = plainTextCopyAction { text },
                ),
            ),
        shape = RoundedCornerShape(20.dp),
        color = if (critical) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerHigh
        },
        tonalElevation = 0.dp,
    ) {
        Text(
            text,
            color = if (critical) {
                MaterialTheme.colorScheme.onErrorContainer
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 20.dp),
        )
    }
}

@Composable
private fun VerificationButton(
    text: String,
    modifier: Modifier = Modifier,
    critical: Boolean = false,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        colors = if (critical)
            ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor = MaterialTheme.colorScheme.onErrorContainer,
            )
        else
            ButtonDefaults.buttonColors(),
        shape = RoundedCornerShape(28.dp),
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .keyFocusable(
                role = FocusRole.LIST_ITEM,
                actionProvider = actionProvider(
                    primaryAction = InteractionAction.Invoke {
                        onClick()
                        true
                    },
                ),
                addClickListener = false,
            ),
    ) {
        Text(text)
    }
}

@Composable
private fun VerificationLoadingIndicator(modifier: Modifier = Modifier) {
    VerificationCard(modifier) {
        Box(
            Modifier.fillMaxWidth().padding(vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
    }
}

@Composable
private fun VerificationButtonSection(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}



@Composable
private fun VerificationCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content,
        )
    }
}

@Composable
private fun VerificationNoActiveRequestContent(
    viewModel: VerificationRequestViewModel,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    val destinationState = LocalDestinationState.current
    VerificationStateText(stringResource(Res.string.verification_no_active_request, viewModel.sessionId))
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_done)) {
            destinationState?.closeScreen(keyHandler)
        }
    }
}

@Composable
private fun VerificationInitialContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    VerificationMetadataInfo(request, viewModel)
    VerificationButtonSection {
        when (request.request) {
            is VerificationRequest.Incoming -> {
                VerificationButton(stringResource(Res.string.action_accept)) {
                    viewModel.acceptVerificationRequest()
                }
                VerificationButton(stringResource(Res.string.action_decline)) {
                    viewModel.cancelVerification()
                }
            }
            is VerificationRequest.Outgoing -> {
                VerificationButton(stringResource(Res.string.action_cancel)) {
                    viewModel.cancelVerification()
                }
            }
        }
    }
}

@Composable
private fun VerificationAcceptedContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    VerificationMetadataInfo(request, viewModel)
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_start_emoji_verification)) {
            viewModel.startSasVerification()
        }
        VerificationButton(stringResource(Res.string.action_cancel)) {
            viewModel.cancelVerification()
        }
    }
}

@Composable
private fun VerificationSasStartedContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    VerificationMetadataInfo(request, viewModel)
    VerificationLoadingIndicator()
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_cancel)) {
            viewModel.cancelVerification()
        }
    }
}

@Composable
private fun VerificationDataContent(
    state: VerificationFlowState.DidReceiveVerificationData,
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    VerificationMetadataInfo(request, viewModel)
    val stateText = when (state.data) {
        is SessionVerificationData.Emojis -> stringResource(Res.string.verification_compare_emoji_match)
        is SessionVerificationData.Decimals -> stringResource(Res.string.verification_compare_decimals_match)
    }
    VerificationStateText(stateText)
    when (val data = state.data) {
        is SessionVerificationData.Emojis -> VerificationDataEmojiContent(data, Modifier.fillMaxWidth())
        is SessionVerificationData.Decimals -> VerificationStateText(data.decimals.joinToString())
    }
    val hasApproved = viewModel.pendingApproveAck.collectAsState().value
    if (hasApproved) {
        VerificationLoadingIndicator()
    }
    VerificationButtonSection {
        if (!hasApproved) {
            VerificationButton(stringResource(Res.string.action_verification_match)) {
                viewModel.approveVerification()
            }
            VerificationButton(stringResource(Res.string.action_verification_mismatch), critical = true) {
                viewModel.declineVerification()
            }
        } else {
            VerificationButton(stringResource(Res.string.action_cancel)) {
                viewModel.cancelVerification()
            }
        }
    }
}

@Composable
private fun VerificationDataEmojiContent(
    data: SessionVerificationData.Emojis,
    modifier: Modifier = Modifier,
) {
    FlowRow(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        itemVerticalAlignment = Alignment.Top,
    ) {
        data.emojis.forEach { emoji ->
            VerificationEmojiContent(emoji)
        }
    }
}

@Composable
private fun VerificationEmojiContent(
    emoji: VerificationEmoji,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val resource = emoji.number.toEmojiResource()
            Image(
                painterResource(resource.drawableRes),
                stringResource(resource.nameRes),
                modifier = Modifier.size(56.dp),
            )
            Text(
                stringResource(resource.nameRes),
                color = MaterialTheme.colorScheme.onSecondaryContainer,
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
}

@Composable
private fun VerificationFinishedContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    val destinationState = LocalDestinationState.current
    VerificationStateText(stringResource(Res.string.verification_successful))
    VerificationMetadataInfo(request, viewModel)
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_done)) {
            destinationState?.closeScreen(keyHandler)
        }
    }
}

@Composable
private fun VerificationCancelledContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    val destinationState = LocalDestinationState.current
    VerificationStateText(stringResource(Res.string.verification_cancelled), critical = true)
    VerificationMetadataInfo(request, viewModel)
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_done)) {
            destinationState?.closeScreen(keyHandler)
        }
    }
}

@Composable
private fun VerificationFailedContent(
    request: ScVerificationRequest,
    viewModel: VerificationRequestViewModel,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    val destinationState = LocalDestinationState.current
    VerificationStateText(stringResource(Res.string.verification_failed), critical = true)
    VerificationMetadataInfo(request, viewModel)
    VerificationButtonSection {
        VerificationButton(stringResource(Res.string.action_done)) {
            destinationState?.closeScreen(keyHandler)
        }
    }
}
