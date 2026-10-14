package chat.schildi.revenge.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import chat.schildi.revenge.GlobalActionsScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        GlobalActionsScope.launch(Dispatchers.IO) {
            try {
                AndroidNotifier.handleNotificationAction(context.applicationContext, intent)
            } finally {
                pendingResult.finish()
            }
        }
    }
}
