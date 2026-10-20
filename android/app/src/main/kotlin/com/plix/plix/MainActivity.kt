package com.plix.plix

import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.PixelFormat
import android.media.MediaCodecList
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.SubtitleView
import android.widget.FrameLayout
import android.view.Gravity
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val MEDIA_KEYS_CHANNEL = "com.plix.plix/media_keys"
    private val NATIVE_PLAYER_CHANNEL = "com.plix.plix/native_player"
    private val UPDATER_CHANNEL = "com.plix.plix/updater"

    private var mediaKeysChannel: MethodChannel? = null
    private var nativePlayerChannel: MethodChannel? = null
    private var updaterChannel: MethodChannel? = null

    private var isPlayerActive: Boolean = false
    private var mediaSession: MediaSession? = null

    // Native HDR Video Surface & ExoPlayer
    private var videoSurfaceView: SurfaceView? = null
    private var subtitleView: SubtitleView? = null
    private var aspectRatioFrameLayout: AspectRatioFrameLayout? = null
    private var exoPlayer: ExoPlayer? = null
    private var isSurfaceCreated: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pollRunnable: Runnable? = null
    private var selectedSubtitleLanguage: String? = null
    private var selectedSubtitleLabel: String? = null
    private var selectedSubtitleIndex: Int? = null
    private var isSubtitleDisabled: Boolean = false
    private var selectedAudioLanguage: String? = null
    private var selectedAudioLabel: String? = null
    private var selectedAudioIndex: Int? = null
    private val SPEECH_REQUEST_CODE = 9912
    private var speechResultCallback: io.flutter.plugin.common.MethodChannel.Result? = null

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                window.colorMode = ActivityInfo.COLOR_MODE_HDR
                window.setFormat(PixelFormat.RGBA_1010102)
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        setupNativeSurfaceView()
        setupMediaSession()
    }

    override fun onFlutterSurfaceViewCreated(flutterSurfaceView: FlutterSurfaceView) {
        super.onFlutterSurfaceViewCreated(flutterSurfaceView)
        try {
            flutterSurfaceView.setZOrderMediaOverlay(true)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setupNativeSurfaceView() {
        val root = findViewById<ViewGroup>(android.R.id.content) ?: return

        val aspectLayout = AspectRatioFrameLayout(this).apply {
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            visibility = View.GONE
        }
        aspectRatioFrameLayout = aspectLayout

        val surface = SurfaceView(this).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                holder.setFormat(PixelFormat.RGBA_1010102)
            }
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        holder.setFormat(PixelFormat.RGBA_1010102)
                    }
                    isSurfaceCreated = true
                    exoPlayer?.setVideoSurfaceHolder(holder)
                }

                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

                override fun surfaceDestroyed(holder: SurfaceHolder) {
                    isSurfaceCreated = false
                    exoPlayer?.clearVideoSurfaceHolder(holder)
                }
            })
        }
        videoSurfaceView = surface

        aspectLayout.addView(surface, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        ))

        val subView = SubtitleView(this).apply {
            setUserDefaultStyle()
            setUserDefaultTextSize()
        }
        subtitleView = subView
        aspectLayout.addView(subView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        ))

        // Add behind Flutter's view, centered in root FrameLayout
        root.addView(aspectLayout, 0, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        ))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Updater channel
        updaterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
        updaterChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrBlank()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_URL", "URL was empty", null)
                    }
                }
                "getCacheDir" -> {
                    result.success(cacheDir.absolutePath)
                }
                "isTelevision" -> {
                    var isTv = false
                    try {
                        val uiModeManager = getSystemService(android.content.Context.UI_MODE_SERVICE) as? android.app.UiModeManager
                        val isTvMode = uiModeManager?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION
                        val isLeanback = packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK)
                        isTv = isTvMode || isLeanback
                    } catch (_: Exception) {}
                    result.success(isTv)
                }
                "getDeviceName" -> {
                    var name: String? = null
                    try {
                        name = android.provider.Settings.Global.getString(contentResolver, "device_name")
                    } catch (_: Exception) {}
                    if (name.isNullOrBlank()) {
                        try {
                            name = android.os.Build.MODEL
                        } catch (_: Exception) {}
                    }
                    if (name.isNullOrBlank()) {
                        val isLeanback = packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK)
                        name = if (isLeanback) "Android TV" else "Android Phone"
                    }
                    result.success(name)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = java.io.File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                                return@setMethodCallHandler
                            }
                            val contentUri = androidx.core.content.FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Media keys channel
        mediaKeysChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_KEYS_CHANNEL)
        mediaKeysChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPlayerActive" -> {
                    isPlayerActive = call.argument<Boolean>("active") ?: false
                    updateMediaSessionActive(isPlayerActive)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Native Player channel for true HDR & hardware audio checking
        nativePlayerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_PLAYER_CHANNEL)
        nativePlayerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAudioSupported" -> {
                    val codec = call.argument<String>("codec") ?: ""
                    result.success(isAudioCodecSupported(codec))
                }
                "play" -> {
                    val url = call.argument<String>("url") ?: ""
                    val headers = call.argument<Map<String, String>>("headers")
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    playMedia(url, headers, positionMs)
                    result.success(true)
                }
                "pause" -> {
                    exoPlayer?.pause()
                    result.success(true)
                }
                "resume" -> {
                    exoPlayer?.play()
                    result.success(true)
                }
                "seekTo" -> {
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    exoPlayer?.seekTo(positionMs)
                    result.success(true)
                }
                "stop" -> {
                    stopPlayback()
                    result.success(true)
                }
                "getState" -> {
                    val pos = exoPlayer?.currentPosition ?: 0L
                    val dur = exoPlayer?.duration ?: 0L
                    val isPlaying = exoPlayer?.isPlaying ?: false
                    val buffered = exoPlayer?.bufferedPosition ?: 0L
                    result.success(mapOf(
                        "position" to pos,
                        "duration" to (if (dur < 0) 0L else dur),
                        "isPlaying" to isPlaying,
                        "buffered" to buffered
                    ))
                }
                "setSubtitleTrack" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val language = call.argument<String>("language")
                    val label = call.argument<String>("label")
                    val trackIndex = (call.argument<Number>("trackIndex"))?.toInt()
                    isSubtitleDisabled = !enabled
                    selectedSubtitleLanguage = language
                    selectedSubtitleLabel = label
                    selectedSubtitleIndex = trackIndex
                    applySubtitleSelection()
                    result.success(true)
                }
                "setAudioTrack" -> {
                    val trackIndex = (call.argument<Number>("trackIndex"))?.toInt()
                    val language = call.argument<String>("language")
                    val label = call.argument<String>("label")
                    selectedAudioIndex = trackIndex
                    selectedAudioLanguage = language
                    selectedAudioLabel = label
                    applyAudioSelection()
                    result.success(true)
                }
                "startVoiceRecognition" -> {
                    speechResultCallback = result
                    val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Speak to search Plix...")
                    }
                    try {
                        startActivityForResult(intent, SPEECH_REQUEST_CODE)
                    } catch (e: Exception) {
                        speechResultCallback?.success("")
                        speechResultCallback = null
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SPEECH_REQUEST_CODE) {
            if (resultCode == RESULT_OK && data != null) {
                val results = data.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)
                val spokenText = results?.firstOrNull() ?: ""
                speechResultCallback?.success(spokenText)
            } else {
                speechResultCallback?.success("")
            }
            speechResultCallback = null
        }
    }

    private fun applySubtitleSelection() {
        val player = exoPlayer ?: return
        try {
            val builder = player.trackSelectionParameters.buildUpon()
            builder.clearOverridesOfType(C.TRACK_TYPE_TEXT)
            if (isSubtitleDisabled) {
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                player.trackSelectionParameters = builder.build()
                return
            }

            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            val targetTrackIndex = selectedSubtitleIndex
            val lang = selectedSubtitleLanguage
            val label = selectedSubtitleLabel

            var overrideSet = false
            var selectedMediaGroup: androidx.media3.common.TrackGroup? = null
            val currentTracks = player.currentTracks

            // 1. If targetTrackIndex is provided, select the exact text track by 0-based index
            if (targetTrackIndex != null && targetTrackIndex >= 0) {
                var textTrackCounter = 0
                for (group in currentTracks.groups) {
                    if (group.type == C.TRACK_TYPE_TEXT) {
                        val mediaGroup = group.mediaTrackGroup
                        for (i in 0 until mediaGroup.length) {
                            if (textTrackCounter == targetTrackIndex) {
                                builder.setOverrideForType(
                                    TrackSelectionOverride(mediaGroup, listOf(i))
                                )
                                selectedMediaGroup = mediaGroup
                                overrideSet = true
                                break
                            }
                            textTrackCounter++
                        }
                        if (overrideSet) break
                    }
                }
            }

            // 2. Fallback to matching by label / language if index match was not applied
            if (!overrideSet) {
                for (group in currentTracks.groups) {
                    if (group.type == C.TRACK_TYPE_TEXT) {
                        val mediaGroup = group.mediaTrackGroup
                        for (i in 0 until mediaGroup.length) {
                            val format = mediaGroup.getFormat(i)
                            val langMatches = !lang.isNullOrEmpty() && (
                                format.language?.equals(lang, ignoreCase = true) == true ||
                                (lang.length >= 2 && format.language?.startsWith(lang.substring(0, 2), ignoreCase = true) == true)
                            )
                            val labelMatches = !label.isNullOrEmpty() && (
                                format.label?.contains(label, ignoreCase = true) == true ||
                                label.contains(format.label ?: "", ignoreCase = true)
                            )

                            if (langMatches || labelMatches) {
                                builder.setOverrideForType(
                                    TrackSelectionOverride(mediaGroup, listOf(i))
                                )
                                selectedMediaGroup = mediaGroup
                                overrideSet = true
                                break
                            }
                        }
                        if (overrideSet) break
                    }
                }
            }

            // 3. Explicitly disable all other text track groups so ExoPlayer never plays multiple subtitle tracks at once
            for (group in currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_TEXT) {
                    val mediaGroup = group.mediaTrackGroup
                    if (mediaGroup != selectedMediaGroup) {
                        builder.setOverrideForType(
                            TrackSelectionOverride(mediaGroup, emptyList())
                        )
                    }
                }
            }

            if (!overrideSet && !lang.isNullOrEmpty()) {
                builder.setPreferredTextLanguage(lang)
            }
            player.trackSelectionParameters = builder.build()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyAudioSelection() {
        val player = exoPlayer ?: return
        try {
            val builder = player.trackSelectionParameters.buildUpon()
            val targetTrackIndex = selectedAudioIndex
            val lang = selectedAudioLanguage
            val label = selectedAudioLabel

            var overrideSet = false
            val currentTracks = player.currentTracks

            // 1. If targetTrackIndex is provided, select the exact audio track by 0-based index
            if (targetTrackIndex != null && targetTrackIndex >= 0) {
                var audioTrackCounter = 0
                for (group in currentTracks.groups) {
                    if (group.type == C.TRACK_TYPE_AUDIO) {
                        val mediaGroup = group.mediaTrackGroup
                        for (i in 0 until mediaGroup.length) {
                            if (audioTrackCounter == targetTrackIndex) {
                                builder.setOverrideForType(
                                    TrackSelectionOverride(mediaGroup, listOf(i))
                                )
                                overrideSet = true
                                break
                            }
                            audioTrackCounter++
                        }
                        if (overrideSet) break
                    }
                }
            }

            // 2. Fallback to matching by label / language
            if (!overrideSet) {
                for (group in currentTracks.groups) {
                    if (group.type == C.TRACK_TYPE_AUDIO) {
                        val mediaGroup = group.mediaTrackGroup
                        for (i in 0 until mediaGroup.length) {
                            val format = mediaGroup.getFormat(i)
                            val langMatches = !lang.isNullOrEmpty() && (
                                format.language?.equals(lang, ignoreCase = true) == true ||
                                (lang.length >= 2 && format.language?.startsWith(lang.substring(0, 2), ignoreCase = true) == true)
                            )
                            val labelMatches = !label.isNullOrEmpty() && (
                                format.label?.contains(label, ignoreCase = true) == true ||
                                label.contains(format.label ?: "", ignoreCase = true)
                            )

                            if (langMatches || labelMatches) {
                                builder.setOverrideForType(
                                    TrackSelectionOverride(mediaGroup, listOf(i))
                                )
                                overrideSet = true
                                break
                            }
                        }
                        if (overrideSet) break
                    }
                }
            }

            if (!overrideSet && !lang.isNullOrEmpty()) {
                builder.setPreferredAudioLanguage(lang)
            }
            player.trackSelectionParameters = builder.build()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isAudioCodecSupported(codec: String): Boolean {
        val lower = codec.lowercase().trim()
        val mime = when {
            lower == "ac3" -> "audio/ac3"
            lower == "eac3" || lower == "e-ac3" -> "audio/eac3"
            lower == "ac4" -> "audio/ac4"
            lower == "dca" || lower == "dts" || lower.contains("dts") -> "audio/vnd.dts"
            lower == "truehd" -> "audio/true-hd"
            lower == "aac" -> "audio/mp4a-latm"
            lower == "flac" -> "audio/flac"
            lower == "opus" -> "audio/opus"
            lower == "vorbis" -> "audio/vorbis"
            lower == "mp3" -> "audio/mpeg"
            else -> return true
        }

        try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                for (type in info.supportedTypes) {
                    if (type.equals(mime, ignoreCase = true)) {
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun playMedia(url: String, headers: Map<String, String>?, positionMs: Long) {
        stopPlayback()

        mainHandler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    window.colorMode = ActivityInfo.COLOR_MODE_HDR
                    videoSurfaceView?.holder?.setFormat(PixelFormat.RGBA_1010102)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            videoSurfaceView?.visibility = View.VISIBLE
            aspectRatioFrameLayout?.visibility = View.VISIBLE

            val player = ExoPlayer.Builder(this).build().apply {
                videoSurfaceView?.let { setVideoSurfaceView(it) }

                val dataSourceFactory = DefaultHttpDataSource.Factory()
                headers?.let {
                    dataSourceFactory.setDefaultRequestProperties(it)
                }

                val mediaItem = MediaItem.fromUri(Uri.parse(url))
                val mediaSource = if (url.contains(".m3u8")) {
                    HlsMediaSource.Factory(dataSourceFactory).createMediaSource(mediaItem)
                } else {
                    ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(mediaItem)
                }

                addListener(object : Player.Listener {
                    override fun onVideoSizeChanged(videoSize: VideoSize) {
                        if (videoSize.width > 0 && videoSize.height > 0) {
                            val ratio = (videoSize.width.toFloat() * videoSize.pixelWidthHeightRatio) / videoSize.height.toFloat()
                            mainHandler.post {
                                aspectRatioFrameLayout?.setAspectRatio(ratio)
                            }
                        }
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_READY) {
                            nativePlayerChannel?.invokeMethod("onPlayerReady", mapOf(
                                "duration" to (if (duration < 0) 0L else duration)
                            ))
                        } else if (playbackState == Player.STATE_ENDED) {
                            nativePlayerChannel?.invokeMethod("onPlayerEnded", null)
                        }
                    }

                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        nativePlayerChannel?.invokeMethod("onIsPlayingChanged", mapOf("isPlaying" to isPlaying))
                        updateMediaSessionActive(isPlaying)
                    }

                    override fun onTracksChanged(tracks: Tracks) {
                        if (!isSubtitleDisabled) {
                            applySubtitleSelection()
                        }
                        applyAudioSelection()
                    }

                    override fun onCues(cueGroup: CueGroup) {
                        if (isSubtitleDisabled) {
                            mainHandler.post { subtitleView?.setCues(emptyList()) }
                            nativePlayerChannel?.invokeMethod("onSubtitleCue", mapOf("text" to ""))
                            nativePlayerChannel?.invokeMethod("onSubtitleBitmapCue", null)
                            return
                        }
                        val bitmapCue = cueGroup.cues.firstOrNull { it.bitmap != null }
                        if (bitmapCue != null && bitmapCue.bitmap != null) {
                            try {
                                val stream = java.io.ByteArrayOutputStream()
                                bitmapCue.bitmap!!.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                                val bytes = stream.toByteArray()
                                mainHandler.post {
                                    nativePlayerChannel?.invokeMethod("onSubtitleBitmapCue", mapOf("bytes" to bytes))
                                }
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            nativePlayerChannel?.invokeMethod("onSubtitleCue", mapOf("text" to ""))
                        } else {
                            mainHandler.post {
                                subtitleView?.setCues(emptyList())
                                nativePlayerChannel?.invokeMethod("onSubtitleBitmapCue", null)
                            }
                            val text = if (cueGroup.cues.isEmpty()) {
                                ""
                            } else {
                                val firstCue = cueGroup.cues.firstOrNull { !it.text.isNullOrBlank() }
                                firstCue?.text?.toString()?.trim() ?: ""
                            }
                            nativePlayerChannel?.invokeMethod("onSubtitleCue", mapOf("text" to text))
                        }
                    }
                })

                setMediaSource(mediaSource)
                prepare()
                applySubtitleSelection()
                applyAudioSelection()
                if (positionMs > 0) {
                    seekTo(positionMs)
                }
                play()
            }
            exoPlayer = player
            startPeriodicUpdates()
        }
    }

    private fun startPeriodicUpdates() {
        stopPeriodicUpdates()
        pollRunnable = object : Runnable {
            override fun run() {
                exoPlayer?.let { player ->
                    val pos = player.currentPosition
                    val dur = player.duration
                    val isPlaying = player.isPlaying
                    nativePlayerChannel?.invokeMethod("onPositionUpdate", mapOf(
                        "position" to pos,
                        "duration" to (if (dur < 0) 0L else dur),
                        "isPlaying" to isPlaying
                    ))
                }
                mainHandler.postDelayed(this, 500)
            }
        }
        mainHandler.post(pollRunnable!!)
    }

    private fun stopPeriodicUpdates() {
        pollRunnable?.let { mainHandler.removeCallbacks(it) }
        pollRunnable = null
    }

    private fun stopPlayback() {
        stopPeriodicUpdates()
        selectedAudioIndex = null
        selectedAudioLanguage = null
        selectedAudioLabel = null
        exoPlayer?.let {
            it.stop()
            it.release()
        }
        exoPlayer = null
        mainHandler.post {
            subtitleView?.setCues(emptyList())
            videoSurfaceView?.visibility = View.GONE
            aspectRatioFrameLayout?.visibility = View.GONE
        }
    }

    override fun onPause() {
        super.onPause()
        exoPlayer?.pause()
        nativePlayerChannel?.invokeMethod("onIsPlayingChanged", mapOf("isPlaying" to false))
    }

    override fun onStop() {
        super.onStop()
        exoPlayer?.pause()
        nativePlayerChannel?.invokeMethod("onIsPlayingChanged", mapOf("isPlaying" to false))
    }

    private fun setupMediaSession() {
        try {
            mediaSession = MediaSession(this, "PlixMediaSession").apply {
                setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)

                val state = PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_FAST_FORWARD or
                        PlaybackState.ACTION_REWIND or
                        PlaybackState.ACTION_STOP
                    )
                    .setState(PlaybackState.STATE_PLAYING, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                    .build()
                setPlaybackState(state)

                setCallback(object : MediaSession.Callback() {
                    override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                        val keyEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                        }
                        if (keyEvent != null && keyEvent.action == KeyEvent.ACTION_DOWN) {
                            return handleKeyCode(keyEvent.keyCode)
                        }
                        return super.onMediaButtonEvent(mediaButtonIntent)
                    }

                    override fun onPlay() {
                        sendAction("play")
                    }

                    override fun onPause() {
                        sendAction("pause")
                    }

                    override fun onFastForward() {
                        sendAction("fast_forward")
                    }

                    override fun onRewind() {
                        sendAction("rewind")
                    }

                    override fun onStop() {
                        sendAction("pause")
                    }
                })
                isActive = true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateMediaSessionActive(active: Boolean) {
        try {
            mediaSession?.let { session ->
                session.isActive = true
                val stateVal = if (active) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
                val state = PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_FAST_FORWARD or
                        PlaybackState.ACTION_REWIND or
                        PlaybackState.ACTION_STOP
                    )
                    .setState(stateVal, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                    .build()
                session.setPlaybackState(state)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun handleKeyCode(keyCode: Int): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_BUTTON_START -> {
                sendAction("play_pause", keyCode)
                true
            }
            KeyEvent.KEYCODE_MEDIA_PLAY -> {
                sendAction("play", keyCode)
                true
            }
            KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                sendAction("pause", keyCode)
                true
            }
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
            KeyEvent.KEYCODE_MEDIA_NEXT -> {
                sendAction("fast_forward", keyCode)
                true
            }
            KeyEvent.KEYCODE_MEDIA_REWIND,
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                sendAction("rewind", keyCode)
                true
            }
            else -> false
        }
    }

    private fun sendAction(action: String, keyCode: Int = 0) {
        runOnUiThread {
            mediaKeysChannel?.invokeMethod("onMediaKey", mapOf("action" to action, "keyCode" to keyCode))
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (handleKeyCode(event.keyCode)) {
                if (isPlayerActive) return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (handleKeyCode(keyCode)) {
            if (isPlayerActive) return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        stopPlayback()
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }
}
