package chat.schildi.revenge

import chat.schildi.revenge.compose.destination.conversation.event.message.waveformSampleCount
import kotlin.test.Test
import kotlin.test.assertEquals

class AudioWaveformLayoutTest {
    @Test
    fun emptyOrInvalidWidthKeepsOneSample() {
        assertEquals(1, waveformSampleCount(0, 4f))
        assertEquals(1, waveformSampleCount(100, 0f))
        assertEquals(1, waveformSampleCount(100, Float.NaN))
    }

    @Test
    fun widthMapsToAvailableWaveformSlots() {
        assertEquals(12, waveformSampleCount(48, 4f))
        assertEquals(25, waveformSampleCount(100, 4f))
    }

    @Test
    fun sampleCountIsBoundedForLongWaveforms() {
        assertEquals(
            Dimens.Conversation.AudioWaveform.maxRenderedSegments,
            waveformSampleCount(10_000, 1f),
        )
    }
}
