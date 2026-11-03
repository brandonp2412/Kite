package chat.schildi.revenge.compose.components

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class ContextMenuOffsetTest {
    private val density = Density(2f)
    private val anchor = Rect(50f, 100f, 400f, 180f)

    @Test
    fun dismissalKeepsPointerOffsetThroughExitAnimation() {
        val openOffset = contextMenuOffset(
            expanded = true,
            pointerPositionOnOpen = Offset(250f, 140f),
            anchorBounds = anchor,
            density = density,
            previousOffset = DpOffset(0.dp, 0.dp),
        )
        assertEquals(DpOffset(100.dp, 0.dp), openOffset)

        val closingOffset = contextMenuOffset(
            expanded = false,
            pointerPositionOnOpen = null,
            anchorBounds = anchor,
            density = density,
            previousOffset = openOffset,
        )
        assertEquals(openOffset, closingOffset)
    }

    @Test
    fun nextOpeningUsesNewPointerPosition() {
        val nextOffset = contextMenuOffset(
            expanded = true,
            pointerPositionOnOpen = Offset(90f, 140f),
            anchorBounds = anchor,
            density = density,
            previousOffset = DpOffset(100.dp, 0.dp),
        )
        assertEquals(DpOffset(20.dp, 0.dp), nextOffset)
    }
}
