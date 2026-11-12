import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plix_profile.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/profile_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/brand_logo.dart';
import '../widgets/profile_avatar_widget.dart';
import '../widgets/pin_dialog.dart';
import 'auth_chooser_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;
  final PlixProfile? profileToEdit;
  final bool isInitialSetup;

  const ProfileSetupScreen({
    super.key,
    required this.authService,
    required this.serverService,
    this.profileToEdit,
    this.isInitialSetup = false,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late TextEditingController _nameController;
  late String _selectedAvatarId;
  late String _selectedColorId;
  late bool _enablePin;
  String _pinValue = '';
  String? _errorMessage;
  bool _isSaving = false;

  final FocusNode _backFocusNode = FocusNode();
  final FocusNode _nameBoxFocusNode = FocusNode();
  late final FocusNode _nameInputFocusNode;
  final FocusNode _pinToggleFocusNode = FocusNode();
  final FocusNode _saveFocusNode = FocusNode();
  final FocusNode _deleteFocusNode = FocusNode();

  final Map<String, FocusNode> _avatarFocusNodes = {};
  late final ScrollController _avatarScrollController;

  final Map<String, FocusNode> _colorFocusNodes = {};
  late final ScrollController _colorScrollController;

  bool get isEditing => widget.profileToEdit != null;

  @override
  void initState() {
    super.initState();
    PlixTheme.resetToDefaultModern();

    final profile = widget.profileToEdit;
    _nameController = TextEditingController(text: profile?.name ?? (widget.isInitialSetup ? 'Home' : ''));
    _selectedAvatarId = profile?.avatarId ?? (widget.isInitialSetup ? 'avatar_default' : 'avatar_popcorn');
    _selectedColorId = profile?.avatarColorId ?? 'gradient_gold';
    _enablePin = profile?.hasPin ?? false;
    _pinValue = profile?.pin ?? '';

    // Calculate initial scroll position for avatars so current selection is visible immediately
    final selectedIdx = PlixProfile.availableAvatars.indexWhere((a) => a.id == _selectedAvatarId);
    final double initialAvatarOffset = selectedIdx > 0 ? ((selectedIdx * 96.0) - 180.0).clamp(0.0, 4000.0) : 0.0;
    _avatarScrollController = ScrollController(initialScrollOffset: initialAvatarOffset);

    // Calculate initial scroll position for colors
    final colIdx = ProfileGradientOption.availableGradients.indexWhere((g) => g.id == _selectedColorId);
    final double initialColorOffset = colIdx > 0 ? ((colIdx * 64.0) - 140.0).clamp(0.0, 3000.0) : 0.0;
    _colorScrollController = ScrollController(initialScrollOffset: initialColorOffset);

    _nameInputFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            _nameInputFocusNode.unfocus();
            final target = _avatarFocusNodes[_selectedAvatarId] ?? _avatarFocusNodes.values.first;
            target.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            _nameInputFocusNode.unfocus();
            if (!widget.isInitialSetup) {
              _backFocusNode.requestFocus();
            } else {
              _nameBoxFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    for (final avatar in PlixProfile.availableAvatars) {
      _avatarFocusNodes[avatar.id] = FocusNode();
    }

    for (final grad in ProfileGradientOption.availableGradients) {
      _colorFocusNodes[grad.id] = FocusNode();
    }

    // Default focus to name box without automatically showing keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameBoxFocusNode.requestFocus();
        if (_avatarScrollController.hasClients && initialAvatarOffset > 0) {
          _avatarScrollController.jumpTo(
            initialAvatarOffset.clamp(0.0, _avatarScrollController.position.maxScrollExtent),
          );
        }
        if (_colorScrollController.hasClients && initialColorOffset > 0) {
          _colorScrollController.jumpTo(
            initialColorOffset.clamp(0.0, _colorScrollController.position.maxScrollExtent),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _backFocusNode.dispose();
    _nameBoxFocusNode.dispose();
    _nameInputFocusNode.dispose();
    _pinToggleFocusNode.dispose();
    _saveFocusNode.dispose();
    _deleteFocusNode.dispose();
    for (final node in _avatarFocusNodes.values) {
      node.dispose();
    }
    _avatarScrollController.dispose();
    for (final node in _colorFocusNodes.values) {
      node.dispose();
    }
    _colorScrollController.dispose();
    super.dispose();
  }

  Future<void> _togglePin() async {
    if (_enablePin) {
      setState(() {
        _enablePin = false;
        _pinValue = '';
      });
    } else {
      final pin = await PinSetupDialog.show(
        context,
        title: 'Set Profile PIN',
        subtitle: 'Enter a 4-digit PIN to lock this profile',
      );
      if (pin != null && pin.length == 4) {
        setState(() {
          _enablePin = true;
          _pinValue = pin;
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a profile name.');
      _nameBoxFocusNode.requestFocus();
      return;
    }

    if (name.length > 20) {
      setState(() => _errorMessage = 'Profile name cannot exceed 20 characters.');
      _nameBoxFocusNode.requestFocus();
      return;
    }

    if (_enablePin && _pinValue.length != 4) {
      setState(() => _errorMessage = 'PIN must be exactly 4 digits.');
      _pinToggleFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (isEditing) {
        final updated = widget.profileToEdit!.copyWith(
          name: name,
          avatarId: _selectedAvatarId,
          avatarColorId: _selectedColorId,
          pin: _enablePin ? _pinValue : null,
          clearPin: !_enablePin,
        );
        await ProfileService.instance.updateProfile(updated);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        final newProfile = await ProfileService.instance.createProfile(
          name: name,
          avatarId: _selectedAvatarId,
          avatarColorId: _selectedColorId,
          pin: _enablePin ? _pinValue : null,
        );

        if (!mounted) return;

        // Switch to the newly created profile
        await ProfileService.instance.setActiveProfile(newProfile.id);
        widget.authService.clearCache();

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AuthChooserScreen(
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to save profile: $e';
      });
    }
  }

  Future<void> _handleDelete() async {
    if (!isEditing || ProfileService.instance.profiles.length <= 1) return;

    final cancelFocusNode = FocusNode();
    final deleteFocusNode = FocusNode();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          cancelFocusNode.requestFocus();
        });
        return AlertDialog(
          backgroundColor: PlixTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: PlixTheme.cardBorder),
          ),
          title: const Text('Delete Profile?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to delete "${widget.profileToEdit!.name}"? All server connections and settings for this profile will be permanently removed.',
            style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
          ),
          actions: [
            Focus(
              focusNode: cancelFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    deleteFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space ||
                      event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                    Navigator.of(ctx).pop(false);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (btnCtx) {
                  final isFocused = Focus.of(btnCtx).hasFocus;
                  return OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isFocused ? PlixTheme.plexGold.withOpacity(0.18) : Colors.transparent,
                      foregroundColor: isFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                      side: BorderSide(
                        color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                        width: isFocused ? 2.5 : 1.0,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            Focus(
              focusNode: deleteFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    cancelFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space ||
                      event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                    Navigator.of(ctx).pop(true);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (btnCtx) {
                  final isFocused = Focus.of(btnCtx).hasFocus;
                  return OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isFocused ? Colors.redAccent : Colors.transparent,
                      foregroundColor: isFocused ? Colors.white : Colors.redAccent,
                      side: BorderSide(
                        color: Colors.redAccent,
                        width: isFocused ? 2.5 : 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await ProfileService.instance.deleteProfile(widget.profileToEdit!.id);
      widget.authService.clearCache();
      await PlixTheme.loadSavedTheme();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  if (!widget.isInitialSetup)
                    PlixBackButton(
                      focusNode: _backFocusNode,
                      onPressed: () => Navigator.of(context).pop(false),
                      onDown: () => _nameBoxFocusNode.requestFocus(),
                    )
                  else
                    const PlixAppLogo(size: 28, showWordmark: false),
                  const SizedBox(width: 12),
                  Text(
                    isEditing
                        ? 'Customize Profile'
                        : widget.isInitialSetup
                            ? 'Create Your Profile'
                            : 'New Profile',
                    style: const TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (widget.isInitialSetup)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: PlixTheme.plexGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PlixTheme.plexGold.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Step 1 of 3',
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Divider(color: PlixTheme.cardBorder, height: 1),

            // Main Body Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Chosen Avatar Preview on Left + Profile Name Box on Right (Centered)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ProfileAvatarWidget(
                                avatarId: _selectedAvatarId,
                                avatarColorId: _selectedColorId,
                                size: 80,
                                glow: true,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'PROFILE NAME',
                                          style: TextStyle(
                                            color: PlixTheme.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                        Text(
                                          'Max 20 chars',
                                          style: TextStyle(
                                            color: PlixTheme.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Focus(
                                      focusNode: _nameBoxFocusNode,
                                      onKeyEvent: (node, event) {
                                        if (event is KeyDownEvent) {
                                          final key = event.logicalKey;
                                          if (key == LogicalKeyboardKey.arrowDown) {
                                            final targetAvatar = _avatarFocusNodes[_selectedAvatarId] ?? _avatarFocusNodes.values.first;
                                            targetAvatar.requestFocus();
                                            return KeyEventResult.handled;
                                          }
                                          if (key == LogicalKeyboardKey.arrowUp && !widget.isInitialSetup) {
                                            _backFocusNode.requestFocus();
                                            return KeyEventResult.handled;
                                          }
                                          if (key == LogicalKeyboardKey.select ||
                                              key == LogicalKeyboardKey.enter ||
                                              key == LogicalKeyboardKey.space ||
                                              key == LogicalKeyboardKey.gameButtonA) {
                                            _nameInputFocusNode.requestFocus();
                                            SystemChannels.textInput.invokeMethod('TextInput.show');
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final isBoxFocused = Focus.of(context).hasFocus;
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: isBoxFocused ? PlixTheme.surface : PlixTheme.surface.withOpacity(0.7),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isBoxFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                                                width: isBoxFocused ? 2.5 : 1.0,
                                              ),
                                              boxShadow: isBoxFocused
                                                  ? [
                                                      BoxShadow(
                                                        color: PlixTheme.plexGold.withOpacity(0.35),
                                                        blurRadius: 10,
                                                        spreadRadius: 1,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: TextField(
                                              controller: _nameController,
                                              focusNode: _nameInputFocusNode,
                                              maxLength: 20,
                                              style: const TextStyle(
                                                color: PlixTheme.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              decoration: const InputDecoration(
                                                hintText: 'Enter name (e.g. Living Room, Josh)',
                                                hintStyle: TextStyle(color: PlixTheme.textMuted, fontSize: 13),
                                                counterText: '',
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                              ),
                                              onSubmitted: (_) {
                                                _nameBoxFocusNode.requestFocus();
                                              },
                                            ),
                                          );
                                        },
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

                    const SizedBox(height: 12),

                    // 2. Avatar Icon Picker (Full width, larger 78px images, no clipping)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'CHOOSE ICON',
                          style: TextStyle(
                            color: PlixTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 122,
                      child: ListView.separated(
                        controller: _avatarScrollController,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: PlixProfile.availableAvatars.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final avatar = PlixProfile.availableAvatars[index];
                          final isSelected = _selectedAvatarId == avatar.id;
                          final focusNode = _avatarFocusNodes[avatar.id]!;

                          return Focus(
                            focusNode: focusNode,
                            onFocusChange: (hasF) {
                              if (hasF) {
                                final targetOffset = (index * 92.0) - 180.0;
                                _avatarScrollController.animateTo(
                                  targetOffset.clamp(0.0, _avatarScrollController.position.maxScrollExtent),
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              setState(() {});
                            },
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.arrowLeft && index == 0) {
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowRight && index == PlixProfile.availableAvatars.length - 1) {
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowDown) {
                                  final colTarget = _colorFocusNodes[_selectedColorId] ?? _colorFocusNodes.values.first;
                                  colTarget.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowUp) {
                                  _nameBoxFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space ||
                                    key == LogicalKeyboardKey.gameButtonA) {
                                  setState(() => _selectedAvatarId = avatar.id);
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isAvatarFocused = Focus.of(context).hasFocus;
                                return InkWell(
                                  onTap: () => setState(() => _selectedAvatarId = avatar.id),
                                  customBorder: const CircleBorder(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ProfileAvatarWidget(
                                        avatarId: avatar.id,
                                        avatarColorId: _selectedColorId,
                                        size: 76,
                                        isSelected: isSelected,
                                        isFocused: isAvatarFocused,
                                        glow: isAvatarFocused || isSelected,
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          avatar.label,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected ? PlixTheme.plexGold : PlixTheme.textSecondary,
                                            fontSize: 11,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 3. Background Color Picker (Full width, gradient circles)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'CHOOSE BACKGROUND COLOR',
                          style: TextStyle(
                            color: PlixTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        controller: _colorScrollController,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: ProfileGradientOption.availableGradients.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final gradientOpt = ProfileGradientOption.availableGradients[index];
                          final isSelected = _selectedColorId == gradientOpt.id;
                          final focusNode = _colorFocusNodes[gradientOpt.id]!;

                          return Focus(
                            focusNode: focusNode,
                            onFocusChange: (hasF) {
                              if (hasF) {
                                final targetOffset = (index * 62.0) - 140.0;
                                _colorScrollController.animateTo(
                                  targetOffset.clamp(0.0, _colorScrollController.position.maxScrollExtent),
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              setState(() {});
                            },
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.arrowLeft && index == 0) {
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowRight && index == ProfileGradientOption.availableGradients.length - 1) {
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowDown) {
                                  _pinToggleFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowUp) {
                                  final avTarget = _avatarFocusNodes[_selectedAvatarId] ?? _avatarFocusNodes.values.first;
                                  avTarget.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space ||
                                    key == LogicalKeyboardKey.gameButtonA) {
                                  setState(() => _selectedColorId = gradientOpt.id);
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isColorFocused = Focus.of(context).hasFocus;
                                return InkWell(
                                  onTap: () => setState(() => _selectedColorId = gradientOpt.id),
                                  customBorder: const CircleBorder(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: gradientOpt.gradient,
                                          border: Border.all(
                                            color: isColorFocused
                                                ? PlixTheme.plexGold
                                                : isSelected
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(0.2),
                                            width: isColorFocused ? 3.0 : (isSelected ? 2.5 : 1.2),
                                          ),
                                          boxShadow: isColorFocused
                                              ? [
                                                  BoxShadow(
                                                    color: PlixTheme.plexGold.withOpacity(0.6),
                                                    blurRadius: 14,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.white.withOpacity(0.35),
                                                        blurRadius: 8,
                                                      ),
                                                    ]
                                                  : null,
                                        ),
                                        child: isSelected
                                            ? const Center(
                                                child: Icon(Icons.check_rounded, color: Colors.white, size: 20),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 4. PIN Lock Toggle (Centered)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Focus(
                            focusNode: _pinToggleFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space ||
                                    key == LogicalKeyboardKey.gameButtonA) {
                                  _togglePin();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowDown) {
                                  _saveFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.arrowUp) {
                                  final colTarget = _colorFocusNodes[_selectedColorId] ?? _colorFocusNodes.values.first;
                                  colTarget.requestFocus();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isToggleFocused = Focus.of(context).hasFocus;
                                return InkWell(
                                  onTap: _togglePin,
                                  borderRadius: BorderRadius.circular(16),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isToggleFocused
                                          ? PlixTheme.plexGold.withOpacity(0.15)
                                          : PlixTheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isToggleFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                                        width: isToggleFocused ? 2.5 : 1.0,
                                      ),
                                      boxShadow: isToggleFocused
                                          ? [
                                              BoxShadow(
                                                color: PlixTheme.plexGold.withOpacity(0.35),
                                                blurRadius: 12,
                                                spreadRadius: 1.5,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.lock_rounded,
                                          size: 18,
                                          color: _enablePin ? PlixTheme.plexGold : PlixTheme.textMuted,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Require 4-Digit PIN Lock',
                                                style: TextStyle(
                                                  color: PlixTheme.textPrimary,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                _enablePin
                                                    ? 'PIN is active (toggle off to remove or change)'
                                                    : 'Prompt for PIN when switching to this profile',
                                                style: TextStyle(
                                                  color: _enablePin ? PlixTheme.plexGold : PlixTheme.textSecondary.withOpacity(0.8),
                                                  fontSize: 11,
                                                  fontWeight: _enablePin ? FontWeight.w600 : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch(
                                          value: _enablePin,
                                          activeColor: PlixTheme.plexGold,
                                          onChanged: (val) => _togglePin(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 5. Action Buttons: Save Changes FIRST, Delete Profile BELOW
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Focus(
                            focusNode: _saveFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                final key = event.logicalKey;
                                if (key == LogicalKeyboardKey.arrowDown) {
                                  if (isEditing && ProfileService.instance.profiles.length > 1) {
                                    _deleteFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                }
                                if (key == LogicalKeyboardKey.arrowUp) {
                                  _pinToggleFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (key == LogicalKeyboardKey.select ||
                                    key == LogicalKeyboardKey.enter ||
                                    key == LogicalKeyboardKey.space ||
                                    key == LogicalKeyboardKey.gameButtonA) {
                                  _handleSave();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final isSaveFocused = Focus.of(context).hasFocus;
                                return ElevatedButton.icon(
                                  onPressed: _isSaving ? null : _handleSave,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        )
                                      : Icon(
                                          isEditing ? Icons.check_rounded : Icons.arrow_forward_rounded,
                                          size: 16,
                                          color: Colors.black,
                                        ),
                                  label: Text(
                                    isEditing
                                        ? 'Save Changes'
                                        : (widget.isInitialSetup ? 'Next: Connect Server' : 'Create & Connect Server'),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: PlixTheme.plexGold,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isSaveFocused ? Colors.white : Colors.transparent,
                                        width: isSaveFocused ? 2.5 : 0,
                                      ),
                                    ),
                                    elevation: isSaveFocused ? 8 : 2,
                                    shadowColor: isSaveFocused ? PlixTheme.plexGold : Colors.transparent,
                                  ),
                                );
                              },
                            ),
                          ),

                          if (isEditing && ProfileService.instance.profiles.length > 1) ...[
                            const SizedBox(height: 10),
                            Focus(
                              focusNode: _deleteFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  final key = event.logicalKey;
                                  if (key == LogicalKeyboardKey.arrowUp) {
                                    _saveFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.select ||
                                      key == LogicalKeyboardKey.enter ||
                                      key == LogicalKeyboardKey.space ||
                                      key == LogicalKeyboardKey.gameButtonA) {
                                    _handleDelete();
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final isDeleteFocused = Focus.of(context).hasFocus;
                                  return OutlinedButton.icon(
                                    onPressed: _isSaving ? null : _handleDelete,
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 15),
                                    label: const Text('Delete Profile', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: isDeleteFocused ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
                                      side: BorderSide(
                                        color: isDeleteFocused ? Colors.redAccent : Colors.redAccent.withOpacity(0.5),
                                        width: isDeleteFocused ? 2.5 : 1.0,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
