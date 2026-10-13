package chat.schildi.theme

import androidx.compose.material3.DividerDefaults
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.model.DraftTheme

val scl_fgPrimary = ScColors.colorGray_21
val scl_fgSecondary = ScColors.colorBlackAlpha_8a
val scl_fgTertiary = ScColors.colorBlackAlpha_4c
val scl_fgHint = ScColors.colorBlackAlpha_4c
val scl_fgDisabled = ScColors.colorBlackAlpha_4c
val scl_bg = ScColors.colorWhite_fa
val scl_bgFloating = ScColors.colorWhite
val scl_bgDarker = ScColors.colorWhite_fa
val scl_bgBlack = ScColors.colorWhite_ee
val scl_divider = ScColors.colorBlackAlpha_1f
val scl_accent = KiteBrandColors.primary
const val scl_icon_alpha = 0.5f

internal val sclMaterialColorScheme = lightColorScheme(
    primary = scl_fgPrimary,
    onPrimary = scd_fgPrimary,
    primaryContainer = scl_bg,
    onPrimaryContainer = scl_fgPrimary,
    inversePrimary = scl_bg,

    secondary = scl_fgSecondary,
    onSecondary = scd_fgPrimary,
    secondaryContainer = scl_bgBlack,
    onSecondaryContainer = scl_fgSecondary,

    tertiary = scl_fgSecondary,
    onTertiary = scl_fgTertiary,
    tertiaryContainer = scl_bgBlack,
    onTertiaryContainer = scl_fgTertiary,

    background = scl_bg,
    onBackground = scl_fgPrimary,
    surface = scl_bg,
    onSurface = scl_fgPrimary,
    surfaceVariant = scl_bgFloating,
    onSurfaceVariant = scl_fgSecondary,
    surfaceTint = scl_bgFloating,
    inverseSurface = scd_bg,
    inverseOnSurface = scd_fgPrimary,
    surfaceContainerHigh = scl_bgFloating,

    error = ScColors.colorAccentRed,
    onError = scl_fgPrimary,
    errorContainer = ScColors.colorAccentRed,
    onErrorContainer = scl_fgPrimary,
    outline = scl_fgTertiary,
    outlineVariant = scl_divider, // This is the divider color, as per androidx.compose.material3.DividerTokens (propagated to androidx.compose.material3.DividerDefaults.color)
    scrim = ScColors.colorBlackAlpha_1f,
)

internal val sclExposures = ScThemeExposures(
    isDarkTheme = false,
    horizontalDividerThickness = DividerDefaults.Thickness,
    accentColor = scl_accent,
    colorOnAccent = ScColors.colorWhite,
    linkColor = ScColors.colorAccentBlue,
    threadHint = ScColors.colorAccentOrange,
    bubbleBgIncoming = ScColors.colorWhite_ee,
    bubbleBgOutgoing = scl_accent.fakeAlpha(0.12f),
    mentionBadgeColor = Color(0xffd51928),
    notificationBadgeColor = KiteBrandColors.primary,
    unreadBadgeColor = ScColors.colorGray_73,
    unreadBadgeOnToolbarColor = ScColors.colorGray_73,
    appBarBg = scl_bg,
    bubbleRadius = 18.dp,
    commonLayoutRadius = 18.dp,
    timestampRadius = 6.dp,
    timestampOverlayBg = ScColors.colorBlackAlpha_80,
    timestampOverlayFgOnBg = scd_fgSecondary,
    unreadIndicatorLine = KiteBrandColors.primary,
    unreadIndicatorThickness = 2.dp,
    mentionFg = ScColors.colorBlack,
    mentionBg = KiteBrandColors.primary.copy(alpha = 0.50f),
    mentionFgHighlight = ScColors.colorWhite,
    mentionBgHighlight = ScColors.colorAccentRed,
    greenFg = KiteBrandColors.primary,
    greenBg = KiteBrandColors.primary.copy(alpha = 0.13f),
    messageHighlightBg = KiteBrandColors.primary.copy(alpha = 0.50f),
    composerBlockBg = null,
    composerBlockFg = null,
    spaceBarBg = ScColors.colorWhite_ee,
    searchHint = ScColors.colorAccentBlueLight,
    commandHint = ScColors.colorAccentOrange,
    reactHint = KiteBrandColors.primary,
    customEventHint = ScColors.colorAccentBlueDark,
    draftTheme = DraftTheme(
        mentionSpanColor = KiteBrandColors.primary,
        customEmoteSpanColor = ScColors.colorAccentBlueDark,
    )
)
