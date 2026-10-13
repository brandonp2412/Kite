package chat.schildi.revenge.compose.destination.conversation.event

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
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
): Modifier {
    if (!enabled) return this

    val actionHandler = LocalKeyboardActionHandler.current
    val viewConfiguration = LocalViewConfiguration.current
    return pointerInput(focusId, reaction, actionHandler, viewConfiguration) {
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
                        if (interval != null &&
                            interval >= doubleTapMinTime &&
                            interval <= doubleTapTimeout &&
                            closeEnough
                        ) {
                            previousTapTime = null
                            previousTapPosition = null
                            actionHandler.handleAction(
                                focusId,
                                Action.Event.ToggleReactionKey,
                                listOf(reaction),
                            )
                        } else {
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
