import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plix_profile.dart';
import '../services/custom_avatar_service.dart';
import 'plix_tv_text_field.dart';

class CustomAvatarUploadDialog extends StatefulWidget {
  const CustomAvatarUploadDialog({super.key});

  static Future<AvatarOption?> show(BuildContext context) {
    return showDialog<AvatarOption>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (_) => const CustomAvatarUploadDialog(),
    );
  }

  @override
  State<CustomAvatarUploadDialog> createState() => _CustomAvatarUploadDialogState();
}

class _CustomAvatarUploadDialogState extends State<CustomAvatarUploadDialog> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _fileButtonFocusNode = FocusNode();
  late final FocusNode _urlFocusNode;
  final FocusNode _applyFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();

  bool _isLoading = false;
  String? _loadingMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            _fileButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            _applyFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _urlFocusNode.addListener(_onUrlFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fileButtonFocusNode.requestFocus();
      }
    });
  }

  void _onUrlFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _urlController.dispose();
    _fileButtonFocusNode.dispose();
    _urlFocusNode.dispose();
    _applyFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePickFile() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Selecting image...';
      _errorMessage = null;
    });

    try {
      final avatar = await CustomAvatarService.pickFromFile();
      if (!mounted) return;
      if (avatar != null) {
        Navigator.of(context).pop(avatar);
      } else {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      _fileButtonFocusNode.requestFocus();
    }
  }

  Future<void> _handleApplyUrl() async {
    if (_isLoading) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter an image URL.');
      _urlFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Downloading image...';
      _errorMessage = null;
    });

    try {
      final avatar = await CustomAvatarService.downloadFromUrl(url);
      if (!mounted) return;
      Navigator.of(context).pop(avatar);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      _urlFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0 || _urlFocusNode.hasFocus;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: isKeyboardOpen ? const Alignment(0, -0.65) : Alignment.center,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: BoxDecoration(
                color: PlixTheme.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: PlixTheme.cardBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 30,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: PlixTheme.plexGold.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_rounded,
                        color: Color(0xFFE5A00D),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Custom Avatar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Choose an image file or enter a web URL',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: PlixTheme.textMuted, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Error Message if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.4), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 1. Choose Image File Button
                Focus(
                  focusNode: _fileButtonFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _urlFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (key == LogicalKeyboardKey.select ||
                          key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.space ||
                          key == LogicalKeyboardKey.gameButtonA) {
                        _handlePickFile();
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
                          onTap: _isLoading ? null : _handlePickFile,
                          borderRadius: BorderRadius.circular(12),
                          canRequestFocus: false,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? PlixTheme.plexGold.withOpacity(0.15)
                                  : PlixTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                                width: isFocused ? 2.5 : 1.0,
                              ),
                              boxShadow: isFocused
                                  ? [
                                      BoxShadow(
                                        color: PlixTheme.plexGold.withOpacity(0.35),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.file_upload_outlined,
                                  color: isFocused ? PlixTheme.plexGold : PlixTheme.textPrimary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Choose Image File',
                                      style: TextStyle(
                                        color: isFocused ? PlixTheme.plexGold : PlixTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'PNG, JPG, WEBP, GIF · Max 10 MB',
                                      style: TextStyle(
                                        color: PlixTheme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Divider OR
                Row(
                  children: [
                    Expanded(
                      child: Divider(color: Colors.white.withOpacity(0.12), thickness: 1),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR ENTER URL',
                        style: TextStyle(
                          color: PlixTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(color: Colors.white.withOpacity(0.12), thickness: 1),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 2. URL Input Field
                AnimatedBuilder(
                  animation: _urlFocusNode,
                  builder: (context, _) {
                    final isFocused = _urlFocusNode.hasFocus;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: PlixTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                          width: isFocused ? 2.5 : 1.0,
                        ),
                        boxShadow: isFocused
                            ? [
                                BoxShadow(
                                  color: PlixTheme.plexGold.withOpacity(0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, color: Colors.white54, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 26,
                              child: PlixTvTextField(
                                controller: _urlController,
                                focusNode: _urlFocusNode,
                                hintText: 'https://example.com/avatar.png',
                                imeAction: 'done',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                                onUp: () => _fileButtonFocusNode.requestFocus(),
                                onDown: () => _applyFocusNode.requestFocus(),
                                onSubmitted: (_) => _handleApplyUrl(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // Loading Status or Actions
                if (_isLoading) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PlixTheme.plexGold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _loadingMessage ?? 'Processing...',
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel Button
                      Focus(
                        focusNode: _cancelFocusNode,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowRight) {
                              _applyFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _urlFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter ||
                                key == LogicalKeyboardKey.space ||
                                key == LogicalKeyboardKey.gameButtonA) {
                              Navigator.of(context).pop();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final isFocused = Focus.of(context).hasFocus;
                            return OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                                  width: isFocused ? 2.0 : 1.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Apply Button
                      Focus(
                        focusNode: _applyFocusNode,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              _cancelFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _urlFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.select ||
                                key == LogicalKeyboardKey.enter ||
                                key == LogicalKeyboardKey.space ||
                                key == LogicalKeyboardKey.gameButtonA) {
                              _handleApplyUrl();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final isFocused = Focus.of(context).hasFocus;
                            return ElevatedButton(
                              onPressed: _handleApplyUrl,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: PlixTheme.plexGold,
                                foregroundColor: Colors.black,
                                elevation: isFocused ? 6 : 0,
                                shadowColor: PlixTheme.plexGold.withOpacity(0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: isFocused
                                      ? const BorderSide(color: Colors.white, width: 2.0)
                                      : BorderSide.none,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              ),
                              child: const Text(
                                'Apply',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
