package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import chat.schildi.revenge.compose.destination.conversation.event.reaction.kiteReactionFace
import chat.schildi.theme.rememberEmojiFontFamily
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalViewConfiguration
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.config.keybindings.Action
import kotlin.uuid.Uuid

private const val DOUBLE_TAP_SLOP_MULTIPLIER = 2f

/**
 * Observes taps without consuming pointer changes.
 *
 * Using Compose's regular double-click recognizer would defer a normal click until the
 * double-tap timeout expires. Kite instead keeps the first tap immediate and only reacts
 * when a second short, nearby tap arrives. Dragging, long-pressing, or multi-touch clears
 * the candidate so this does not compete with scrolling, swipe-to-reply, or context menus.
 */
@Composable
fun Modifier.passiveDoubleTapReaction(
    focusId: Uuid,
    enabled: Boolean,
    reaction: String,
    reactionActive: Boolean,
    singleTapEnabled: Boolean,
    onSingleTap: () -> Unit,
    onBurstActiveChange: (Boolean) -> Unit,
): Modifier {
    if (!enabled && !singleTapEnabled) return this

    val actionHandler = LocalKeyboardActionHandler.current
    val viewConfiguration = LocalViewConfiguration.current
    val haptics = LocalHapticFeedback.current
    val activeReaction by rememberUpdatedState(reactionActive)
    val reactionEnabled by rememberUpdatedState(enabled)
    val tapEnabled by rememberUpdatedState(singleTapEnabled)
    val latestOnSingleTap by rememberUpdatedState(onSingleTap)
    val latestOnBurstActiveChange by rememberUpdatedState(onBurstActiveChange)
    var burstPosition by remember(focusId) { mutableStateOf<Offset?>(null) }
    var burstSerial by remember(focusId) { mutableIntStateOf(0) }
    val burstProgress = remember(focusId) { Animatable(0f) }
    val textMeasurer = rememberTextMeasurer()
    val emojiFont = rememberEmojiFontFamily()
    val reactionLayout = remember(reaction, emojiFont) {
        textMeasurer.measure(AnnotatedString(reaction), style = TextStyle(fontSize = 52.sp, fontFamily = emojiFont))
    }
    val isHeart = reaction == "❤️" || reaction == "❤"
    val heartShape = remember {
        Path().apply {
            moveTo(0f, 27f)
            cubicTo(-10f, 18f, -28f, 5f, -28f, -10f)
            cubicTo(-28f, -29f, -9f, -31f, 0f, -18f)
            cubicTo(9f, -31f, 28f, -29f, 28f, -10f)
            cubicTo(28f, 5f, 10f, 18f, 0f, 27f)
            close()
        }
    }
    LaunchedEffect(burstSerial) {
        if (burstSerial > 0) {
            burstProgress.snapTo(0f)
            burstProgress.animateTo(1f, tween(durationMillis = 540, easing = LinearEasing))
            burstPosition = null
            latestOnBurstActiveChange(false)
        }
    }
    return this.zIndex(if (burstPosition != null) Float.MAX_VALUE else 0f).drawWithContent {
        drawContent()
        val tap = burstPosition ?: return@drawWithContent
        // Keep the burst above the composer boundary even on the bottom message.
        val at = Offset(tap.x, tap.y - 52.dp.toPx())
        val t = burstProgress.value
        val opacity = when {
            t < 0.18f -> t / 0.18f
            t < 0.64f -> 1f
            else -> (1f - t) / 0.36f
        }.coerceIn(0f, 1f)
        val scale = when {
            t < 0.42f -> 0.3f + (1.14f - 0.3f) * (1f - (1f - t / 0.42f) * (1f - t / 0.42f))
            t < 0.67f -> 1.14f - 0.16f * ((t - 0.42f) / 0.25f)
            else -> 0.98f - 0.08f * ((t - 0.67f) / 0.33f)
        }
        val glyphScale = 64.dp.toPx() / 64f * scale
        val liftPx = (4f - 16f * t).dp.toPx()
        withTransform({
            translate(left = at.x, top = at.y + liftPx)
            rotate(degrees = when {
                isHeart -> -4f + 6f * t
                reaction.startsWith("👍") || reaction.startsWith("👎") -> -22f + 32f * t
                kiteReactionFace(reaction) != null -> 12f - 25f * t
                else -> -16f + 24f * t
            })
            scale(scaleX = glyphScale, scaleY = glyphScale, pivot = Offset.Zero)
        }) {
            if (isHeart) {
                drawPath(heartShape, color = Color.Black, alpha = 0.16f * opacity)
                drawPath(heartShape, color = Color(0xFFFF5278), alpha = opacity)
            } else {
                // Text is measured once; the animation only changes its draw transform.
                drawText(
                    textLayoutResult = reactionLayout,
                    topLeft = Offset(-reactionLayout.size.width / 2f, -reactionLayout.size.height / 2f),
                    alpha = opacity,
                )
            }
        }
        if (t < 0.6f) {
            val sparkle = (1f - t / 0.6f).coerceIn(0f, 1f)
            val spread = 15.dp.toPx() * (0.5f + t)
            for (direction in 0..5) {
                val angle = direction * kotlin.math.PI / 3
                drawCircle(
                    color = when {
                        isHeart -> if (direction % 2 == 0) Color(0xFFFF90B0) else Color(0xFFFFD38A)
                        reaction.startsWith("👍") || reaction.startsWith("👎") -> Color(0xFFFFC83D)
                        kiteReactionFace(reaction) != null -> if (direction % 2 == 0) Color(0xFFFFD848) else Color(0xFF69C8F2)
                        else -> if (direction % 2 == 0) Color(0xFF9BD3FF) else Color(0xFFC59BFF)
                    },
                    radius = 2.6.dp.toPx() * sparkle,
                    center = Offset(
                        at.x + kotlin.math.cos(angle).toFloat() * (22.dp.toPx() + spread),
                        at.y + kotlin.math.sin(angle).toFloat() * (22.dp.toPx() + spread),
                    ),
                    alpha = opacity * sparkle,
                )
            }
        }
    }.pointerInput(focusId, reaction, actionHandler, viewConfiguration) {
        val touchSlop = viewConfiguration.touchSlop
        val doubleTapSlop = touchSlop * DOUBLE_TAP_SLOP_MULTIPLIER
        val longPressTimeout = viewConfiguration.longPressTimeoutMillis
        val doubleTapMinTime = viewConfiguration.doubleTapMinTimeMillis
        val doubleTapTimeout = viewConfiguration.doubleTapTimeoutMillis

        awaitPointerEventScope {
            var activePointer: PointerId? = null
            var downPosition: Offset? = null
            var downTime = 0L
            var dragged = false
            var multiTouch = false
            var previousTapTime: Long? = null
            var previousTapPosition: Offset? = null

            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Final)
                for (change in event.changes) {
                    val isDown = change.pressed && !change.previousPressed
                    val isUp = !change.pressed && change.previousPressed

                    if (isDown) {
                        if (activePointer != null) {
                            multiTouch = true
                            dragged = true
                            previousTapTime = null
                            previousTapPosition = null
                        } else {
                            activePointer = change.id
                            downPosition = change.position
                            downTime = change.uptimeMillis
                            dragged = false
                            multiTouch = false
                        }
                        continue
                    }

                    if (change.id != activePointer) continue

                    val startPosition = downPosition
                    if (change.pressed && startPosition != null &&
                        (change.position - startPosition).getDistance() > touchSlop
                    ) {
                        dragged = true
                        previousTapTime = null
                        previousTapPosition = null
                    }

                    if (!isUp) continue

                    val elapsed = change.uptimeMillis - downTime
                    val movement = startPosition?.let {
                        (change.position - it).getDistance()
                    } ?: Float.POSITIVE_INFINITY
                    val isShortTap = !dragged &&
                            !multiTouch &&
                            elapsed >= 0L &&
                            elapsed < longPressTimeout &&
                            movement <= touchSlop

                    if (isShortTap) {
                        val priorTime = previousTapTime
                        val priorPosition = previousTapPosition
                        val interval = priorTime?.let { change.uptimeMillis - it }
                        val closeEnough = priorPosition != null &&
                                (change.position - priorPosition).getDistance() <= doubleTapSlop
                        if (reactionEnabled && interval != null &&
                            interval >= doubleTapMinTime &&
                            interval <= doubleTapTimeout &&
                            closeEnough
                        ) {
                            previousTapTime = null
                            previousTapPosition = null
                            if (!activeReaction) {
                                burstPosition = change.position
                                latestOnBurstActiveChange(true)
                                burstSerial++
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            } else {
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            }
                            actionHandler.handleAction(
                                focusId,
                                Action.Event.ToggleReactionKey,
                                listOf(reaction),
                            )
                        } else {
                            if (tapEnabled) latestOnSingleTap()
                            previousTapTime = change.uptimeMillis
                            previousTapPosition = change.position
                        }
                    } else {
                        previousTapTime = null
                        previousTapPosition = null
                    }

                    activePointer = null
                    downPosition = null
                    dragged = false
                    multiTouch = false
                }
            }
        }
    }
}
