package chat.schildi.revenge

import chat.schildi.revenge.compose.components.shouldNavigateToInboxOnMobile
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TopNavigationBackTest {
    @Test
    fun settingsBackArrowReturnsToInboxOnAndroid() {
        assertTrue(shouldNavigateToInboxOnMobile(Destination.SettingsPane()))
        assertTrue(shouldNavigateToInboxOnMobile(Destination.Settings()))
    }

    @Test
    fun existingAccountManagementBackReturnsToInbox() {
        assertTrue(shouldNavigateToInboxOnMobile(Destination.AccountManagement()))
    }

    @Test
    fun initialAccountSetupDoesNotNavigateToNonexistentInbox() {
        assertFalse(shouldNavigateToInboxOnMobile(Destination.AccountManagement(isInitialSetup = true)))
    }
}
