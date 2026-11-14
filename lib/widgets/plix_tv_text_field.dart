import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/plix_device_helper.dart';
import '../app_theme.dart';

class PlixTvTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String imeAction;
  final int? maxLength;
  final bool obscureText;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const PlixTvTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.hintText = '',
    this.style,
    this.hintStyle,
    this.onChanged,
    this.onSubmitted,
    this.imeAction = 'search',
    this.maxLength,
    this.obscureText = false,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  @override
  State<PlixTvTextField> createState() => _PlixTvTextFieldState();
}

class _PlixTvTextFieldState extends State<PlixTvTextField> {
  MethodChannel? _channel;
  bool _isNativeUpdating = false;

  bool get _useNativeView =>
      !kIsWeb && Platform.isAndroid && PlixDeviceHelper.isTelevision;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant PlixTvTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    widget.focusNode.removeListener(_handleFocusChange);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _handleControllerChange() {
    if (!_isNativeUpdating && _channel != null) {
      _channel?.invokeMethod('setText', widget.controller.text);
    }
  }

  void _handleFocusChange() {
    if (_channel != null) {
      if (!widget.focusNode.hasFocus) {
        _channel?.invokeMethod('clearFocus');
      }
    }
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('plix/tv_edit_text_$id');
    _channel!.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onChanged':
        final text = call.arguments as String? ?? '';
        _isNativeUpdating = true;
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _isNativeUpdating = false;
        widget.onChanged?.call(text);
        break;

      case 'onSubmitted':
        final text = call.arguments as String? ?? '';
        widget.onSubmitted?.call(text);
        break;

      case 'onFocusChanged':
        final hasFocus = call.arguments as bool? ?? false;
        if (hasFocus && !widget.focusNode.hasFocus) {
          widget.focusNode.requestFocus();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNativeView) {
      return TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        cursorColor: PlixTheme.plexGold,
        style: widget.style ??
            const TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: 16,
            ),
        obscureText: widget.obscureText,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: widget.hintStyle ??
              const TextStyle(
                color: PlixTheme.textMuted,
                fontSize: 16,
              ),
          border: InputBorder.none,
          isDense: true,
          counterText: '',
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      );
    }

    final textColor = widget.style?.color?.value ?? Colors.white.value;
    final hintColor = widget.hintStyle?.color?.value ?? 0xFF808080;
    final fontSize = widget.style?.fontSize ?? 16.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (widget.onLeft != null) {
              widget.onLeft!();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (widget.onRight != null) {
              widget.onRight!();
            }
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            _channel?.invokeMethod('openKeyboard');
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.focusNode.requestFocus();
          _channel?.invokeMethod('openKeyboard');
        },
        child: AndroidView(
          viewType: 'plix/tv_edit_text',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: {
            'initialText': widget.controller.text,
            'hint': widget.hintText,
            'textColor': textColor,
            'hintColor': hintColor,
            'fontSize': fontSize,
            'imeAction': widget.imeAction,
            'maxLength': widget.maxLength ?? 0,
            'obscureText': widget.obscureText,
          },
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
  }
}
