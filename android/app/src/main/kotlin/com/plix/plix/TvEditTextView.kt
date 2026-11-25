package com.plix.plix

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class TvEditTextFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String?, Any?>
        return TvEditTextView(context, viewId, creationParams, messenger)
    }
}

class TvEditTextView(
    private val context: Context,
    viewId: Int,
    creationParams: Map<String?, Any?>?,
    messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler {

    private inner class TvCustomEditText(ctx: Context) : EditText(ctx) {
        override fun onKeyPreIme(keyCode: Int, event: KeyEvent?): Boolean {
            if (keyCode == KeyEvent.KEYCODE_BACK && event?.action == KeyEvent.ACTION_UP) {
                if (isKeyboardOpen) {
                    unregisterBackCallback()
                    isKeyboardOpen = false
                    editText.isCursorVisible = false
                    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                    imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                    channel.invokeMethod("onKeyboardStateChanged", false)
                }
            }
            return super.onKeyPreIme(keyCode, event)
        }
    }

    private val editText: EditText = TvCustomEditText(context)
    private val channel: MethodChannel = MethodChannel(messenger, "plix/tv_edit_text_$viewId")
    private var isUpdatingFromFlutter = false
    private var isKeyboardOpen = false
    private var backCallback: Any? = null

    private fun getDispatcher(): OnBackInvokedDispatcher? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val viewDispatcher = editText.findOnBackInvokedDispatcher()
            if (viewDispatcher != null) return viewDispatcher

            var ctx = context
            while (ctx is android.content.ContextWrapper) {
                if (ctx is android.app.Activity) {
                    return ctx.onBackInvokedDispatcher
                }
                ctx = ctx.baseContext
            }
        }
        return null
    }

    private fun registerBackCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && backCallback == null) {
            val dispatcher = getDispatcher() ?: return
            val cb = OnBackInvokedCallback {
                unregisterBackCallback()
                if (isKeyboardOpen) {
                    isKeyboardOpen = false
                    editText.isCursorVisible = false
                    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                    imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                    channel.invokeMethod("onKeyboardStateChanged", false)
                }
            }
            backCallback = cb
            try {
                dispatcher.registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                    cb
                )
            } catch (_: Exception) {}
        }
    }

    private fun unregisterBackCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && backCallback != null) {
            try {
                val dispatcher = getDispatcher()
                val cb = backCallback as? OnBackInvokedCallback
                if (dispatcher != null && cb != null) {
                    dispatcher.unregisterOnBackInvokedCallback(cb)
                }
            } catch (_: Exception) {}
            backCallback = null
        }
    }

    init {
        channel.setMethodCallHandler(this)

        val initialText = creationParams?.get("initialText") as? String ?: ""
        val hint = creationParams?.get("hint") as? String ?: ""
        val textColorVal = creationParams?.get("textColor")
        val textColor = when (textColorVal) {
            is Number -> textColorVal.toInt()
            else -> Color.WHITE
        }
        val hintColorVal = creationParams?.get("hintColor")
        val hintColor = when (hintColorVal) {
            is Number -> hintColorVal.toInt()
            else -> Color.parseColor("#808080")
        }
        val fontSize = when (val size = creationParams?.get("fontSize")) {
            is Number -> size.toFloat()
            else -> 16f
        }
        val imeAction = creationParams?.get("imeAction") as? String ?: "search"
        val obscureText = creationParams?.get("obscureText") as? Boolean ?: false
        val maxLength = when (val len = creationParams?.get("maxLength")) {
            is Number -> len.toInt()
            else -> 0
        }
        val keyboardType = creationParams?.get("keyboardType") as? String ?: "text"
        val autocorrect = creationParams?.get("autocorrect") as? Boolean ?: (keyboardType != "url")

        editText.apply {
            setText(initialText)
            this.hint = hint
            setTextColor(textColor)
            setHintTextColor(hintColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(0, 0, 0, 0)
            isSingleLine = true
            maxLines = 1
            isFocusable = true
            isFocusableInTouchMode = true
            showSoftInputOnFocus = false
            isCursorVisible = false

            if (maxLength > 0) {
                filters = arrayOf(InputFilter.LengthFilter(maxLength))
            }

            if (obscureText) {
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            } else if (keyboardType == "url") {
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            } else if (!autocorrect) {
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            } else {
                inputType = InputType.TYPE_CLASS_TEXT
            }

            this.imeOptions = when (imeAction) {
                "search" -> EditorInfo.IME_ACTION_SEARCH
                "done" -> EditorInfo.IME_ACTION_DONE
                "next" -> EditorInfo.IME_ACTION_NEXT
                else -> EditorInfo.IME_ACTION_SEARCH
            }

            setOnEditorActionListener { _, _, _ ->
                unregisterBackCallback()
                isKeyboardOpen = false
                isCursorVisible = false
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                channel.invokeMethod("onKeyboardStateChanged", false)
                channel.invokeMethod("onSubmitted", editText.text.toString())
                true
            }

            setOnFocusChangeListener { _, hasFocus ->
                if (!hasFocus) {
                    unregisterBackCallback()
                    isKeyboardOpen = false
                    isCursorVisible = false
                    channel.invokeMethod("onKeyboardStateChanged", false)
                }
                channel.invokeMethod("onFocusChanged", hasFocus)
            }

            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN) {
                    when (keyCode) {
                        KeyEvent.KEYCODE_DPAD_DOWN -> {
                            channel.invokeMethod("onDown", null)
                            return@setOnKeyListener true
                        }
                        KeyEvent.KEYCODE_DPAD_UP -> {
                            channel.invokeMethod("onUp", null)
                            return@setOnKeyListener true
                        }
                        KeyEvent.KEYCODE_DPAD_LEFT -> {
                            if (!isKeyboardOpen) {
                                channel.invokeMethod("onLeft", null)
                                return@setOnKeyListener true
                            }
                        }
                        KeyEvent.KEYCODE_DPAD_RIGHT -> {
                            if (!isKeyboardOpen) {
                                channel.invokeMethod("onRight", null)
                                return@setOnKeyListener true
                            }
                        }
                    }
                }
                false
            }

            setOnClickListener {
                isKeyboardOpen = true
                isCursorVisible = true
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.showSoftInput(this, 0)
                channel.invokeMethod("onKeyboardStateChanged", true)
                registerBackCallback()
            }

            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    if (!isUpdatingFromFlutter) {
                        channel.invokeMethod("onChanged", s?.toString() ?: "")
                    }
                }
                override fun afterTextChanged(s: Editable?) {}
            })
        }
    }

    override fun getView(): View = editText

    override fun dispose() {
        unregisterBackCallback()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setText" -> {
                val text = call.arguments as? String ?: ""
                isUpdatingFromFlutter = true
                editText.setText(text)
                editText.setSelection(editText.text.length)
                isUpdatingFromFlutter = false
                result.success(null)
            }
            "requestFocus" -> {
                editText.requestFocus()
                result.success(null)
            }
            "openKeyboard" -> {
                isKeyboardOpen = true
                editText.isCursorVisible = true
                editText.showSoftInputOnFocus = true
                editText.requestFocus()
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.showSoftInput(editText, 0)
                channel.invokeMethod("onKeyboardStateChanged", true)
                registerBackCallback()
                editText.post {
                    editText.showSoftInputOnFocus = false
                }
                result.success(null)
            }
            "hideKeyboard" -> {
                unregisterBackCallback()
                isKeyboardOpen = false
                editText.isCursorVisible = false
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                channel.invokeMethod("onKeyboardStateChanged", false)
                result.success(null)
            }
            "clearFocus" -> {
                unregisterBackCallback()
                isKeyboardOpen = false
                editText.isCursorVisible = false
                editText.clearFocus()
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                channel.invokeMethod("onKeyboardStateChanged", false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
