import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plix_profile.dart';
import '../services/plix_device_helper.dart';
import 'profile_avatar_widget.dart';

bool handlePinKeyEvent(KeyEvent event, ValueChanged<String> onDigit, VoidCallback onBackspace) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  String? digit;
  if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
    digit = '0';
  } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
    digit = '1';
  } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
    digit = '2';
  } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
    digit = '3';
  } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
    digit = '4';
  } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
    digit = '5';
  } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
    digit = '6';
  } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
    digit = '7';
  } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
    digit = '8';
  } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
    digit = '9';
  } else if (event.character != null && RegExp(r'^[0-9]$').hasMatch(event.character!)) {
    digit = event.character;
  }

  if (digit != null) {
    onDigit(digit);
    return true;
  }

  if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
    onBackspace();
    return true;
  }
  return false;
}

class PinIndicatorDots extends StatelessWidget {
  final int pinLength;
  final bool hasError;
  final double dotSize;

  const PinIndicatorDots({
    super.key,
    required this.pinLength,
    this.hasError = false,
    this.dotSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < pinLength;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasError
                ? Colors.redAccent
                : isFilled
                    ? PlixTheme.plexGold
                    : Colors.transparent,
            border: Border.all(
              color: hasError
                  ? Colors.redAccent
                  : isFilled
                      ? PlixTheme.plexGold
                      : PlixTheme.textMuted.withOpacity(0.4),
              width: 2,
            ),
            boxShadow: isFilled && !hasError
                ? [
                    BoxShadow(
                      color: PlixTheme.plexGold.withOpacity(0.55),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

bool handleKeypadDirection(int index, LogicalKeyboardKey key, List<FocusNode> nodes, FocusNode? cancelNode) {
  FocusNode? target;
  if (key == LogicalKeyboardKey.arrowRight) {
    switch (index) {
      case 0: target = nodes[1]; break;
      case 1: target = nodes[2]; break;
      case 3: target = nodes[4]; break;
      case 4: target = nodes[5]; break;
      case 6: target = nodes[7]; break;
      case 7: target = nodes[8]; break;
      case 9: target = nodes[10]; break;
    }
  } else if (key == LogicalKeyboardKey.arrowLeft) {
    switch (index) {
      case 1: target = nodes[0]; break;
      case 2: target = nodes[1]; break;
      case 4: target = nodes[3]; break;
      case 5: target = nodes[4]; break;
      case 7: target = nodes[6]; break;
      case 8: target = nodes[7]; break;
      case 10: target = nodes[9]; break;
    }
  } else if (key == LogicalKeyboardKey.arrowDown) {
    switch (index) {
      case 0: target = nodes[3]; break;
      case 1: target = nodes[4]; break;
      case 2: target = nodes[5]; break;
      case 3: target = nodes[6]; break;
      case 4: target = nodes[7]; break;
      case 5: target = nodes[8]; break;
      case 6:
      case 7: target = nodes[9]; break;
      case 8: target = nodes[10]; break;
      case 9:
      case 10: target = cancelNode; break;
    }
  } else if (key == LogicalKeyboardKey.arrowUp) {
    switch (index) {
      case 3: target = nodes[0]; break;
      case 4: target = nodes[1]; break;
      case 5: target = nodes[2]; break;
      case 6: target = nodes[3]; break;
      case 7: target = nodes[4]; break;
      case 8: target = nodes[5]; break;
      case 9: target = nodes[7]; break;
      case 10: target = nodes[8]; break;
    }
  }
  if (target != null && target.canRequestFocus) {
    target.requestFocus();
    return true;
  }
  return false;
}

class PinKeypadWidget extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspace;
  final FocusNode? cancelFocusNode;
  final double keyWidth;
  final double keyHeight;

  const PinKeypadWidget({
    super.key,
    required this.focusNodes,
    required this.onDigitPressed,
    required this.onBackspace,
    this.cancelFocusNode,
    this.keyWidth = 62,
    this.keyHeight = 44,
  });

  Widget _buildKey(String label, int index) {
    return Container(
      width: keyWidth,
      height: keyHeight,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      child: Focus(
        focusNode: focusNodes[index],
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space ||
                key == LogicalKeyboardKey.gameButtonA) {
              onDigitPressed(label);
              return KeyEventResult.handled;
            }
            if (handleKeypadDirection(index, key, focusNodes, cancelFocusNode)) {
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final isFocused = Focus.of(context).hasFocus;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(12),
                onTap: () => onDigitPressed(label),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isFocused
                        ? PlixTheme.plexGold.withOpacity(0.25)
                        : PlixTheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: isFocused ? 2.5 : 1,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: PlixTheme.plexGold.withOpacity(0.4),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isFocused ? PlixTheme.plexGold : PlixTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackspaceKey(int index) {
    return Container(
      width: keyWidth,
      height: keyHeight,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      child: Focus(
        focusNode: focusNodes[index],
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space ||
                key == LogicalKeyboardKey.gameButtonA) {
              onBackspace();
              return KeyEventResult.handled;
            }
            if (handleKeypadDirection(index, key, focusNodes, cancelFocusNode)) {
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final isFocused = Focus.of(context).hasFocus;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(12),
                onTap: onBackspace,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isFocused
                        ? PlixTheme.plexGold.withOpacity(0.25)
                        : PlixTheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: isFocused ? 2.5 : 1,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: PlixTheme.plexGold.withOpacity(0.4),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.backspace_rounded,
                    size: 18,
                    color: isFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slotWidth = keyWidth + 10;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey('1', 0),
            _buildKey('2', 1),
            _buildKey('3', 2),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey('4', 3),
            _buildKey('5', 4),
            _buildKey('6', 5),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey('7', 6),
            _buildKey('8', 7),
            _buildKey('9', 8),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: slotWidth, height: keyHeight),
            _buildKey('0', 9),
            _buildBackspaceKey(10),
          ],
        ),
      ],
    );
  }
}

class PinDialog extends StatefulWidget {
  final PlixProfile profile;

  const PinDialog({super.key, required this.profile});

  static Future<bool> show(BuildContext context, PlixProfile profile) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => PinDialog(profile: profile),
    );
    return result ?? false;
  }

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  String _enteredPin = '';
  String? _errorMessage;
  final List<FocusNode> _numFocusNodes = List.generate(11, (_) => FocusNode());
  final FocusNode _cancelFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (PlixDeviceHelper.isTelevision || PlixDeviceHelper.isDesktop)) {
        _numFocusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _numFocusNodes) {
      node.dispose();
    }
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += digit;
        _errorMessage = null;
      });
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _verifyPin() {
    if (_enteredPin == widget.profile.pin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _enteredPin = '';
        _errorMessage = 'Incorrect PIN. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Focus(
          onKeyEvent: (node, event) {
            final handled = handlePinKeyEvent(event, _onDigitPressed, _onBackspace);
            return handled ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: Container(
            width: 360,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: PlixTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: PlixTheme.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfileAvatarWidget(
                  avatarId: widget.profile.avatarId,
                  avatarColorId: widget.profile.avatarColorId,
                  size: 68,
                  glow: true,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter 4-Digit PIN to Switch',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                // PIN Indicator Dots
                PinIndicatorDots(
                  pinLength: _enteredPin.length,
                  hasError: _errorMessage != null,
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Numeric Keypad
                PinKeypadWidget(
                  focusNodes: _numFocusNodes,
                  cancelFocusNode: _cancelFocusNode,
                  onDigitPressed: _onDigitPressed,
                  onBackspace: _onBackspace,
                ),

                const SizedBox(height: 14),
                Focus(
                  focusNode: _cancelFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowUp) {
                        _numFocusNodes[9].requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.space ||
                          key == LogicalKeyboardKey.gameButtonA) {
                        Navigator.of(context).pop(false);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final isFocused = Focus.of(context).hasFocus;
                      return TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          backgroundColor: isFocused ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
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

class PinSetupDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const PinSetupDialog({
    super.key,
    this.title = 'Set 4-Digit PIN',
    this.subtitle = 'Enter 4 digits for your profile lock',
  });

  static Future<String?> show(
    BuildContext context, {
    String title = 'Set 4-Digit PIN',
    String subtitle = 'Enter 4 digits for your profile lock',
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => PinSetupDialog(title: title, subtitle: subtitle),
    );
    return result;
  }

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  String _enteredPin = '';
  final List<FocusNode> _numFocusNodes = List.generate(11, (_) => FocusNode());
  final FocusNode _cancelFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (PlixDeviceHelper.isTelevision || PlixDeviceHelper.isDesktop)) {
        _numFocusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _numFocusNodes) {
      node.dispose();
    }
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += digit;
      });
      if (_enteredPin.length == 4) {
        Navigator.of(context).pop(_enteredPin);
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Focus(
          onKeyEvent: (node, event) {
            final handled = handlePinKeyEvent(event, _onDigitPressed, _onBackspace);
            return handled ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: Container(
            width: 360,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: PlixTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: PlixTheme.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PlixTheme.plexGold.withOpacity(0.15),
                    border: Border.all(color: PlixTheme.plexGold, width: 2),
                  ),
                  child: Icon(Icons.lock_outline_rounded, color: PlixTheme.plexGold, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                // PIN Indicator Dots
                PinIndicatorDots(
                  pinLength: _enteredPin.length,
                ),

                const SizedBox(height: 18),

                // Numeric Keypad
                PinKeypadWidget(
                  focusNodes: _numFocusNodes,
                  cancelFocusNode: _cancelFocusNode,
                  onDigitPressed: _onDigitPressed,
                  onBackspace: _onBackspace,
                ),

                const SizedBox(height: 14),
                Focus(
                  focusNode: _cancelFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowUp) {
                        _numFocusNodes[9].requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.space ||
                          key == LogicalKeyboardKey.gameButtonA) {
                        Navigator.of(context).pop(null);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final isFocused = Focus.of(context).hasFocus;
                      return TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: TextButton.styleFrom(
                          backgroundColor: isFocused ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
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
