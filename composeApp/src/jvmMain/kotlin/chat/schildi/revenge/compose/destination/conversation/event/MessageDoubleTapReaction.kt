package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.withTransform
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

/** Holds only the short-lived heart burst; it never affects a timeline row's size. */
internal class HeartBurstState {
    var position by mutableStateOf<Offset?>(null)
        private set
    var serial by mutableIntStateOf(0)
        private set

    private var viewport: LayoutCoordinates? = null

    fun updateViewport(coordinates: LayoutCoordinates) { viewport = coordinates }

    fun trigger(tap: Offset, messageCoordinates: LayoutCoordinates) {
        val viewportCoordinates = viewport?.takeIf { it.isAttached } ?: return
        if (!messageCoordinates.isAttached) return
        position = viewportCoordinates.localPositionOf(messageCoordinates, tap)
        serial++
    }

    fun clear() { position = null }
}

internal val LocalHeartBurstState = staticCompositionLocalOf<HeartBurstState?> { null }

@Composable
internal fun rememberHeartBurstState() = remember { HeartBurstState() }

// Draw above the LazyColumn, so neither the short message nor its lazy item clips the burst.
@Composable
internal fun Modifier.drawHeartBurst(state: HeartBurstState): Modifier {
    val burstProgress = remember { Animatable(0f) }
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
    LaunchedEffect(state.serial) {
        if (state.serial > 0) {
            burstProgress.snapTo(0f)
            burstProgress.animateTo(1f, tween(durationMillis = 540, easing = LinearEasing))
            state.clear()
        }
    }
    return drawWithContent {
        drawContent()
        val at = state.position ?: return@drawWithContent
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
            rotate(degrees = -4f + 6f * t)
            scale(scaleX = glyphScale, scaleY = glyphScale, pivot = Offset.Zero)
        }) {
            drawPath(heartShape, color = Color.Black, alpha = 0.16f * opacity)
            drawPath(heartShape, color = Color(0xFFFF5278), alpha = opacity)
        }
        if (t < 0.6f) {
            val sparkle = (1f - t / 0.6f).coerceIn(0f, 1f)
            val spread = 15.dp.toPx() * (0.5f + t)
            for (direction in 0..5) {
                val angle = direction * kotlin.math.PI / 3
                drawCircle(
                    color = if (direction % 2 == 0) Color(0xFFFF90B0) else Color(0xFFFFD38A),
                    radius = 2.6.dp.toPx() * sparkle,
                    center = Offset(
                        at.x + kotlin.math.cos(angle).toFloat() * (22.dp.toPx() + spread),
                        at.y + kotlin.math.sin(angle).toFloat() * (22.dp.toPx() + spread),
                    ),
                    alpha = opacity * sparkle,
                )
            }
        }
    }
}

internal class ReactionLayoutCoordinates { var layout: LayoutCoordinates? = null }

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
    onBurst: (Offset, LayoutCoordinates) -> Unit,
): Modifier {
    if (!enabled && !singleTapEnabled) return this

    val actionHandler = LocalKeyboardActionHandler.current
    val viewConfiguration = LocalViewConfiguration.current
    val haptics = LocalHapticFeedback.current
    val activeReaction by rememberUpdatedState(reactionActive)
    val reactionEnabled by rememberUpdatedState(enabled)
    val tapEnabled by rememberUpdatedState(singleTapEnabled)
    val latestOnSingleTap by rememberUpdatedState(onSingleTap)
    val latestOnBurst by rememberUpdatedState(onBurst)
    val coordinates = remember(focusId) { ReactionLayoutCoordinates() }
    return this.onGloballyPositioned { coordinates.layout = it }.pointerInput(focusId, reaction, actionHandler, viewConfiguration) {
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
                                coordinates.layout?.takeIf { it.isAttached }?.let { layout ->
                                    latestOnBurst(change.position, layout)
                                }
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
