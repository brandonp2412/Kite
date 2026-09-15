package nz.presley.kite.macrobenchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.benchmark.macro.StartupMode
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OpenDmBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun openUserDmFrameTiming() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(FrameTimingMetric()),
        compilationMode = CompilationMode.Full(),
        iterations = 10,
        startupMode = StartupMode.WARM,
        setupBlock = {
            startActivityAndWait()
            assertNotNull(
                "Alice fixture room was not exposed through Android accessibility semantics",
                device.wait(Until.findObject(By.text("Alice")), 5_000),
            )
        },
    ) {
        repeat(30) { index ->
            val target = if (index % 2 == 0) "Alice" else "Bob"
            val room = device.wait(Until.findObject(By.text(target)), 2_000)
            assertNotNull("Could not find $target fixture room", room)
            room.click()
            device.waitForIdle()
        }
    }

    private companion object {
        const val TARGET_PACKAGE = "nz.presley.kite.benchmark"
    }
}
