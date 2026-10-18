package chat.schildi.revenge.compose.components

import androidx.compose.runtime.mutableStateMapOf
import chat.schildi.revenge.config.ScAppDirs
import io.element.android.libraries.matrix.api.core.SessionId
import io.element.android.libraries.matrix.api.core.UserId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest

/** Device-local photos, scoped to both account and Matrix user. */
object LocalAvatarOverrides {
    private val photos = mutableStateMapOf<String, File?>()
    private val root get() = File(ScAppDirs.getUserDataDir(), "avatar-overrides")

    private fun key(sessionId: SessionId, userId: UserId): String =
        MessageDigest.getInstance("SHA-256")
            .digest("${sessionId.value}\u0000${userId.value}".toByteArray())
            .joinToString("") { "%02x".format(it) }

    fun photo(sessionId: SessionId?, userId: UserId?): File? {
        if (sessionId == null || userId == null) return null
        val key = key(sessionId, userId)
        if (!photos.containsKey(key)) {
            photos[key] = File(root, key).listFiles()?.firstOrNull { it.isFile && it.name.startsWith("avatar-") }
        }
        return photos[key]
    }

    suspend fun set(sessionId: SessionId, userId: UserId, file: File) {
        val key = key(sessionId, userId)
        val target = withContext(Dispatchers.IO) {
            val dir = File(root, key)
            check(dir.isDirectory || dir.mkdirs()) { "Cannot create avatar directory" }
            val suffix = file.extension.takeIf { it.matches(Regex("[a-zA-Z0-9]{1,8}")) } ?: "img"
            val target = File(dir, "avatar-${System.nanoTime()}.$suffix")
            file.copyTo(target)
            dir.listFiles()?.filter { it != target }?.forEach(File::delete)
            target
        }
        photos[key] = target
    }

    suspend fun clear(sessionId: SessionId, userId: UserId) {
        val key = key(sessionId, userId)
        withContext(Dispatchers.IO) { File(root, key).deleteRecursively() }
        photos[key] = null
    }
}
