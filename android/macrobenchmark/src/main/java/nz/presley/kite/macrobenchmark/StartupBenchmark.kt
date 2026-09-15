package nz.presley.kite.macrobenchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@LargeTest
class StartupBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun coldStartupTiming() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(StartupTimingMetric()),
        compilationMode = CompilationMode.Full(),
        iterations = 10,
        startupMode = StartupMode.COLD,
        setupBlock = {
            pressHome()
        },
    ) {
        device.executeShellCommand(
            "am start -n $TARGET_PACKAGE/nz.presley.kite.MainActivity",
        )
        assertNotNull(
            "Kite home did not expose the Chats heading after cold start",
            device.wait(Until.findObject(By.text("Chats")), 5_000),
        )
    }

    private companion object {
        const val TARGET_PACKAGE = "nz.presley.kite.benchmark"
    }
}
