package chat.schildi.revenge

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import chat.schildi.revenge.compose.destination.conversation.event.message.FittedImageShape
import chat.schildi.revenge.compose.destination.conversation.event.message.fittedMediaRect
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class FittedImageShapeTest {
    @Test
    fun portraitImageCornersFollowImageRatherThanSquareViewport() {
        val outline = FittedImageShape(Size(3f, 4f), RoundedCornerShape(20.dp))
            .createOutline(Size(400f, 400f), LayoutDirection.Ltr, Density(1f))
        assertEquals(Rect(50f, 0f, 350f, 400f), assertIs<Outline.Generic>(outline).path.getBounds())
    }

    @Test
    fun landscapeImageCornersFollowLetterboxedPicture() {
        assertEquals(Rect(0f, 100f, 400f, 300f), fittedMediaRect(Size(400f, 400f), Size(2f, 1f)))
    }

    @Test
    fun missingIntrinsicDimensionsFallBackToReservedViewport() {
        assertEquals(Rect(0f, 0f, 400f, 400f), fittedMediaRect(Size(400f, 400f), Size.Unspecified))
    }
}
