import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';

class PlixButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget? icon;
  final String label;
  final bool isPrimary;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool blockUp;
  final bool blockDown;
  final bool blockLeft;
  final bool blockRight;
  final double? width;
  final double? fontSize;
  final Color? backgroundColor;
  final Color? highlightColor;
  final Color? borderColor;
  final Color? textColor;

  const PlixButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isPrimary = true,
    this.autofocus = false,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.blockUp = false,
    this.blockDown = false,
    this.blockLeft = false,
    this.blockRight = false,
    this.width,
    this.fontSize,
    this.backgroundColor,
    this.highlightColor,
    this.borderColor,
    this.textColor,
  });

  @override
  State<PlixButton> createState() => _PlixButtonState();
}

class _PlixButtonState extends State<PlixButton> {
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
  void didUpdateWidget(covariant PlixButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      } else {
        _focusNode.removeListener(_onFocusChange);
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
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

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;

    final effectiveHighlightColor = widget.highlightColor ??
        (widget.isPrimary ? PlixTheme.plexGoldLight : PlixTheme.cardFocused);

    final bgColor = widget.backgroundColor != null
        ? (isHighlighted ? effectiveHighlightColor : widget.backgroundColor!)
        : (widget.isPrimary
            ? (isHighlighted ? PlixTheme.plexGoldLight : PlixTheme.plexGold)
            : (isHighlighted
                ? PlixTheme.cardFocused
                : (PlixTheme.isOLED
                    ? const Color(0xFF000000)
                    : (PlixTheme.isGlass ? const Color(0x30FFFFFF) : PlixTheme.surface))));

    final fgColor = widget.textColor != null
        ? widget.textColor!
        : (widget.isPrimary
            ? Colors.black
            : (isHighlighted ? PlixTheme.textPrimary : PlixTheme.textSecondary));

    final borderColor = isHighlighted
        ? (widget.borderColor ?? PlixTheme.plexGold)
        : (widget.isPrimary
            ? Colors.transparent
            : (PlixTheme.isOLED
                ? PlixTheme.cardBorder
                : (PlixTheme.isGlass ? const Color(0x45FFFFFF) : Colors.transparent)));

    final glowColor = widget.borderColor ??
        widget.highlightColor ??
        widget.backgroundColor ??
        PlixTheme.plexGold;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            if (widget.onLeft != null) {
              widget.onLeft!();
              return KeyEventResult.handled;
            }
            if (widget.blockLeft) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            if (widget.onRight != null) {
              widget.onRight!();
              return KeyEventResult.handled;
            }
            if (widget.blockRight) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
              return KeyEventResult.handled;
            }
            if (widget.blockUp) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            if (widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            if (widget.blockDown) {
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent && (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.gameButtonSelect ||
              key == LogicalKeyboardKey.numpadEnter)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: isHighlighted ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          canRequestFocus: false,
          onTap: widget.onPressed,
          onHover: (hovered) {
            if ((Platform.isWindows || Platform.isLinux) && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.width,
            alignment: Alignment.center,
            padding: widget.padding,
            decoration: (PlixTheme.isGlass && widget.backgroundColor == null)
                ? PlixTheme.glassBoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    isHighlighted: isHighlighted,
                    accent: glowColor,
                    borderWidth: 1.5,
                  )
                : BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: 2.0,
                    ),
                    boxShadow: isHighlighted
                        ? [
                            BoxShadow(
                              color: glowColor.withOpacity(0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (PlixTheme.isGlass && widget.backgroundColor == null)
                  PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(8)),
                Center(
                  child: Row(
                    mainAxisSize: widget.width != null ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        IconTheme(
                          data: IconThemeData(color: fgColor, size: 20),
                          child: widget.icon!,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: widget.fontSize ?? 15,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
