package com.plix.plix

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.activity.ComponentActivity
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.YouTubePlayer
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.listeners.AbstractYouTubePlayerListener
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.options.IFramePlayerOptions
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.views.YouTubePlayerView
import kotlin.math.max

/**
 * Fullscreen embedded YouTube trailer player using android-youtube-player.
 * Automatically falls back to launching the native YouTube / SmartTube app
 * via ACTION_VIEW (vnd.youtube:{key}) when embed restrictions (error 101 / 150) occur.
 */
class TrailerPlayerActivity : ComponentActivity() {

    private lateinit var youTubePlayerView: YouTubePlayerView
    private lateinit var loadingSpinner: ProgressBar
    private var activePlayer: YouTubePlayer? = null
    private var isPlaying: Boolean = false
    private var currentSecond: Float = 0f
    private var videoKey: String = ""
    private var didFallback: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        videoKey = intent.getStringExtra("videoKey")?.trim() ?: ""
        if (videoKey.isEmpty()) {
            finish()
            return
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#0A0B10"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        youTubePlayerView = YouTubePlayerView(this).apply {
            enableAutomaticInitialization = false
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        loadingSpinner = ProgressBar(this).apply {
            isIndeterminate = true
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        root.addView(youTubePlayerView)
        root.addView(loadingSpinner)
        setContentView(root)
        enableImmersiveMode()

        lifecycle.addObserver(youTubePlayerView)

        val options = IFramePlayerOptions.Builder(this)
            .controls(1)
            .autoplay(1)
            .rel(0)
            .fullscreen(0)
            .build()

        youTubePlayerView.initialize(object : AbstractYouTubePlayerListener() {
            override fun onReady(youTubePlayer: YouTubePlayer) {
                activePlayer = youTubePlayer
                loadingSpinner.visibility = View.GONE
                youTubePlayer.loadVideo(videoKey, 0f)
            }

            override fun onStateChange(
                youTubePlayer: YouTubePlayer,
                state: PlayerConstants.PlayerState
            ) {
                isPlaying = (state == PlayerConstants.PlayerState.PLAYING)
                if (state == PlayerConstants.PlayerState.PLAYING ||
                    state == PlayerConstants.PlayerState.BUFFERING
                ) {
                    loadingSpinner.visibility = View.GONE
                } else if (state == PlayerConstants.PlayerState.ENDED) {
                    finish()
                }
            }

            override fun onCurrentSecond(youTubePlayer: YouTubePlayer, second: Float) {
                currentSecond = second
            }

            override fun onError(
                youTubePlayer: YouTubePlayer,
                error: PlayerConstants.PlayerError
            ) {
                // Studio trailers often block third-party WebView embedding (101 / 150 -> VIDEO_NOT_PLAYABLE_IN_EMBEDDED_PLAYER).
                // Gracefully fall back to native YouTube / SmartTube app via ACTION_VIEW.
                if (error == PlayerConstants.PlayerError.VIDEO_NOT_PLAYABLE_IN_EMBEDDED_PLAYER ||
                    error == PlayerConstants.PlayerError.HTML_5_PLAYER ||
                    error == PlayerConstants.PlayerError.VIDEO_NOT_FOUND
                ) {
                    fallbackToExternalYouTube()
                }
            }
        }, options)
    }

    private fun fallbackToExternalYouTube() {
        if (didFallback || isFinishing) return
        didFallback = true
        try {
            val appIntent = Intent(Intent.ACTION_VIEW, Uri.parse("vnd.youtube:$videoKey")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(appIntent)
        } catch (_: Exception) {
            try {
                val webIntent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://www.youtube.com/watch?v=$videoKey")
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(webIntent)
            } catch (_: Exception) {
            }
        }
        finish()
    }

    @Suppress("DEPRECATION")
    private fun enableImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_ESCAPE -> {
                    finish()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    activePlayer?.let { player ->
                        if (isPlaying) player.pause() else player.play()
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    activePlayer?.seekTo(max(0f, currentSecond - 10f))
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    activePlayer?.seekTo(currentSecond + 10f)
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        if (::youTubePlayerView.isInitialized) {
            youTubePlayerView.release()
        }
        super.onDestroy()
    }
}
