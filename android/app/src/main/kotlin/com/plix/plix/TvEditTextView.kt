package com.plix.plix

import android.content.Context
import android.graphics.Color
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

    private val editText: EditText = EditText(context)
    private val channel: MethodChannel = MethodChannel(messenger, "plix/tv_edit_text_$viewId")
    private var isUpdatingFromFlutter = false
    private var isKeyboardOpen = false

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
                isKeyboardOpen = false
                isCursorVisible = false
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                channel.invokeMethod("onSubmitted", editText.text.toString())
                true
            }

            setOnFocusChangeListener { _, hasFocus ->
                if (!hasFocus) {
                    isKeyboardOpen = false
                    isCursorVisible = false
                }
                channel.invokeMethod("onFocusChanged", hasFocus)
            }

            setOnKeyListener { _, keyCode, _ ->
                // When keyboard is not open, ignore DPAD Left and Right so text cursor does not move
                if ((keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) && !isKeyboardOpen) {
                    true
                } else {
                    false
                }
            }

            setOnClickListener {
                isKeyboardOpen = true
                isCursorVisible = true
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.showSoftInput(this, 0)
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
                editText.post {
                    editText.showSoftInputOnFocus = false
                }
                result.success(null)
            }
            "hideKeyboard" -> {
                isKeyboardOpen = false
                editText.isCursorVisible = false
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                result.success(null)
            }
            "clearFocus" -> {
                isKeyboardOpen = false
                editText.isCursorVisible = false
                editText.clearFocus()
                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
