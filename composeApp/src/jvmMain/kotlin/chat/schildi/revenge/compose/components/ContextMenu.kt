package chat.schildi.revenge.compose.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.RocketLaunch
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuItemColors
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.window.PopupProperties
import chat.schildi.revenge.Dimens
import chat.schildi.revenge.actions.ActionContext
import chat.schildi.revenge.actions.ActionResult
import chat.schildi.revenge.actions.InteractionAction
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.resources.ComposableStringHolder
import chat.schildi.resources.toStringHolder
import chat.schildi.revenge.config.keybindings.Action
import chat.schildi.revenge.config.keybindings.displayName
import chat.schildi.revenge.compose.destination.conversation.event.reaction.KiteReactionGlyph
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import shire.res.generated.resources.Res
import shire.res.generated.resources.action_enter_command_mode
import kotlin.uuid.Uuid

sealed interface ContextMenuEntry {
    val title: ComposableStringHolder
    val icon: Painter?
    val decoration: ContextMenuDecoration?
    val keyboardShortcut: Key?
    val critical: Boolean
    val enabled: Boolean
    val autoCloseMenu: Boolean
    val dismissParentsOnAutoClose: Boolean
}

sealed interface ContextMenuDecoration {
    data class Toggle(val checked: Boolean) : ContextMenuDecoration
    data object CheckMark : ContextMenuDecoration
    data object DisabledCheckMark : ContextMenuDecoration
}

enum class ContextMenuPresentation {
    Default,
    Message,
}

private enum class ContextMenuOpenState {
    Closed,
    Open,
    ChildOpen,
}

data class ContextMenuActionEntry(
    override val title: ComposableStringHolder,
    override val icon: Painter? = null,
    val action: Action,
    val actionArgs: ImmutableList<String> = persistentListOf(),
    override val decoration: ContextMenuDecoration? = null,
    override val keyboardShortcut: Key? = null,
    override val critical: Boolean = false,
    override val enabled: Boolean = true,
    override val autoCloseMenu: Boolean = decoration == null,
    override val dismissParentsOnAutoClose: Boolean = false,
    val compactLabel: String? = null,
) : ContextMenuEntry

data class ContextMenuActionRowEntry(
    override val title: ComposableStringHolder,
    val actions: ImmutableList<ContextMenuActionEntry>,
    val showTitle: Boolean = true,
    override val icon: Painter? = null,
    override val decoration: ContextMenuDecoration? = null,
    override val keyboardShortcut: Key? = null,
    override val critical: Boolean = false,
    override val enabled: Boolean = true,
) : ContextMenuEntry {
    override val autoCloseMenu = false
    override val dismissParentsOnAutoClose = false
}

data class ContextMenuCallbackEntry(
    override val title: ComposableStringHolder,
    override val icon: Painter? = null,
    val action: suspend (ActionContext) -> ActionResult,
    override val decoration: ContextMenuDecoration? = null,
    override val keyboardShortcut: Key? = null,
    override val critical: Boolean = false,
    override val enabled: Boolean = true,
    override val autoCloseMenu: Boolean = decoration == null,
    override val dismissParentsOnAutoClose: Boolean = false,
) : ContextMenuEntry

data class ContextMenuSubmenuEntry(
    override val title: ComposableStringHolder,
    override val icon: Painter? = null,
    val submenuId: Uuid,
    val submenu: ImmutableList<ContextMenuEntry>,
    override val decoration: ContextMenuDecoration? = null,
    override val keyboardShortcut: Key? = null,
    override val critical: Boolean = false,
    override val enabled: Boolean = true,
) : ContextMenuEntry {
    override val autoCloseMenu = false
    override val dismissParentsOnAutoClose: Boolean = false
}

