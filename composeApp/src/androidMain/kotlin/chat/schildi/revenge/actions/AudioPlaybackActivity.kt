package chat.schildi.revenge.actions

import android.app.Activity
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast

/** Play local Matrix audio without relying on an external audio intent handler. */
class AudioPlaybackActivity : Activity() {
    companion object {
        const val EXTRA_FILENAME = "filename"
    }

    private var player: MediaPlayer? = null
    private var prepared = false
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var playButton: Button
    private lateinit var seekBar: SeekBar
    private lateinit var positionLabel: TextView
    private val updatePosition = object : Runnable {
        override fun run() {
            val media = player ?: return
            if (!prepared || !media.isPlaying) return
            seekBar.progress = media.currentPosition
            positionLabel.text = "${formatDuration(media.currentPosition)} / ${formatDuration(media.duration)}"
            handler.postDelayed(this, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent.data ?: run { finish(); return }
        val padding = (24 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        layout.addView(TextView(this).apply {
            text = intent.getStringExtra(EXTRA_FILENAME) ?: "Audio attachment"
            textSize = 18f
        })
        positionLabel = TextView(this).apply { text = "00:00 / 00:00" }
        seekBar = SeekBar(this).apply {
            isEnabled = false
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                    if (fromUser) player?.seekTo(progress)
                }
                override fun onStartTrackingTouch(bar: SeekBar) = Unit
                override fun onStopTrackingTouch(bar: SeekBar) = Unit
            })
        }
        playButton = Button(this).apply {
            text = "Loading…"
            isEnabled = false
            setOnClickListener {
                player?.let { media ->
                    if (media.isPlaying) media.pause() else media.start()
                    text = if (media.isPlaying) "Pause" else "Play"
                    handler.removeCallbacks(updatePosition)
                    if (media.isPlaying) handler.post(updatePosition)
                }
            }
        }
        layout.addView(seekBar)
        layout.addView(positionLabel)
        layout.addView(playButton)
        setContentView(layout)

        try {
            player = MediaPlayer().apply {
                setDataSource(this@AudioPlaybackActivity, uri)
                setOnPreparedListener { media ->
                    prepared = true
                    seekBar.max = media.duration.coerceAtLeast(0)
                    seekBar.isEnabled = true
                    playButton.isEnabled = true
                    media.start()
                    playButton.text = "Pause"
                    handler.post(updatePosition)
                }
                setOnCompletionListener {
                    handler.removeCallbacks(updatePosition)
                    playButton.text = "Replay"
                    seekBar.progress = 0
                }
                setOnErrorListener { _, _, _ ->
                    Toast.makeText(this@AudioPlaybackActivity, "Cannot play this audio format", Toast.LENGTH_LONG).show()
                    finish()
                    true
                }
                prepareAsync()
            }
        } catch (_: Exception) {
            Toast.makeText(this, "Cannot open audio attachment", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    override fun onStop() {
        super.onStop()
        handler.removeCallbacks(updatePosition)
        if (prepared) player?.takeIf { it.isPlaying }?.pause()
        if (::playButton.isInitialized && player != null) playButton.text = "Play"
    }

    override fun onDestroy() {
        handler.removeCallbacks(updatePosition)
        player?.release()
        player = null
        super.onDestroy()
    }

    private fun formatDuration(milliseconds: Int): String {
        val seconds = milliseconds.coerceAtLeast(0) / 1000
        return "%02d:%02d".format(seconds / 60, seconds % 60)
    }
}
