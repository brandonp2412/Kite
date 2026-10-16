package chat.schildi.revenge

import chat.schildi.revenge.compose.destination.settings.navigateBackFromSettings
import kotlin.test.Test
import kotlin.test.assertEquals

class SettingsBackNavigationTest {
    @Test
    fun backFromSettingsRootReturnsToInbox() {
        val settings = Destination.Settings()
        val parent = DestinationStateHolder.forInitialDestination(settings)

        navigateBackFromSettings(settings, parent)

        assertEquals(Destination.Inbox, parent.state.value.destination)
    }

    @Test
    fun backFromSettingsDetailsReturnsToSettingsRoot() {
        val settings = Destination.Settings()
        val parent = DestinationStateHolder.forInitialDestination(settings)
        settings.details.navigate(Destination.SettingsPane("appearance"), NavigationPreference.REPLACE)

        navigateBackFromSettings(settings, parent)

        assertEquals(Destination.MultiPaneSettingsPlaceholder, settings.details.state.value.destination)
        assertEquals(settings, parent.state.value.destination)
    }
}