/**
 * @param focusId: The focus ID of the keyFocusable to operate the action on.
 * @param menuId: The ID of the menu, should be equal to [focusId] except for submenus.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WithContextMenu(
    focusId: Uuid,
    popupContent: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
    menuId: Uuid = focusId,
    presentation: ContextMenuPresentation = ContextMenuPresentation.Default,
    onOpen: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    // Do not recompose every visible message whenever some other row opens/closes a
    // context menu. Each row observes only whether its own menu state changed.
    val currentMenuState = keyHandler.currentOpenContextMenu.collectAsState()
    val menuOpenState by remember(keyHandler, menuId) {
        derivedStateOf {
            val currentMenu = currentMenuState.value
            when {
                currentMenu?.hasMenu(menuId) != true -> ContextMenuOpenState.Closed
                currentMenu.menuId != menuId -> ContextMenuOpenState.ChildOpen
                else -> ContextMenuOpenState.Open
            }
        }
    }
    val expanded = menuOpenState != ContextMenuOpenState.Closed
    val hasChild = menuOpenState == ContextMenuOpenState.ChildOpen
    val wasExpanded = remember(menuId) { booleanArrayOf(false) }
    if (expanded && !wasExpanded[0]) onOpen?.invoke()
    wasExpanded[0] = expanded

    // Window bounds change continuously while the timeline scrolls. They are only
    // needed at menu-open time, so keep the latest value outside snapshot state;
    // otherwise onGloballyPositioned invalidates every visible message every frame.
    val anchorBounds = remember { arrayOfNulls<Rect>(1) }
    // Capture the touch position before the popup's first frame. Updating it from
    // a LaunchedEffect makes the menu appear at zero offset and then jump.
    val pointerPositionOnOpen = remember(expanded) {
        keyHandler.lastPointerPosition.takeIf { expanded }
    }
    val density = LocalDensity.current

    val containerColor = when {
        presentation == ContextMenuPresentation.Message -> MaterialTheme.colorScheme.surface
        hasChild -> MaterialTheme.colorScheme.surfaceContainerLow
        else -> MaterialTheme.colorScheme.surfaceContainerHighest
    }

    val offset = remember(pointerPositionOnOpen, expanded) {
        val anchor = anchorBounds[0]
        val position = pointerPositionOnOpen
        if (anchor == null || position == null) {
            DpOffset(0.dp, 0.dp)
        } else {
            val localX = (position.x - anchor.left).coerceAtLeast(0f)
            with(density) {
                DpOffset(localX.toDp(), 0.dp)
            }
        }
    }

    Box(
        modifier.onGloballyPositioned {
            anchorBounds[0] = it.boundsInWindow()
        }
    ) {
        // If we have selectable text, want to override that menu as well
        // TODO teach that menu some copy-selection item to replicate platform menu's functionality?
        WithPlatformTextContextMenuDisabled {
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { keyHandler.dismissContextMenu(menuId) },
                containerColor = if (presentation == ContextMenuPresentation.Message) Color.Transparent else containerColor,
                tonalElevation = 0.dp,
                shadowElevation = if (presentation == ContextMenuPresentation.Message) 0.dp else 8.dp,
                offset = if (presentation == ContextMenuPresentation.Default) {
                    DpOffset(offset.x - 12.dp, offset.y)
                } else {
                    offset
                },
                shape = if (presentation == ContextMenuPresentation.Message) {
                    MaterialTheme.shapes.extraLarge
                } else {
                    MaterialTheme.shapes.large
                },
                // Message actions intentionally stay non-focusable. Current Google Messages
                // keeps the floating action surface visible while a second long-press lands
                // on the message text for precise selection. A focusable popup consumes that
                // second gesture before SelectionContainer can see it.
                properties = PopupProperties(
                    focusable = presentation != ContextMenuPresentation.Message || messageContextMenuFocusable,
                ),
                content = popupContent,
            )
            if (presentation == ContextMenuPresentation.Message) {
                CompositionLocalProvider(
                    LocalTouchTextSelectionEnabled provides expanded,
                    content = content,
                )
            } else {
                content()
            }
        }
    }
}

/**
 * @param focusId: The focus ID of the keyFocusable to operate the action on.
 * @param menuId: The ID of the menu, should be equal to [focusId] except for submenus.
 * @param parentMenuId: the menuId of the parent menu in case of submenus.
 */
