import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/plix_device_helper.dart';
import '../widgets/brand_logo.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_bottom_nav.dart';

bool _isActivationKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.gameButtonSelect ||
      key == LogicalKeyboardKey.numpadEnter;
}

/// Standalone Appearance & Visual Themes Screen
/// Fits all 9 atmosphere presets, live preview, and accent color swatches
/// cleanly on screen without scrolling on 1080p Android TV.
class AppearanceScreen extends StatefulWidget {
  final PlexServer? server;
  final String? clientId;

  const AppearanceScreen({
    super.key,
    this.server,
    this.clientId,
  });

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _homeButtonFocusNode = FocusNode();

  final Map<String, FocusNode> _presetFocusNodes = {};
  final Map<String, FocusNode> _colorFocusNodes = {};
  final FocusNode _customColorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    for (final preset in PlixTheme.presetOptions) {
      _presetFocusNodes[preset.id] = FocusNode();
    }
    for (final opt in PlixTheme.colorOptions) {
      _colorFocusNodes[opt.id] = FocusNode();
    }

    // Default focus to active preset
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final activeId = PlixTheme.currentPreset.value.id;
        final targetNode = _presetFocusNodes[activeId] ?? _presetFocusNodes.values.firstOrNull;
        targetNode?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    _homeButtonFocusNode.dispose();
    for (final node in _presetFocusNodes.values) {
      node.dispose();
    }
    for (final node in _colorFocusNodes.values) {
      node.dispose();
    }
    _customColorFocusNode.dispose();
    super.dispose();
  }

  /// Full Custom Theme Configuration Dialog with fixed focus & wider layout
  void _showCustomThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return _CustomThemeEditorDialog(
              onThemeChanged: () {
                setDialogState(() {});
                if (mounted) setState(() {});
              },
            );
          },
        );
      },
    );
  }

  void _showCustomColorDialog() async {
    final col = await _pickColorDialog(
      context,
      'Custom Accent Color',
      PlixTheme.plexGold,
    );
    if (col != null) {
      PlixTheme.setCustomColor(col, 'Custom');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      bottomNavigationBar: (isCompact && !isTv && widget.server != null && widget.clientId != null)
          ? PlixBottomNav(
              currentIndex: 4,
              server: widget.server!,
              clientId: widget.clientId!,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: isCompact ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 36,
              vertical: isCompact ? 10 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Top Bar
              Row(
                children: [
                  if (!Platform.isAndroid || PlixDeviceHelper.isTelevision) ...[
                    PlixBackButton(
                      focusNode: _backButtonFocusNode,
                      autofocus: false,
                      onRight: () => _homeButtonFocusNode.requestFocus(),
                      onDown: () {
                        final activeId = PlixTheme.currentPreset.value.id;
                        _presetFocusNodes[activeId]?.requestFocus();
                      },
                    ),
                    const SizedBox(width: 10),
                    PlixHomeButton(
                      focusNode: _homeButtonFocusNode,
                      onLeft: () => _backButtonFocusNode.requestFocus(),
                      onDown: () {
                        final activeId = PlixTheme.currentPreset.value.id;
                        _presetFocusNodes[activeId]?.requestFocus();
                      },
                    ),
                    const SizedBox(width: 16),
                  ],
                  Icon(
                    Icons.palette_rounded,
                    color: PlixTheme.plexGold,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Appearance & Themes',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Edit Custom Theme Quick Button
                  ValueListenableBuilder<ThemePresetOption>(
                    valueListenable: PlixTheme.currentPreset,
                    builder: (context, activePreset, _) {
                      if (activePreset.id == 'custom') {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: PlixTheme.plexGold,
                              side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.6)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('Edit Custom Palette', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: _showCustomThemeDialog,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Theme Preview Bar
              _LiveThemePreviewBar(),
              const SizedBox(height: 14),

              // Atmosphere Presets Header
              Row(
                children: [
                  Icon(Icons.style_rounded, color: PlixTheme.plexGold, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Base Atmosphere Themes',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Presets Grid
              ValueListenableBuilder<ThemePresetOption>(
                valueListenable: PlixTheme.currentPreset,
                builder: (context, activePreset, _) {
                  final cols = isCompact ? 2 : 4;
                  final totalPresets = PlixTheme.presetOptions.length;
                  final rows = (totalPresets / cols).ceil();

                  return Column(
                    children: [
                      for (int row = 0; row < rows; row++) ...[
                        Row(
                          children: [
                            for (int col = 0; col < cols; col++) ...[
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final index = row * cols + col;
                                    if (index >= totalPresets) {
                                      return const SizedBox();
                                    }
                                    final preset = PlixTheme.presetOptions[index];
                                    return _ThemePresetTile(
                                      preset: preset,
                                      isSelected: preset.id == activePreset.id,
                                      focusNode: _presetFocusNodes[preset.id]!,
                                      onSelect: () {
                                        if (preset.id == 'custom') {
                                          PlixTheme.setPreset(preset, updateDefaultAccent: false);
                                          _showCustomThemeDialog();
                                        } else {
                                          PlixTheme.setPreset(preset);
                                        }
                                      },
                                      onLeft: col > 0
                                          ? () => _presetFocusNodes[PlixTheme.presetOptions[index - 1].id]?.requestFocus()
                                          : null,
                                      onRight: col < cols - 1 && index < totalPresets - 1
                                          ? () => _presetFocusNodes[PlixTheme.presetOptions[index + 1].id]?.requestFocus()
                                          : null,
                                      onUp: row == 0
                                          ? () => _backButtonFocusNode.requestFocus()
                                          : () => _presetFocusNodes[PlixTheme.presetOptions[index - cols].id]?.requestFocus(),
                                      onDown: row == rows - 1
                                          ? () {
                                              final colorCols = isCompact ? 2 : 6;
                                              final targetColorCol = (col * (colorCols / cols)).floor();
                                              if (targetColorCol < PlixTheme.colorOptions.length) {
                                                _colorFocusNodes[PlixTheme.colorOptions[targetColorCol].id]?.requestFocus();
                                              }
                                            }
                                          : () => _presetFocusNodes[PlixTheme.presetOptions[(index + cols).clamp(0, totalPresets - 1)].id]?.requestFocus(),
                                    );
                                  },
                                ),
                              ),
                              if (col < cols - 1) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        if (row < rows - 1) const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 14),

              // Accent Colors Header
              Row(
                children: [
                  Icon(Icons.color_lens_rounded, color: PlixTheme.plexGold, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Accent Highlight Colors',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Accent Colors Grid (3 rows of 6)
              ValueListenableBuilder<ThemeColorOption>(
                valueListenable: PlixTheme.currentThemeOption,
                builder: (context, currentOption, _) {
                  final cols = isCompact ? 2 : 6;
                  final totalItems = PlixTheme.colorOptions.length + 1; // +1 for Custom Color
                  final rows = (totalItems / cols).ceil();
                  final isCustomActive = currentOption.id.startsWith('custom_');

                  FocusNode nodeFor(int idx) {
                    if (idx == totalItems - 1) return _customColorFocusNode;
                    return _colorFocusNodes[PlixTheme.colorOptions[idx].id]!;
                  }

                  return Column(
                    children: [
                      for (int row = 0; row < rows; row++) ...[
                        Row(
                          children: [
                            for (int col = 0; col < cols; col++) ...[
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final index = row * cols + col;
                                    if (index >= totalItems) {
                                      return const SizedBox();
                                    }

                                    final onLeft = col > 0 ? () => nodeFor(index - 1).requestFocus() : null;
                                    final onRight = col < cols - 1 && index < totalItems - 1 ? () => nodeFor(index + 1).requestFocus() : null;
                                    final onUp = row == 0
                                        ? () {
                                            final presetCols = isCompact ? 2 : 4;
                                            final presetRows = (PlixTheme.presetOptions.length / presetCols).ceil();
                                            final targetPresetCol = (col / cols * presetCols).floor().clamp(0, presetCols - 1);
                                            final targetIndex = (presetRows - 1) * presetCols + targetPresetCol;
                                            _presetFocusNodes[PlixTheme.presetOptions[targetIndex.clamp(0, PlixTheme.presetOptions.length - 1)].id]?.requestFocus();
                                          }
                                        : () => nodeFor(index - cols).requestFocus();
                                    final onDown = (row == rows - 1 || index + cols >= totalItems)
                                        ? null
                                        : () => nodeFor(index + cols).requestFocus();

                                    // Custom Color Tile
                                    if (index == totalItems - 1) {
                                      return _CustomColorTile(
                                        isSelected: isCustomActive,
                                        activeColor: isCustomActive ? currentOption.primary : null,
                                        focusNode: _customColorFocusNode,
                                        onSelect: _showCustomColorDialog,
                                        onLeft: onLeft,
                                        onRight: onRight,
                                        onUp: onUp,
                                        onDown: onDown,
                                      );
                                    }

                                    final opt = PlixTheme.colorOptions[index];
                                    return _ThemeColorTile(
                                      option: opt,
                                      isSelected: !isCustomActive && opt.id == currentOption.id,
                                      focusNode: _colorFocusNodes[opt.id]!,
                                      onSelect: () => PlixTheme.setTheme(opt),
                                      onLeft: onLeft,
                                      onRight: onRight,
                                      onUp: onUp,
                                      onDown: onDown,
                                    );
                                  },
                                ),
                              ),
                              if (col < cols - 1) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        if (row < rows - 1) const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Compact Live theme preview bar with liquid glass shine support
class _LiveThemePreviewBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preset = PlixTheme.currentPreset.value;
    final accent = PlixTheme.plexGold;
    final isGlass = preset.isGlass;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: isGlass
          ? PlixTheme.glassBoxDecoration(
              borderRadius: BorderRadius.circular(10),
              isHighlighted: false,
              accent: accent,
            )
          : BoxDecoration(
              color: preset.isOLED ? const Color(0xFF000000) : preset.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: preset.cardBorder,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(10)),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              const PlixAppLogo(size: 22, showWordmark: false, borderRadius: 6),
              const SizedBox(width: 8),
              const Text(
                'Live Preview',
                style: TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 14),
              // Sample mini button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 13, color: Colors.black),
                    SizedBox(width: 3),
                    Text(
                      'Watch',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: isGlass
                    ? BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white24),
                      )
                    : BoxDecoration(
                        color: preset.isOLED ? const Color(0xFF000000) : preset.card,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: preset.cardBorder),
                      ),
                child: const Text(
                  'Details',
                  style: TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

/// Compact Theme Preset Tile (Height 48px)
class _ThemePresetTile extends StatefulWidget {
  final ThemePresetOption preset;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ThemePresetTile({
    required this.preset,
    required this.isSelected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_ThemePresetTile> createState() => _ThemePresetTileState();
}

class _ThemePresetTileState extends State<_ThemePresetTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final accent = PlixTheme.plexGold;
    final isGlass = widget.preset.isGlass;

    final borderColor = isHighlighted
        ? (isGlass ? Colors.white.withOpacity(0.95) : accent)
        : (widget.isSelected ? accent.withOpacity(0.85) : (isGlass ? Colors.white.withOpacity(0.3) : PlixTheme.cardBorder));

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows || Platform.isLinux) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: isGlass
              ? PlixTheme.glassBoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  isHighlighted: isHighlighted,
                  accent: accent,
                  borderWidth: isHighlighted ? 2.0 : 1.2,
                )
              : BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.cardFocused
                      : (widget.preset.isOLED ? const Color(0xFF000000) : PlixTheme.card),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: isHighlighted ? 2.2 : 1.2),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(10)),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.preset.previewGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Icon(widget.preset.icon, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                          fontSize: 12.5,
                          fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.preset.isGlass)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white30, width: 0.8),
                        ),
                        child: const Text('GLASS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.isOLED)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                        child: const Text('OLED', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.isCyberpunk)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: const Color(0xFFFF007F).withOpacity(0.25), borderRadius: BorderRadius.circular(4)),
                        child: const Text('NEON', style: TextStyle(color: Color(0xFFFF007F), fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.isMatrix)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: const Color(0xFF00FF66).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text('MATRIX', style: TextStyle(color: Color(0xFF00FF66), fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.id == 'nebula')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: const Color(0xFF9C27B0).withOpacity(0.25), borderRadius: BorderRadius.circular(4)),
                        child: const Text('COSMIC', style: TextStyle(color: Color(0xFFCE93D8), fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.id == 'solar')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(0.25), borderRadius: BorderRadius.circular(4)),
                        child: const Text('SOLAR', style: TextStyle(color: Color(0xFFFFB74D), fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.id == 'tokyo')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: const Color(0xFFE91E63).withOpacity(0.25), borderRadius: BorderRadius.circular(4)),
                        child: const Text('TOKYO', style: TextStyle(color: Color(0xFFF48FB1), fontSize: 8, fontWeight: FontWeight.bold)),
                      )
                    else if (widget.preset.id == 'custom')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: accent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: Text('EDIT', style: TextStyle(color: accent, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: 6),
                    if (widget.isSelected)
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 11, color: Colors.black),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Theme Accent Color Tile (Height 36px)
class _ThemeColorTile extends StatefulWidget {
  final ThemeColorOption option;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ThemeColorTile({
    required this.option,
    required this.isSelected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_ThemeColorTile> createState() => _ThemeColorTileState();
}

class _ThemeColorTileState extends State<_ThemeColorTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final isGlass = PlixTheme.isGlass;

    final borderColor = isHighlighted
        ? widget.option.primary
        : (widget.isSelected ? widget.option.primary.withOpacity(0.85) : (isGlass ? Colors.white.withOpacity(0.25) : PlixTheme.cardBorder));

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows || Platform.isLinux) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: isGlass
              ? PlixTheme.glassBoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  isHighlighted: isHighlighted,
                  accent: widget.option.primary,
                  borderWidth: isHighlighted ? 1.8 : 1.0,
                )
              : BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.cardFocused
                      : (PlixTheme.isOLED ? const Color(0xFF000000) : PlixTheme.card),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: isHighlighted ? 2.0 : 1.2),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: widget.option.primary.withOpacity(0.35),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(8)),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: widget.option.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 0.8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.isSelected)
                      Icon(Icons.check, size: 12, color: widget.option.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Custom Color Tile (Height 36px)
class _CustomColorTile extends StatefulWidget {
  final bool isSelected;
  final Color? activeColor;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _CustomColorTile({
    required this.isSelected,
    required this.activeColor,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_CustomColorTile> createState() => _CustomColorTileState();
}

class _CustomColorTileState extends State<_CustomColorTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final color = widget.activeColor ?? PlixTheme.plexGold;
    final isGlass = PlixTheme.isGlass;

    final borderColor = isHighlighted
        ? color
        : (widget.isSelected ? color.withOpacity(0.85) : (isGlass ? Colors.white.withOpacity(0.25) : PlixTheme.cardBorder));

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows || Platform.isLinux) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: isGlass
              ? PlixTheme.glassBoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  isHighlighted: isHighlighted,
                  accent: color,
                  borderWidth: isHighlighted ? 1.8 : 1.0,
                )
              : BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.cardFocused
                      : (PlixTheme.isOLED ? const Color(0xFF000000) : PlixTheme.card),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: isHighlighted ? 2.0 : 1.2),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(8)),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: widget.activeColor != null
                            ? null
                            : const SweepGradient(
                                colors: [
                                  Colors.red,
                                  Colors.orange,
                                  Colors.yellow,
                                  Colors.green,
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.red,
                                ],
                              ),
                        color: widget.activeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 0.8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.activeColor != null ? 'Custom' : 'Custom...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.isSelected)
                      Icon(Icons.check, size: 12, color: color),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fully usable Theme Customizer Modal Dialog
/// - Wider modal width (540dp)
/// - Cursor defaults automatically to the top option (Background)
/// - Symmetrical D-pad traversal between all rows and Done button
/// - Done button moved down for aesthetic spacing
class _CustomThemeEditorDialog extends StatefulWidget {
  final VoidCallback onThemeChanged;

  const _CustomThemeEditorDialog({required this.onThemeChanged});

  @override
  State<_CustomThemeEditorDialog> createState() => _CustomThemeEditorDialogState();
}

class _CustomThemeEditorDialogState extends State<_CustomThemeEditorDialog> {
  final FocusNode _bgFocusNode = FocusNode();
  final FocusNode _surfFocusNode = FocusNode();
  final FocusNode _cardFocusNode = FocusNode();
  final FocusNode _borderFocusNode = FocusNode();
  late final FocusNode _doneFocusNode;

  @override
  void initState() {
    super.initState();
    _doneFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            _borderFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    // Default cursor directly to the top option upon opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bgFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _bgFocusNode.dispose();
    _surfFocusNode.dispose();
    _cardFocusNode.dispose();
    _borderFocusNode.dispose();
    _doneFocusNode.dispose();
    super.dispose();
  }

  Widget _buildElementRow({
    required String label,
    required Color currentColor,
    required FocusNode focusNode,
    required FocusNode? upNode,
    required FocusNode? downNode,
    required VoidCallback onEdit,
  }) {
    return _CustomThemeRowTile(
      label: label,
      currentColor: currentColor,
      focusNode: focusNode,
      upNode: upNode,
      downNode: downNode,
      onEdit: onEdit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: PlixTheme.cardBorder, width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28),
      actionsPadding: const EdgeInsets.fromLTRB(28, 20, 28, 28), // Done button moved down for aesthetic spacing
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PlixTheme.plexGold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded, color: PlixTheme.plexGold, size: 24),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customize Atmosphere Colors',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Personalize the background, surfaces, cards, and borders:',
                style: TextStyle(color: PlixTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 560, // Wider modal
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _buildElementRow(
              label: 'Background',
              currentColor: PlixTheme.customBackground,
              focusNode: _bgFocusNode,
              upNode: null,
              downNode: _surfFocusNode,
              onEdit: () async {
                final col = await _pickColorDialog(context, 'Background Color', PlixTheme.customBackground);
                if (col != null) {
                  await PlixTheme.updateCustomTheme(background: col);
                  widget.onThemeChanged();
                  setState(() {});
                }
              },
            ),
            _buildElementRow(
              label: 'Sidebar & Surfaces',
              currentColor: PlixTheme.customSurface,
              focusNode: _surfFocusNode,
              upNode: _bgFocusNode,
              downNode: _cardFocusNode,
              onEdit: () async {
                final col = await _pickColorDialog(context, 'Sidebar & Surfaces Color', PlixTheme.customSurface);
                if (col != null) {
                  await PlixTheme.updateCustomTheme(surface: col);
                  widget.onThemeChanged();
                  setState(() {});
                }
              },
            ),
            _buildElementRow(
              label: 'Cards & Containers',
              currentColor: PlixTheme.customCard,
              focusNode: _cardFocusNode,
              upNode: _surfFocusNode,
              downNode: _borderFocusNode,
              onEdit: () async {
                final col = await _pickColorDialog(context, 'Cards & Containers Color', PlixTheme.customCard);
                if (col != null) {
                  await PlixTheme.updateCustomTheme(card: col);
                  widget.onThemeChanged();
                  setState(() {});
                }
              },
            ),
            _buildElementRow(
              label: 'Card Borders',
              currentColor: PlixTheme.customBorder,
              focusNode: _borderFocusNode,
              upNode: _cardFocusNode,
              downNode: _doneFocusNode,
              onEdit: () async {
                final col = await _pickColorDialog(context, 'Card Borders Color', PlixTheme.customBorder);
                if (col != null) {
                  await PlixTheme.updateCustomTheme(border: col);
                  widget.onThemeChanged();
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        AnimatedBuilder(
          animation: _doneFocusNode,
          builder: (btnCtx, _) {
            final isFocused = _doneFocusNode.hasFocus;
            return ElevatedButton(
              focusNode: _doneFocusNode,
              style: ElevatedButton.styleFrom(
                backgroundColor: isFocused ? Colors.white : PlixTheme.plexGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: isFocused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                ),
                elevation: isFocused ? 8 : 2,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            );
          },
        ),
      ],
    );
  }
}

/// Fully focusable, interactive theme element row card
class _CustomThemeRowTile extends StatefulWidget {
  final String label;
  final Color currentColor;
  final FocusNode focusNode;
  final FocusNode? upNode;
  final FocusNode? downNode;
  final VoidCallback onEdit;

  const _CustomThemeRowTile({
    required this.label,
    required this.currentColor,
    required this.focusNode,
    required this.upNode,
    required this.downNode,
    required this.onEdit,
  });

  @override
  State<_CustomThemeRowTile> createState() => _CustomThemeRowTileState();
}

class _CustomThemeRowTileState extends State<_CustomThemeRowTile> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hex = widget.currentColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    final accent = PlixTheme.plexGold;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp && widget.upNode != null) {
            widget.upNode!.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.downNode != null) {
            widget.downNode!.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            widget.onEdit();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onEdit,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? PlixTheme.cardFocused : PlixTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused ? accent : PlixTheme.cardBorder,
              width: _isFocused ? 2.0 : 1.2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.currentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white30, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: _isFocused ? Colors.white : PlixTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#$hex',
                      style: const TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isFocused ? accent : PlixTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isFocused ? accent : PlixTheme.cardBorder,
                  ),
                ),
                child: Text(
                  'Change',
                  style: TextStyle(
                    color: _isFocused ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fully D-Pad Navigable Color Picker Dialog:
/// - Palette of colors at the top are fully focusable with D-pad
/// - Hex input field with enter-to-apply and right-arrow to reach Apply button
/// - Wider, modern aesthetic design
Future<Color?> _pickColorDialog(BuildContext context, String title, Color initialColor) {
  final textController = TextEditingController(
    text: initialColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
  );

  const customPalette = [
    Color(0xFF000000), Color(0xFF070312), Color(0xFF080D18), Color(0xFF030C07),
    Color(0xFF0A1118), Color(0xFF0E0608), Color(0xFF0F0818), Color(0xFF14151B),
    Color(0xFF1B1D22), Color(0xFF22252C), Color(0xFF2E3340), Color(0xFF384052),
    Color(0xFFE5A00D), Color(0xFF00E5FF), Color(0xFFFF007F), Color(0xFF00FF66),
    Color(0xFF80DEEA), Color(0xFFE50914), Color(0xFFFF6D00), Color(0xFFB388FF),
  ];

  return showDialog<Color>(
    context: context,
    builder: (ctx) {
      return _PalettePickerDialog(
        title: title,
        initialColor: initialColor,
        customPalette: customPalette,
        textController: textController,
      );
    },
  );
}

class _PalettePickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;
  final List<Color> customPalette;
  final TextEditingController textController;

  const _PalettePickerDialog({
    required this.title,
    required this.initialColor,
    required this.customPalette,
    required this.textController,
  });

  @override
  State<_PalettePickerDialog> createState() => _PalettePickerDialogState();
}

class _PalettePickerDialogState extends State<_PalettePickerDialog> {
  final List<FocusNode> _swatchFocusNodes = [];
  late final FocusNode _hexInputFocusNode;
  late final FocusNode _applyBtnFocusNode;
  late final FocusNode _cancelBtnFocusNode;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.customPalette.length; i++) {
      _swatchFocusNodes.add(FocusNode());
    }

    _hexInputFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
            _applyBtnFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            _swatchFocusNodes.last.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _applyBtnFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            _hexInputFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            _swatchFocusNodes.last.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            _cancelBtnFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            _applyHex();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _cancelBtnFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            _applyBtnFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            _hexInputFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            Navigator.of(context).pop(null);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    // Default focus to matching palette swatch or first swatch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        int targetIdx = widget.customPalette.indexWhere((c) => c.value == widget.initialColor.value);
        if (targetIdx == -1) targetIdx = 0;
        _swatchFocusNodes[targetIdx].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _swatchFocusNodes) {
      node.dispose();
    }
    _hexInputFocusNode.dispose();
    _applyBtnFocusNode.dispose();
    _cancelBtnFocusNode.dispose();
    super.dispose();
  }

  void _applyHex() {
    var hex = widget.textController.text.trim().replaceAll('#', '');
    if (hex.length == 3) {
      hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
    }
    if (hex.length == 6) {
      final val = int.tryParse('FF$hex', radix: 16);
      if (val != null) {
        Navigator.of(context).pop(Color(val));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const cols = 5;
    final totalSwatches = widget.customPalette.length;
    final rows = (totalSwatches / cols).ceil();

    return AlertDialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PlixTheme.cardBorder, width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Icon(Icons.palette_outlined, color: PlixTheme.plexGold, size: 22),
          const SizedBox(width: 10),
          Text(
            widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 460, // Wider content area
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a hue from the palette or enter a 6-character hex code:',
              style: TextStyle(color: PlixTheme.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),

            // Swatches Grid with full D-Pad navigation
            Column(
              children: [
                for (int r = 0; r < rows; r++) ...[
                  Row(
                    children: [
                      for (int c = 0; c < cols; c++) ...[
                        Builder(
                          builder: (context) {
                            final idx = r * cols + c;
                            if (idx >= totalSwatches) return const Spacer();
                            final col = widget.customPalette[idx];
                            final isSelected = widget.initialColor.value == col.value;

                            return Expanded(
                              child: _FocusableColorSwatch(
                                color: col,
                                isSelected: isSelected,
                                focusNode: _swatchFocusNodes[idx],
                                onSelect: () => Navigator.of(context).pop(col),
                                onLeft: c > 0 ? () => _swatchFocusNodes[idx - 1].requestFocus() : null,
                                onRight: c < cols - 1 && idx < totalSwatches - 1
                                    ? () => _swatchFocusNodes[idx + 1].requestFocus()
                                    : null,
                                onUp: r > 0 ? () => _swatchFocusNodes[idx - cols].requestFocus() : null,
                                onDown: r == rows - 1
                                    ? () => _hexInputFocusNode.requestFocus()
                                    : () => _swatchFocusNodes[(idx + cols).clamp(0, totalSwatches - 1)].requestFocus(),
                              ),
                            );
                          },
                        ),
                        if (c < cols - 1) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  if (r < rows - 1) const SizedBox(height: 8),
                ],
              ],
            ),

            const SizedBox(height: 18),

            // Custom Hex Input with dedicated reachable Apply button
            Row(
              children: [
                const Text('#', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    focusNode: _hexInputFocusNode,
                    controller: widget.textController,
                    maxLength: 6,
                    onSubmitted: (_) => _applyHex(),
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'RRGGBB',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: PlixTheme.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PlixTheme.cardBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PlixTheme.plexGold, width: 2)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedBuilder(
                  animation: _applyBtnFocusNode,
                  builder: (ctx, _) {
                    final isFocused = _applyBtnFocusNode.hasFocus;
                    return ElevatedButton(
                      focusNode: _applyBtnFocusNode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFocused ? Colors.white : PlixTheme.plexGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: isFocused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                        ),
                        elevation: isFocused ? 8 : 2,
                      ),
                      onPressed: _applyHex,
                      child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AnimatedBuilder(
          animation: _cancelBtnFocusNode,
          builder: (ctx, _) {
            final isFocused = _cancelBtnFocusNode.hasFocus;
            return TextButton(
              focusNode: _cancelBtnFocusNode,
              style: TextButton.styleFrom(
                foregroundColor: isFocused ? Colors.white : PlixTheme.textSecondary,
                backgroundColor: isFocused ? Colors.white12 : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isFocused ? const BorderSide(color: Colors.white54, width: 1.5) : BorderSide.none,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            );
          },
        ),
      ],
    );
  }
}

/// D-pad focusable color swatch item
class _FocusableColorSwatch extends StatefulWidget {
  final Color color;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _FocusableColorSwatch({
    required this.color,
    required this.isSelected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_FocusableColorSwatch> createState() => _FocusableColorSwatchState();
}

class _FocusableColorSwatchState extends State<_FocusableColorSwatch> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && _isActivationKey(key)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : (widget.isSelected ? Colors.white70 : Colors.black45),
              width: _isFocused ? 3.0 : (widget.isSelected ? 2.0 : 1.0),
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.6),
                      blurRadius: 10,
                      spreadRadius: 1.5,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.isSelected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
