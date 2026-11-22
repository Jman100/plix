import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../services/plix_device_helper.dart';

class PlixBackButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final bool forceShow;

  const PlixBackButton({
    super.key,
    this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
    this.forceShow = false,
  });

  @override
  State<PlixBackButton> createState() => _PlixBackButtonState();
}

class _PlixBackButtonState extends State<PlixBackButton> {
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
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (!widget.forceShow && Platform.isAndroid && !PlixDeviceHelper.isTelevision && !isLandscape) {
      return const SizedBox.shrink();
    }
    final isHighlighted = _isFocused || _isHovered;

    final isGlass = PlixTheme.isGlassSidebar;
    final isBlur = isGlass && PlixTheme.isGlassSidebarBlur;
    final isRainbow = PlixTheme.isRainbow;
    final alpha = PlixTheme.glassButtonAlpha;

    final btnContainer = AnimatedContainer(
      duration: PlixDeviceHelper.isTelevision ? Duration.zero : const Duration(milliseconds: 150),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isRainbow && isHighlighted
            ? null
            : (isGlass
                ? (isHighlighted
                    ? PlixTheme.cardFocused.withAlpha((alpha + 0x40).clamp(0, 255))
                    : Colors.black.withAlpha((alpha * 0.7).round()))
                : (isHighlighted ? PlixTheme.cardFocused : Colors.black45)),
        gradient: isRainbow && isHighlighted
            ? (isGlass
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFF007A).withAlpha((alpha + 0x40).clamp(0, 255)),
                      const Color(0xFF7928CA).withAlpha((alpha + 0x40).clamp(0, 255)),
                      const Color(0xFF0070F3).withAlpha((alpha + 0x40).clamp(0, 255)),
                      const Color(0xFF00E676).withAlpha((alpha + 0x40).clamp(0, 255)),
                      const Color(0xFFFFB300).withAlpha((alpha + 0x40).clamp(0, 255)),
                    ],
                  )
                : PlixTheme.rainbowButtonGradient)
            : null,
        border: isHighlighted
            ? (PlixTheme.isRainbowBorder
                ? PlixTheme.rainbowOutlineBorder(width: 2.5)
                : Border.all(color: PlixTheme.plexGold, width: 2.5))
            : Border.all(
                color: isGlass ? Colors.white.withOpacity(0.25) : Colors.white24,
                width: 1.5,
              ),
        boxShadow: (isHighlighted && !PlixTheme.isRainbowBorder)
            ? [
                BoxShadow(
                  color: PlixTheme.plexGold.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.arrow_back,
        color: isHighlighted
            ? (isRainbow ? Colors.white : PlixTheme.plexGold)
            : Colors.white,
        size: 22,
      ),
    );

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
          child: ClipOval(
            child: isBlur
                ? BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: PlixTheme.glassSidebarBlurSigma,
                      sigmaY: PlixTheme.glassSidebarBlurSigma,
                    ),
                    child: btnContainer,
                  )
                : btnContainer,
          ),
        ),
      ),
    );
  }
}