@Composable
fun WithContextMenu(
    focusId: Uuid,
    entries: ImmutableList<ContextMenuEntry>,
    modifier: Modifier = Modifier,
    menuId: Uuid = focusId,
    parentMenuId: Uuid? = null,
    presentation: ContextMenuPresentation = ContextMenuPresentation.Default,
    messageTimestamp: String? = null,
    onComposeReaction: (() -> Unit)? = null,
    content: @Composable (InteractionAction.ContextMenu?) -> Unit,
) {
    val keyHandler = LocalKeyboardActionHandler.current
    // Matrix updates can arrive before the dropdown exit animation finishes.
    // Hold the displayed labels/actions until the next menu opening.
    val openedEntries = remember(menuId) { arrayOfNulls<ImmutableList<ContextMenuEntry>>(1) }
    WithContextMenu(
        focusId = focusId,
        menuId = menuId,
        modifier = modifier,
        presentation = presentation,
        onOpen = { openedEntries[0] = entries },
        content = {
            content(
                if (entries.isEmpty())
                    null
                else
                    InteractionAction.ContextMenu(focusId, entries, menuId, parentMenuId)
            )
        },
        popupContent = {
            val shownEntries = if (presentation == ContextMenuPresentation.Message) entries else openedEntries[0] ?: entries
            if (presentation == ContextMenuPresentation.Message) {
                val actionRows = shownEntries.filterIsInstance<ContextMenuActionRowEntry>()
                val menuEntries = shownEntries.filterNot { it is ContextMenuActionRowEntry }

                if (actionRows.isNotEmpty()) {
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.extraLarge,
                        modifier = Modifier.padding(end = 12.dp, bottom = 6.dp),
                    ) {
                        actionRows.forEach { entry ->
                            ContextMenuDropdownMenuItem(
                                entry = entry,
                                focusId = focusId,
                                menuId = menuId,
                                presentation = presentation,
                                onClick = { keyHandler.handleContextMenuEntry(focusId, menuId, entry) },
                                onComposeReaction = onComposeReaction,
                            )
                        }
                    }
                }
                if (menuEntries.isNotEmpty() || messageTimestamp != null) {
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = MaterialTheme.shapes.extraLarge,
                        modifier = Modifier.width(192.dp),
                    ) {
                        Column(Modifier.padding(vertical = 4.dp)) {
                            if (messageTimestamp != null) {
                                Text(
                                    text = messageTimestamp,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                                )
                            }
                            menuEntries.forEach { entry ->
                                ContextMenuDropdownMenuItem(
                                    entry = entry,
                                    focusId = focusId,
                                    menuId = menuId,
                                    presentation = presentation,
                                    modifier = Modifier.height(48.dp),
                                    onClick = { keyHandler.handleContextMenuEntry(focusId, menuId, entry) },
                                )
                            }
                        }
                    }
                }
            } else {
                shownEntries.forEach { entry ->
                    ContextMenuDropdownMenuItem(
                        entry = entry,
                        focusId = focusId,
                        menuId = menuId,
                        presentation = presentation,
                        onClick = {
                            keyHandler.handleContextMenuEntry(focusId, menuId, entry)
                        },
                    )
                }
            }
        }
    )
}

// Re-usable action for command mode
@Composable
fun enterCommandModeContextMenuAction() = ContextMenuActionEntry(
    Res.string.action_enter_command_mode.toStringHolder(),
    rememberVectorPainter(Icons.Default.RocketLaunch),
    Action.Global.Command,
)

@Composable
private fun ContextMenuDropdownMenuItem(
    entry: ContextMenuEntry,
    focusId: Uuid,
    menuId: Uuid,
    presentation: ContextMenuPresentation,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onComposeReaction: (() -> Unit)? = null,
) {
    when (entry) {
        is ContextMenuActionRowEntry -> {
            val keyHandler = LocalKeyboardActionHandler.current
            ContextMenuActionRowContent(
                entry = entry,
                onActionClick = { action ->
                    if (action.action == Action.Event.ComposeReaction && onComposeReaction != null) {
                        keyHandler.dismissContextMenu(menuId)
                        onComposeReaction()
                    } else {
                        keyHandler.handleContextMenuEntry(focusId, menuId, action)
                    }
                },
                modifier = modifier,
                presentation = presentation,
            )
        }
        is ContextMenuSubmenuEntry -> {
            WithContextMenu(
                focusId = focusId,
                menuId = entry.submenuId,
                parentMenuId = menuId,
                entries = entry.submenu,
                modifier = modifier,
                presentation = presentation,
            ) {
                ContextMenuDropdownMenuItemContent(
                    entry = entry,
                    onClick = onClick,
                )
            }
        }
        else -> {
            ContextMenuDropdownMenuItemContent(
                entry = entry,
                onClick = onClick,
                modifier = modifier,
            )
        }
    }
}

