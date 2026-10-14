package chat.schildi.theme

import androidx.compose.material3.DividerDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.model.DraftTheme

val scd_fgPrimary = ScColors.colorWhite
val scd_fgSecondary = ScColors.colorWhiteAlpha_b3
val scd_fgTertiary = ScColors.colorWhiteAlpha_80
val scd_fgHint = ScColors.colorWhiteAlpha_80
val scd_fgDisabled = ScColors.colorWhiteAlpha_80
val scd_bg = KiteBrandColors.darkContainer
val scd_bgFloating = KiteBrandColors.darkContainerHigh
val scd_bgDarker = KiteBrandColors.darkBackground
val scd_bgBlack = ScColors.colorBlack
val scd_divider = ScColors.colorWhiteAlpha_1f
val scd_accent = KiteBrandColors.primaryDark
const val scd_icon_alpha = 0.5f

internal val scdMaterialColorScheme = darkColorScheme(
    primary = scd_fgPrimary,
    onPrimary = scl_fgPrimary,
    primaryContainer = scd_bgDarker,
    onPrimaryContainer = scd_fgPrimary,
    inversePrimary = scl_fgPrimary,

    secondary = scd_fgSecondary,
    onSecondary = scl_fgPrimary,
    secondaryContainer = scd_bg,
    onSecondaryContainer = scd_fgSecondary,

    tertiary = scd_fgTertiary,
    onTertiary = scl_fgTertiary,
    tertiaryContainer = scd_bgBlack,
    onTertiaryContainer = scd_fgTertiary,

    background = scd_bgDarker,
    onBackground = scd_fgPrimary,
    surface = scd_bgDarker,
    onSurface = scd_fgPrimary,
    surfaceVariant = scd_bg,
    onSurfaceVariant = scd_fgSecondary,
    surfaceTint = scd_bgFloating,
    inverseSurface = scl_bgFloating,
    inverseOnSurface = scl_fgPrimary,
    surfaceContainerHigh = scd_bgFloating,

    error = ScColors.colorAccentRed,
    onError = scd_fgPrimary,
    errorContainer = ScColors.colorAccentRed,
    onErrorContainer = scd_fgPrimary,
    outline = scd_fgTertiary,
    outlineVariant = scd_divider, // This is the divider color, as per androidx.compose.material3.DividerTokens (propagated to androidx.compose.material3.DividerDefaults.color)
    scrim = ScColors.colorBlackAlpha_1f,
)

internal val scdExposures = ScThemeExposures(
    isDarkTheme = true,
    horizontalDividerThickness = DividerDefaults.Thickness,
    accentColor = scd_accent,
    colorOnAccent = ScColors.colorGray_21,
    linkColor = ScColors.colorAccentBlueLight,
    threadHint = ScColors.colorAccentLime,
    bubbleBgIncoming = KiteBrandColors.darkIncomingBubble,
    bubbleBgOutgoing = KiteBrandColors.darkOutgoingBubble,
    mentionBadgeColor = Color(0xffd51928),
    notificationBadgeColor = KiteBrandColors.primaryDark,
    unreadBadgeColor = scd_bgFloating,
    unreadBadgeOnToolbarColor = ScColors.colorGray_61,
    appBarBg = scd_bg,
    bubbleRadius = 18.dp,
    commonLayoutRadius = 18.dp,
    timestampRadius = 6.dp,
    timestampOverlayBg = ScColors.colorBlackAlpha_80,
    timestampOverlayFgOnBg = scd_fgSecondary,
    unreadIndicatorLine = KiteBrandColors.primaryDark,
    unreadIndicatorThickness = 2.dp,
    mentionFg = ScColors.colorWhite,
    mentionBg = KiteBrandColors.primaryDark.copy(alpha = 0.50f),
    mentionFgHighlight = ScColors.colorWhite,
    mentionBgHighlight = ScColors.colorAccentRed,
    greenFg = KiteBrandColors.primaryDark,
    greenBg = KiteBrandColors.primaryDark.copy(alpha = 0.19f),
    messageHighlightBg = KiteBrandColors.primaryDark.copy(alpha = 0.50f),
    composerBlockBg = scd_bgFloating,
    composerBlockFg = scd_fgPrimary,
    spaceBarBg = scd_bg,
    searchHint = ScColors.colorAccentBlueLight,
    commandHint = ScColors.colorAccentOrange,
    reactHint = KiteBrandColors.primaryDark,
    customEventHint = ScColors.colorAccentLime,
    draftTheme = DraftTheme(
        mentionSpanColor = KiteBrandColors.primaryDark,
        customEmoteSpanColor = ScColors.colorAccentLime,
    ),
)
