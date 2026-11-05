package chat.schildi.revenge

import chat.schildi.revenge.util.MediaMeasures
import chat.schildi.revenge.util.imageMeasuresFromBounds
import kotlin.test.Test
import kotlin.test.assertEquals

class ImageMediaMeasuresTest {
    @Test
    fun uprightImagePreservesDimensions() {
        assertEquals(MediaMeasures(1080, 2400, null), imageMeasuresFromBounds(1080, 2400, false))
    }

    @Test
    fun exifQuarterTurnSwapsDimensions() {
        assertEquals(MediaMeasures(2400, 1080, null), imageMeasuresFromBounds(1080, 2400, true))
    }

    @Test
    fun invalidDecodeDoesNotPretendToBeSquare() {
        val unknown = MediaMeasures(null, null, null)
        assertEquals(unknown, imageMeasuresFromBounds(0, 2400, false))
        assertEquals(unknown, imageMeasuresFromBounds(1080, -1, true))
    }
}