@Composable
private fun ContextMenuActionRowContent(
    entry: ContextMenuActionRowEntry,
    onActionClick: (ContextMenuActionEntry) -> Unit,
    modifier: Modifier = Modifier,
    presentation: ContextMenuPresentation = ContextMenuPresentation.Default,
) {
    val labelColor = if (entry.enabled) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        MaterialTheme.colorScheme.tertiary
    }
    val compactMessageSurface = presentation == ContextMenuPresentation.Message
    Column(
        modifier = modifier.padding(
                horizontal = if (compactMessageSurface) 4.dp else 12.dp,
                vertical = if (compactMessageSurface) 2.dp else 10.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(if (compactMessageSurface) 2.dp else 8.dp),
    ) {
        if (entry.showTitle) {
            Text(
                text = entry.title.render(),
                color = labelColor,
                style = MaterialTheme.typography.labelLarge,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(if (compactMessageSurface) 2.dp else 8.dp)) {
            entry.actions.forEach { action ->
                val actionTitle = action.title.render()
                val selected = when (val decoration = action.decoration) {
                    is ContextMenuDecoration.Toggle -> decoration.checked
                    is ContextMenuDecoration.CheckMark -> true
                    else -> false
                }
                Surface(
                    onClick = { onActionClick(action) },
                    enabled = entry.enabled && action.enabled,
                    modifier = Modifier
                        .size(if (compactMessageSurface) 44.dp else 52.dp)
                        .semantics {
                            contentDescription = actionTitle
                            this.selected = selected
                        },
                    shape = if (compactMessageSurface) CircleShape else MaterialTheme.shapes.extraLarge,
                    color = if (selected) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else if (compactMessageSurface) {
                        Color.Transparent
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHighest
                    },
                    contentColor = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        val compactLabel = action.compactLabel
                        when {
                            compactLabel != null -> KiteReactionGlyph(
                                reaction = compactLabel,
                                size = 24.dp,
                                modifier = Modifier.clearAndSetSemantics { },
                            )
                            action.icon != null -> Icon(
                                painter = action.icon,
                                contentDescription = null,
                                modifier = Modifier
                                    .size(24.dp)
                                    .clearAndSetSemantics { },
                            )
                            else -> Text(
                                text = actionTitle,
                                modifier = Modifier.clearAndSetSemantics { },
                                fontSize = 22.sp,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ContextMenuDropdownMenuItemContent(
    entry: ContextMenuEntry,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val keyboardShortcutsEnabled = LocalKeyboardActionHandler.current.keyboardPrimary.collectAsState().value
    val textColor = MaterialTheme.colorScheme.onSurface
    val iconColor = if (entry.critical) {
        MaterialTheme.colorScheme.error
    } else {
        textColor
    }
    DropdownMenuItem(
        modifier = modifier,
        enabled = entry.enabled,
        colors = MenuItemColors(
            textColor = textColor,
            leadingIconColor = iconColor,
            trailingIconColor = textColor,
            disabledTextColor = MaterialTheme.colorScheme.tertiary,
            disabledLeadingIconColor = MaterialTheme.colorScheme.tertiary,
            disabledTrailingIconColor = MaterialTheme.colorScheme.tertiary,
        ),
        leadingIcon = entry.icon?.let { icon -> {
            Icon(
                icon,
                null,
                Modifier.size(24.dp)
            )
        }},
        trailingIcon = when (val decoration = entry.decoration) {
            is ContextMenuDecoration.Toggle -> {
                {
                    Switch(
                        enabled = entry.enabled,
                        checked = decoration.checked,
                        onCheckedChange = null,
                    )
                }
            }
            is ContextMenuDecoration.CheckMark -> {
                {
                    Icon(
                        Icons.Default.Check,
                        null,
                    )
                }
            }
            is ContextMenuDecoration.DisabledCheckMark -> {
                {
                    Icon(
                        Icons.Default.Check,
                        null,
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = Dimens.fgDisabledAlpha),
                    )
                }
            }
            null -> {{}}
        },
        text = {
            val title = entry.title.render()
            val text = remember(entry, title, keyboardShortcutsEnabled) {
                val keyboardShortcut = entry.keyboardShortcut
                if (keyboardShortcut == null || !keyboardShortcutsEnabled) {
                    AnnotatedString(title)
                } else {
                    val keyText = keyboardShortcut.displayName().lowercase()
                    val keyIndex = title.lowercase().indexOf(keyText)
                    buildAnnotatedString {
                        append(title)
                        if (keyIndex >= 0) {
                            addStyle(
                                SpanStyle(textDecoration = TextDecoration.Underline),
                                keyIndex,
                                keyIndex + 1,
                            )
                        } else {
                            append(" (")
                            withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                                append(keyText)
                            }
                            append(")")
                        }
                    }
                }
            }
            Text(text)
        },
        onClick = onClick,
    )
}

fun Int.keyboardShortcutFromIndexZero() = when (this) {
    0 -> Key.Zero
    1 -> Key.One
    2 -> Key.Two
    3 -> Key.Three
    4 -> Key.Four
    5 -> Key.Five
    6 -> Key.Six
    7 -> Key.Seven
    8 -> Key.Eight
    9 -> Key.Nine
    10 -> Key.A
    11 -> Key.B
    12 -> Key.C
    13 -> Key.D
    14 -> Key.E
    15 -> Key.F
    16 -> Key.G
    17 -> Key.H
    18 -> Key.I
    19 -> Key.J
    20 -> Key.K
    21 -> Key.L
    22 -> Key.M
    23 -> Key.N
    24 -> Key.O
    25 -> Key.P
    26 -> Key.Q
    27 -> Key.R
    28 -> Key.S
    29 -> Key.T
    30 -> Key.U
    31 -> Key.V
    32 -> Key.W
    33 -> Key.X
    34 -> Key.Y
    35 -> Key.Z
    else -> null
}

fun Int.keyboardShortcutFromIndex() = inc().keyboardShortcutFromIndexZero()
