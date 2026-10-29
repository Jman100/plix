import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';

class PlixHomeButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const PlixHomeButton({
    super.key,
    this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  @override
  State<PlixHomeButton> createState() => _PlixHomeButtonState();
}

class _PlixHomeButtonState extends State<PlixHomeButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _handlePress() {
    if (widget.onPressed != null) {
      widget.onPressed!();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      return const SizedBox.shrink();
    }
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            _handlePress();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: isHighlighted ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: _handlePress,
          onHover: (hovered) {
            if ((Platform.isWindows || Platform.isLinux) && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHighlighted ? PlixTheme.cardFocused : Colors.black45,
              border: Border.all(
                color: isHighlighted ? PlixTheme.plexGold : Colors.white24,
                width: isHighlighted ? 2.5 : 1.5,
              ),
              boxShadow: isHighlighted
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.55),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.home_rounded,
              color: isHighlighted ? PlixTheme.plexGold : Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
