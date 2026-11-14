import '../services/guest_mode_service.dart';
import 'incognito_icon.dart';
import 'plix_button.dart';
import '../services/profile_service.dart';
import '../models/plix_profile.dart';
import 'profile_avatar_widget.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_server.dart';
import '../services/plix_device_helper.dart';

enum NavDestination {
  home,
  watchlist,
  search,
  library,
  settings,
  switchServer,
  signOut,
}

class SidebarNav extends StatefulWidget {
  final PlexServer? currentServer;
  final List<PlexLibrary> libraries;
  final PlexLibrary? selectedLibrary;
  final NavDestination activeDestination;
  final ValueChanged<NavDestination> onDestinationSelected;
  final ValueChanged<PlexLibrary> onLibrarySelected;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchServer;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onNavigateRight;
  final FocusNode? homeFocusNode;
  final FocusNode? settingsFocusNode;
  final FocusNode? switchServerFocusNode;
  final FocusNode? signOutFocusNode;
  final ValueChanged<bool>? onFocusChange;

  final ValueChanged<List<PlexLibrary>>? onLibrariesReordered;
  final VoidCallback? onOpenProfiles;
  final VoidCallback? onEditProfile;

  const SidebarNav({
    super.key,
    required this.currentServer,
    required this.libraries,
    this.selectedLibrary,
    required this.activeDestination,
    required this.onDestinationSelected,
    required this.onLibrarySelected,
    required this.onSignOut,
    required this.onSwitchServer,
    this.onOpenSettings,
    this.onNavigateRight,
    this.homeFocusNode,
    this.settingsFocusNode,
    this.switchServerFocusNode,
    this.signOutFocusNode,
    this.onFocusChange,
    this.onLibrariesReordered,
    this.onOpenProfiles,
    this.onEditProfile,
  });

  @override
  State<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<SidebarNav> {
  final GlobalKey _profileAvatarKey = GlobalKey();
  bool _isExpanded = false;
  bool _isProfileMenuOpen = false;
  bool _mobileLandscapeExpanded = false;
  Orientation? _lastOrientation;
  late List<PlexLibrary> _orderedLibraries;
  String? _activeReorderKey;
  bool _isReorderMode = false;
  final Map<String, FocusNode> _itemFocusNodes = {};

  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _watchlistFocusNode = FocusNode();
  final FocusNode _settingsFocusNode = FocusNode();
  FocusNode get _effectiveSettingsFocusNode => widget.settingsFocusNode ?? _settingsFocusNode;
  final FocusNode _switchServerFocusNode = FocusNode();
  FocusNode get _effectiveSwitchServerFocusNode => widget.switchServerFocusNode ?? _switchServerFocusNode;
  final FocusNode _signOutFocusNode = FocusNode();
  FocusNode get _effectiveSignOutFocusNode => widget.signOutFocusNode ?? _signOutFocusNode;
  final FocusNode _reorderToggleFocusNode = FocusNode();
  final FocusNode _profileFocusNode = FocusNode();
  final GlobalKey _listViewKey = GlobalKey();

  void _scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0.0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToKeepItemVisible(FocusNode? node) {
    if (!mounted || node == null) return;
    final nodeCtx = node.context;
    if (nodeCtx == null || !nodeCtx.mounted) return;
    final renderObject = nodeCtx.findRenderObject() as RenderBox?;
    final listViewBox = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject != null && listViewBox != null && _scrollController.hasClients) {
      final itemOffset = renderObject.localToGlobal(Offset.zero, ancestor: listViewBox);
      final itemTop = itemOffset.dy;
      final itemBottom = itemTop + renderObject.size.height;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentOffset = _scrollController.position.pixels;

      // Scroll down if item is approaching or exceeds bottom of viewport
      if (itemBottom > viewportHeight * 0.75) {
        final target = (currentOffset + (itemBottom - viewportHeight * 0.75)).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else if (_orderedLibraries.isNotEmpty && _orderedLibraries.first.compositeId == _activeReorderKey) {
        // Scrolled all the way to top item in reorder
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else if (itemTop < 60) {
        // Scroll up if item is approaching the top of viewport
        final target = (currentOffset + itemTop - 60).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _ensureItemVisible(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToKeepItemVisible(node);
    });
  }

  void _handleProfileFocusChange() {
    if (mounted) setState(() {});
  }
  void _handleReorderFocusChange() {
    if (_reorderToggleFocusNode.hasFocus) {
      _ensureItemVisible(_reorderToggleFocusNode);
    }
  }

  void _ensureActiveItemVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusNode? focusedNode;
      if (_effectiveSwitchServerFocusNode.hasFocus) {
        focusedNode = _effectiveSwitchServerFocusNode;
      } else if (_effectiveSettingsFocusNode.hasFocus) {
        focusedNode = _effectiveSettingsFocusNode;
      } else if (_effectiveSignOutFocusNode.hasFocus) {
        focusedNode = _effectiveSignOutFocusNode;
      } else if (_reorderToggleFocusNode.hasFocus) {
        focusedNode = _reorderToggleFocusNode;
      } else {
        for (final node in _itemFocusNodes.values) {
          if (node.hasFocus) {
            focusedNode = node;
            break;
          }
        }
      }
      if (focusedNode != null) {
        _ensureItemVisible(focusedNode);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _profileFocusNode.addListener(_handleProfileFocusChange);
    _reorderToggleFocusNode.addListener(_handleReorderFocusChange);
    _syncLibraries(widget.libraries);
  }

  @override
  void didUpdateWidget(covariant SidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.libraries != oldWidget.libraries) {
      _syncLibraries(widget.libraries);
    }
  }

  void _syncLibraries(List<PlexLibrary> libs) {
    _orderedLibraries = List.from(libs);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _watchlistFocusNode.dispose();
    _settingsFocusNode.dispose();
    _switchServerFocusNode.dispose();
    _signOutFocusNode.dispose();
    _reorderToggleFocusNode.removeListener(_handleReorderFocusChange);
    _reorderToggleFocusNode.dispose();
    _profileFocusNode.removeListener(_handleProfileFocusChange);
    _profileFocusNode.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _moveLibrary(PlexLibrary lib, int delta) {
    final idx = _orderedLibraries.indexWhere((l) => l.compositeId == lib.compositeId);
    if (idx == -1) return;
    final target = idx + delta;
    if (target >= 0 && target < _orderedLibraries.length) {
      setState(() {
        final item = _orderedLibraries.removeAt(idx);
        _orderedLibraries.insert(target, item);
        _activeReorderKey = lib.compositeId;
      });
      widget.onLibrariesReordered?.call(List.from(_orderedLibraries));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final node = _itemFocusNodes[lib.compositeId];
          node?.requestFocus();
          _scrollToKeepItemVisible(node);
        }
      });
    }
  }

  void _showEnterGuestModeDialog() {
    final cancelFocus = FocusNode(debugLabel: 'guestCancel');
    final enableFocus = FocusNode(debugLabel: 'guestEnable');

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: PlixTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.8),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: PlixTheme.plexGold.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: IncognitoIcon(size: 26, color: PlixTheme.plexGold),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Enter Guest Mode',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Stream content in a temporary private session. Watch history and progress during guest mode will not be saved to your server, keeping your profile activity and Continue Watching completely untouched.\n\nYou can exit Guest Mode at any time from the sidebar.',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlixButton(
                      focusNode: cancelFocus,
                      autofocus: true,
                      label: 'Cancel',
                      backgroundColor: Colors.white.withOpacity(0.1),
                      borderColor: Colors.white.withOpacity(0.2),
                      textColor: PlixTheme.textPrimary,
                      highlightColor: Colors.white.withOpacity(0.2),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      onRight: () => enableFocus.requestFocus(),
                      blockLeft: true,
                      blockUp: true,
                      blockDown: true,
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                    const SizedBox(width: 12),
                    PlixButton(
                      focusNode: enableFocus,
                      label: 'Enable',
                      icon: const Icon(Icons.check_rounded, size: 18),
                      backgroundColor: Colors.white.withOpacity(0.1),
                      borderColor: Colors.white.withOpacity(0.2),
                      textColor: PlixTheme.textPrimary,
                      highlightColor: PlixTheme.plexGold,
                      highlightTextColor: Colors.black,
                      highlightBorderColor: PlixTheme.plexGold,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      onLeft: () => cancelFocus.requestFocus(),
                      blockRight: true,
                      blockUp: true,
                      blockDown: true,
                      onPressed: () async {
                        Navigator.of(dialogCtx).pop();
                        await GuestModeService.instance.setGuestMode(true);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openProfileMenu() {
    if (_isProfileMenuOpen) return;
    _isProfileMenuOpen = true;
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final avatarBox = _profileAvatarKey.currentContext?.findRenderObject() as RenderBox?;
      final avatarPos = avatarBox?.localToGlobal(Offset.zero) ?? const Offset(16, 56);
      final avatarSize = avatarBox?.size ?? const Size(42, 42);

      final isGuest = GuestModeService.instance.isGuestMode;
      final switchUserFocus = FocusNode(debugLabel: 'switchUser');
      final editProfileFocus = FocusNode(debugLabel: 'editProfile');
      final enterGuestFocus = FocusNode(debugLabel: 'enterGuest');
      final exitGuestFocus = FocusNode(debugLabel: 'exitGuest');

      showDialog(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        builder: (dialogCtx) {
          return FocusScope(
            autofocus: true,
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(dialogCtx).pop(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  Positioned(
                    left: avatarPos.dx.clamp(8.0, MediaQuery.of(dialogCtx).size.width - 220.0),
                    top: avatarPos.dy + avatarSize.height + 6.0,
                    child: Material(
                      color: Colors.transparent,
                      child: ValueListenableBuilder<int>(
                        valueListenable: PlixTheme.themeRevision,
                        builder: (context, _, __) {
                          final accent = PlixTheme.plexGold;
                          return Container(
                            width: isGuest ? 200 : 215,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            decoration: BoxDecoration(
                              color: PlixTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: accent.withOpacity(0.5), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.25),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.7),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isGuest) ...[
                                  _ProfilePopupMenuItem(
                                    focusNode: exitGuestFocus,
                                    autofocus: true,
                                    icon: Icons.no_accounts_rounded,
                                    label: 'Exit Guest Mode',
                                    onSelect: () {
                                      Navigator.of(dialogCtx).pop();
                                      GuestModeService.instance.exitGuestMode();
                                    },
                                    onDown: () {},
                                    onUp: () {},
                                    onOtherDirection: () => Navigator.of(dialogCtx).pop(),
                                    onBack: () => Navigator.of(dialogCtx).pop(),
                                  ),
                                ] else ...[
                                  _ProfilePopupMenuItem(
                                    focusNode: switchUserFocus,
                                    autofocus: true,
                                    icon: Icons.switch_account_rounded,
                                    label: 'Switch User',
                                    onSelect: () {
                                      Navigator.of(dialogCtx).pop();
                                      widget.onOpenProfiles?.call();
                                    },
                                    onDown: () => editProfileFocus.requestFocus(),
                                    onUp: () => enterGuestFocus.requestFocus(),
                                    onOtherDirection: () => Navigator.of(dialogCtx).pop(),
                                    onBack: () => Navigator.of(dialogCtx).pop(),
                                  ),
                                  const SizedBox(height: 4),
                                  _ProfilePopupMenuItem(
                                    focusNode: editProfileFocus,
                                    icon: Icons.edit_rounded,
                                    label: 'Edit Profile',
                                    onSelect: () {
                                      Navigator.of(dialogCtx).pop();
                                      widget.onEditProfile?.call();
                                    },
                                    onUp: () => switchUserFocus.requestFocus(),
                                    onDown: () => enterGuestFocus.requestFocus(),
                                    onOtherDirection: () => Navigator.of(dialogCtx).pop(),
                                    onBack: () => Navigator.of(dialogCtx).pop(),
                                  ),
                                  const SizedBox(height: 4),
                                  _ProfilePopupMenuItem(
                                    focusNode: enterGuestFocus,
                                    icon: Icons.visibility_off_rounded,
                                    label: 'Enter Guest Mode',
                                    onSelect: () {
                                      Navigator.of(dialogCtx).pop();
                                      _showEnterGuestModeDialog();
                                    },
                                    onUp: () => editProfileFocus.requestFocus(),
                                    onDown: () => switchUserFocus.requestFocus(),
                                    onOtherDirection: () => Navigator.of(dialogCtx).pop(),
                                    onBack: () => Navigator.of(dialogCtx).pop(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).then((_) {
        switchUserFocus.dispose();
        editProfileFocus.dispose();
        exitGuestFocus.dispose();
        if (mounted) {
          setState(() {
            _isProfileMenuOpen = false;
          });
          _profileFocusNode.requestFocus();
        }
      });
    });
  }

  void _toggleReorderMode() {
    setState(() {
      _isReorderMode = !_isReorderMode;
      if (!_isReorderMode) {
        _activeReorderKey = null;
      }
    });
  }

  void _showOfflineToast(String serverName) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$serverName is currently offline.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 280,
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.6), width: 1.5),
        ),
      ),
    );
  }

  void _handleNavigateRight() {
    if (_isReorderMode) {
      setState(() {
        _isReorderMode = false;
        _activeReorderKey = null;
      });
    }
    widget.onNavigateRight?.call();
  }

  void _handleLibraryTap(PlexLibrary lib) {
    if (_isReorderMode) {
      if (_activeReorderKey == lib.compositeId) {
        setState(() => _activeReorderKey = null);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final node = _itemFocusNodes[lib.compositeId];
            if (node != null && node.canRequestFocus) {
              node.requestFocus();
              _scrollToKeepItemVisible(node);
            }
          }
        });
      } else {
        setState(() => _activeReorderKey = lib.compositeId);
        final node = _itemFocusNodes[lib.compositeId];
        node?.requestFocus();
        _scrollToKeepItemVisible(node);
      }
      return;
    }
    if (!lib.isServerOnline) {
      _showOfflineToast(lib.serverName ?? 'Server');
      return;
    }
    widget.onLibrarySelected(lib);
  }



  @override
  Widget build(BuildContext context) {
    final currentOrientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != currentOrientation) {
      _lastOrientation = currentOrientation;
      _mobileLandscapeExpanded = false;
    }

    final isMobileLandscape = !(Platform.isWindows || Platform.isLinux) &&
        !PlixDeviceHelper.isTelevision &&
        currentOrientation == Orientation.landscape;
    final isReorderGripEnabled = !PlixDeviceHelper.isTelevision &&
        ((Platform.isWindows || Platform.isLinux) || currentOrientation == Orientation.landscape);
    final effectiveExpanded = _isProfileMenuOpen || (isMobileLandscape ? _mobileLandscapeExpanded : _isExpanded);
    final width = effectiveExpanded ? 245.0 : 72.0;

    return MouseRegion(
      onEnter: (_) {
        if (Platform.isWindows || Platform.isLinux) {
          setState(() {
            _isExpanded = true;
          });
          _scrollToTop();
          widget.onFocusChange?.call(true);
        }
      },
      onExit: (_) {
        if (Platform.isWindows || Platform.isLinux) {
          setState(() {
            _isExpanded = false;
          });
          widget.onFocusChange?.call(false);
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasNavFocus) {
          if (!hasNavFocus && _isReorderMode) {
            setState(() {
              _isReorderMode = false;
              _activeReorderKey = null;
            });
          }
          if (!(Platform.isWindows || Platform.isLinux)) {
            setState(() {
              _isExpanded = hasNavFocus;
            });
            widget.onFocusChange?.call(hasNavFocus);
            if (hasNavFocus) {
              _ensureActiveItemVisible();
            }
          }
        },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.hardEdge,
        width: width,
        decoration: BoxDecoration(
          color: PlixTheme.isOLED
              ? const Color(0xFF000000)
              : (PlixTheme.isGlass
                  ? null
                  : PlixTheme.surface),
          gradient: PlixTheme.isGlass
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x4D1A2942),
                    Color(0x2E101B2E),
                    Color(0x1F0A121F),
                  ],
                )
              : null,
          border: PlixTheme.isGlass
              ? const Border(right: BorderSide(color: Color(0x66FFFFFF), width: 1.5))
              : (PlixTheme.isOLED
                  ? Border(right: BorderSide(color: PlixTheme.cardBorder, width: 1.0))
                  : (PlixTheme.isCyberpunk
                      ? const Border(right: BorderSide(color: Color(0x66FF007F), width: 1.2))
                      : null)),
          boxShadow: PlixTheme.isGlass
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header / Logo with Server Name beside it when expanded
            if (PlixDeviceHelper.isTelevision && !effectiveExpanded)
              Container(
                height: 60,
                width: 72.0,
                alignment: Alignment.center,
                child: ValueListenableBuilder<PlixProfile?>(
                  valueListenable: ProfileService.instance.activeProfileNotifier,
                  builder: (context, activeProf, _) {
                    return ProfileAvatarWidget(
                      avatarId: activeProf?.avatarId ?? 'avatar_default',
                      avatarColorId: activeProf?.avatarColorId,
                      size: 44,
                      glow: false,
                    );
                  },
                ),
              )
            else
              Container(
                height: 60,
                padding: EdgeInsets.symmetric(horizontal: effectiveExpanded ? 14 : 10),
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: effectiveExpanded ? (245.0 - 28.0) : (72.0 - 20.0),
                  child: Row(
                    children: [
                      if (!effectiveExpanded) ...[
                        ValueListenableBuilder<PlixProfile?>(
                          valueListenable: ProfileService.instance.activeProfileNotifier,
                          builder: (context, activeProf, _) {
                            final avatarId = activeProf?.avatarId ?? 'avatar_default';
                            if (isMobileLandscape) {
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      _mobileLandscapeExpanded = true;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: PlixTheme.plexGold.withOpacity(0.4),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ProfileAvatarWidget(
                                          avatarId: avatarId,
                                          avatarColorId: activeProf?.avatarColorId,
                                          size: 28,
                                          glow: false,
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 18,
                                          color: PlixTheme.plexGold,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                            return ProfileAvatarWidget(
                              avatarId: avatarId,
                              avatarColorId: activeProf?.avatarColorId,
                              size: 38,
                              borderRadius: 10,
                              glow: false,
                            );
                          },
                        ),
                      ],
                      if (effectiveExpanded) ...[
                        ValueListenableBuilder<PlixProfile?>(
                          valueListenable: ProfileService.instance.activeProfileNotifier,
                          builder: (context, activeProf, _) {
                            final avatarId = activeProf?.avatarId ?? 'avatar_default';
                            final isFocused = _profileFocusNode.hasFocus;
                            return Focus(
                              focusNode: _profileFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                  final key = event.logicalKey;
                                  if (key == LogicalKeyboardKey.arrowDown) {
                                    (widget.homeFocusNode ?? _itemFocusNodes['home'])?.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (key == LogicalKeyboardKey.arrowRight) {
                                    _handleNavigateRight();
                                    return KeyEventResult.handled;
                                  }
                                  if (event is KeyDownEvent &&
                                      (key == LogicalKeyboardKey.select ||
                                      key == LogicalKeyboardKey.enter ||
                                      key == LogicalKeyboardKey.space ||
                                      key == LogicalKeyboardKey.gameButtonA ||
                                      key == LogicalKeyboardKey.gameButtonSelect ||
                                      key == LogicalKeyboardKey.numpadEnter)) {
                                    _openProfileMenu();
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Tooltip(
                                message: 'Profiles (${activeProf?.name ?? "Switch Profile"})',
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    canRequestFocus: false,
                                    onTap: _openProfileMenu,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      key: _profileAvatarKey,
                                      child: ProfileAvatarWidget(
                                        avatarId: avatarId,
                                        avatarColorId: activeProf?.avatarColorId,
                                        size: 42,
                                        isFocused: isFocused,
                                        glow: isFocused,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                text: 'pli',
                                style: TextStyle(
                                  color: PlixTheme.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.5,
                                ),
                              ),
                              TextSpan(
                                text: 'x',
                                style: TextStyle(
                                  color: PlixTheme.plexGold,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<PlixProfile?>(
                          valueListenable: ProfileService.instance.activeProfileNotifier,
                          builder: (context, activeProf, _) {
                            final profName = activeProf?.name ?? 'Profile';
                            return Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 1.5,
                                    height: 18,
                                    color: PlixTheme.cardBorder,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      profName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PlixTheme.textPrimary,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: GuestModeService.instance.isGuestModeNotifier,
                                    builder: (context, isGuest, _) {
                                      if (!isGuest) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Tooltip(
                                          message: 'Guest Mode Active',
                                          child: IncognitoIcon(
                                            size: 22,
                                            color: PlixTheme.plexGold,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        if (isMobileLandscape) ...[
                          const SizedBox(width: 4),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _mobileLandscapeExpanded = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: PlixTheme.plexGold.withOpacity(0.4),
                                    width: 1.0,
                                  ),
                                ),
                                child: Icon(
                                  Icons.chevron_left_rounded,
                                  size: 18,
                                  color: PlixTheme.plexGold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Divider(color: PlixTheme.cardBorder, height: 1),

            // Navigation Items (Home, Search, Watchlist, Libraries, Settings, Switch Server, Sign Out)
            Expanded(
              child: ListView(
                key: _listViewKey,
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _NavItem(
                    focusNode: widget.homeFocusNode ?? _itemFocusNodes.putIfAbsent('home', () => FocusNode()),
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isSelected: widget.activeDestination == NavDestination.home,
                    isExpanded: effectiveExpanded,
                    onUp: () {
                      _profileFocusNode.requestFocus();
                    },
                    onDown: () => _searchFocusNode.requestFocus(),
                    onFocusChange: (focused) {
                      if (focused) _scrollToTop();
                    },
                    onNavigateRight: _handleNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.home),
                  ),

                  _NavItem(
                    focusNode: _searchFocusNode,
                    icon: Icons.search_rounded,
                    label: 'Search',
                    isSelected: widget.activeDestination == NavDestination.search,
                    isExpanded: effectiveExpanded,
                    onUp: () {
                      (widget.homeFocusNode ?? _itemFocusNodes['home'])?.requestFocus();
                      _scrollToTop();
                    },
                    onDown: () => _watchlistFocusNode.requestFocus(),
                    onNavigateRight: _handleNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.search),
                  ),

                  _NavItem(
                    focusNode: _watchlistFocusNode,
                    icon: Icons.bookmark_rounded,
                    label: 'Watchlist',
                    isSelected: widget.activeDestination == NavDestination.watchlist,
                    isExpanded: effectiveExpanded,
                    onUp: () => _searchFocusNode.requestFocus(),
                    onDown: () {
                      if (_orderedLibraries.isNotEmpty) {
                        if (effectiveExpanded) {
                          _reorderToggleFocusNode.requestFocus();
                        } else {
                          _itemFocusNodes[_orderedLibraries.first.compositeId]?.requestFocus();
                        }
                      } else {
                        _effectiveSettingsFocusNode.requestFocus();
                      }
                    },
                    onNavigateRight: _handleNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.watchlist),
                  ),

                  // Libraries section header
                  if (_orderedLibraries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
                      child: effectiveExpanded
                          ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: SizedBox(
                                width: 245.0 - 20.0,
                                child: Row(
                              children: [
                                const Text(
                                  'LIBRARIES',
                                  style: TextStyle(
                                    color: PlixTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Divider(
                                    color: PlixTheme.cardBorder,
                                    height: 1,
                                    thickness: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _ReorderToggleButton(
                                  focusNode: _reorderToggleFocusNode,
                                  isActive: _isReorderMode,
                                  onToggle: _toggleReorderMode,
                                  onUp: () => _watchlistFocusNode.requestFocus(),
                                  onDown: () {
                                    if (_orderedLibraries.isNotEmpty) {
                                      _itemFocusNodes[_orderedLibraries.first.compositeId]
                                          ?.requestFocus();
                                    } else {
                                      _effectiveSettingsFocusNode.requestFocus();
                                    }
                                  },
                                  onNavigateRight: _handleNavigateRight,
                                ),
                              ],
                            ),
                          ),
                        )
                          : Divider(
                              color: PlixTheme.cardBorder,
                              height: 1,
                              thickness: 1,
                            ),
                    ),

                  // Dynamic library entries grouped by server
                  if (_orderedLibraries.isNotEmpty)
                    _isReorderMode && isReorderGripEnabled
                        ? ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _orderedLibraries.length,
                            onReorder: (oldIndex, newIndex) {
                              if (oldIndex < newIndex) {
                                newIndex -= 1;
                              }
                              setState(() {
                                final item = _orderedLibraries.removeAt(oldIndex);
                                _orderedLibraries.insert(newIndex, item);
                                _activeReorderKey = item.compositeId;
                              });
                              widget.onLibrariesReordered?.call(List.from(_orderedLibraries));
                            },
                            itemBuilder: (context, i) {
                              final lib = _orderedLibraries[i];
                              final hasMultiServers = _orderedLibraries.map((l) => l.serverName).where((n) => n != null && n.isNotEmpty).toSet().length > 1;
                              final serverLabel = hasMultiServers ? (lib.serverName ?? (lib.isJellyfin ? 'Jellyfin' : 'Plex')) : null;
                              return _NavItem(
                                key: ValueKey('nav_${lib.compositeId}'),
                                focusNode: _itemFocusNodes.putIfAbsent(lib.compositeId, () => FocusNode()),
                                icon: lib.isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                label: lib.title,
                                subtitle: serverLabel,
                                isOffline: !lib.isServerOnline,
                                isSelected: widget.activeDestination == NavDestination.library &&
                                    widget.selectedLibrary?.compositeId == lib.compositeId,
                                isExpanded: effectiveExpanded,
                                isReorderMode: _isReorderMode,
                                isReorderPicked: _activeReorderKey == lib.compositeId,
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: const Icon(
                                      Icons.drag_handle_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                onUp: () {
                                  if (_isReorderMode && _activeReorderKey == lib.compositeId) {
                                    _moveLibrary(lib, -1);
                                    return;
                                  }
                                  if (i == 0) {
                                    if (effectiveExpanded) {
                                      _reorderToggleFocusNode.requestFocus();
                                    } else {
                                      _watchlistFocusNode.requestFocus();
                                    }
                                  } else {
                                    _itemFocusNodes[_orderedLibraries[i - 1].compositeId]?.requestFocus();
                                  }
                                },
                                onDown: () {
                                  if (_isReorderMode && _activeReorderKey == lib.compositeId) {
                                    _moveLibrary(lib, 1);
                                    return;
                                  }
                                  if (i == _orderedLibraries.length - 1) {
                                    _effectiveSettingsFocusNode.requestFocus();
                                  } else {
                                    _itemFocusNodes[_orderedLibraries[i + 1].compositeId]?.requestFocus();
                                  }
                                },
                                onNavigateRight: _handleNavigateRight,
                                onTap: () => _handleLibraryTap(lib),
                              );
                            },
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < _orderedLibraries.length; i++)
                                Builder(
                                  builder: (context) {
                                    final lib = _orderedLibraries[i];
                                    final hasMultiServers = _orderedLibraries.map((l) => l.serverName).where((n) => n != null && n.isNotEmpty).toSet().length > 1;
                                    final serverLabel = hasMultiServers ? (lib.serverName ?? (lib.isJellyfin ? 'Jellyfin' : 'Plex')) : null;
                                    return _NavItem(
                                      key: ValueKey('nav_${lib.compositeId}'),
                                      focusNode: _itemFocusNodes.putIfAbsent(lib.compositeId, () => FocusNode()),
                                      icon: lib.isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                      label: lib.title,
                                      subtitle: serverLabel,
                                      isOffline: !lib.isServerOnline,
                                      isSelected: widget.activeDestination == NavDestination.library &&
                                          widget.selectedLibrary?.compositeId == lib.compositeId,
                                      isExpanded: effectiveExpanded,
                                      isReorderMode: _isReorderMode,
                                      isReorderPicked: _activeReorderKey == lib.compositeId,
                                      trailing: null,
                                      onUp: () {
                                        if (_isReorderMode && _activeReorderKey == lib.compositeId) {
                                          _moveLibrary(lib, -1);
                                          return;
                                        }
                                        if (i == 0) {
                                          if (effectiveExpanded) {
                                            _reorderToggleFocusNode.requestFocus();
                                          } else {
                                            _watchlistFocusNode.requestFocus();
                                          }
                                        } else {
                                          _itemFocusNodes[_orderedLibraries[i - 1].compositeId]?.requestFocus();
                                        }
                                      },
                                      onDown: () {
                                        if (_isReorderMode && _activeReorderKey == lib.compositeId) {
                                          _moveLibrary(lib, 1);
                                          return;
                                        }
                                        if (i == _orderedLibraries.length - 1) {
                                          _effectiveSettingsFocusNode.requestFocus();
                                        } else {
                                          _itemFocusNodes[_orderedLibraries[i + 1].compositeId]?.requestFocus();
                                        }
                                      },
                                      onNavigateRight: _handleNavigateRight,
                                      onTap: () => _handleLibraryTap(lib),
                                    );
                                  },
                                ),
                            ],
                          ),

                  Divider(color: PlixTheme.cardBorder, height: 20),

                  _NavItem(
                    focusNode: _effectiveSettingsFocusNode,
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    isSelected: widget.activeDestination == NavDestination.settings,
                    isExpanded: effectiveExpanded,
                    onUp: () {
                      if (_orderedLibraries.isNotEmpty) {
                        _itemFocusNodes[_orderedLibraries.last.compositeId]?.requestFocus();
                      } else {
                        _watchlistFocusNode.requestFocus();
                      }
                    },
                    onDown: () => _effectiveSwitchServerFocusNode.requestFocus(),
                    onNavigateRight: _handleNavigateRight,
                    onTap: () {
                      if (_isReorderMode) {
                        setState(() {
                          _isReorderMode = false;
                          _activeReorderKey = null;
                        });
                      }
                      if (widget.onOpenSettings != null) {
                        widget.onOpenSettings!();
                      } else {
                        widget.onDestinationSelected(NavDestination.settings);
                      }
                    },
                  ),

                  _NavItem(
                    focusNode: _effectiveSwitchServerFocusNode,
                    icon: Icons.tune_rounded,
                    label: 'Customize Servers',
                    isSelected: widget.activeDestination == NavDestination.switchServer,
                    isExpanded: effectiveExpanded,
                    onUp: () => _effectiveSettingsFocusNode.requestFocus(),
                    onDown: () => _effectiveSignOutFocusNode.requestFocus(),
                    onNavigateRight: _handleNavigateRight,
                    onTap: widget.onSwitchServer,
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: GuestModeService.instance.isGuestModeNotifier,
                    builder: (context, isGuest, _) {
                      return _NavItem(
                        focusNode: _effectiveSignOutFocusNode,
                        icon: isGuest ? Icons.no_accounts_rounded : Icons.logout_rounded,
                        label: isGuest ? 'Exit Guest Mode' : 'Log Out',
                        isSelected: !isGuest && widget.activeDestination == NavDestination.signOut,
                        isExpanded: effectiveExpanded,
                        onUp: () => _effectiveSwitchServerFocusNode.requestFocus(),
                        blockDown: true,
                        onNavigateRight: _handleNavigateRight,
                        onTap: () {
                          if (isGuest) {
                            GuestModeService.instance.exitGuestMode();
                          } else {
                            widget.onSignOut();
                          }
                        },
                      );
                    },
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

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isSelected;
  final bool isExpanded;
  final bool isReorderMode;
  final bool isReorderPicked;
  final bool isOffline;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onNavigateRight;
  final FocusNode? focusNode;
  final bool blockDown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final ValueChanged<bool>? onFocusChange;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.isSelected,
    required this.isExpanded,
    this.isReorderMode = false,
    this.isReorderPicked = false,
    this.isOffline = false,
    this.trailing,
    required this.onTap,
    this.onNavigateRight,
    this.focusNode,
    this.blockDown = false,
    this.onUp,
    this.onDown,
    this.onFocusChange,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        final renderObject = context.findRenderObject() as RenderBox?;
        final scrollable = Scrollable.maybeOf(context);
        if (renderObject != null && scrollable != null) {
          final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
          if (scrollableBox != null) {
            final itemOffset = renderObject.localToGlobal(Offset.zero, ancestor: scrollableBox);
            final itemTop = itemOffset.dy;
            final itemBottom = itemTop + renderObject.size.height;
            final viewportHeight = scrollable.position.viewportDimension;
            final currentOffset = scrollable.position.pixels;

            // Only scroll down once the cursor is towards the bottom of the screen (> 80% of viewport)
            if (itemBottom > viewportHeight * 0.80) {
              final target = (currentOffset + (itemBottom - viewportHeight * 0.80)).clamp(0.0, scrollable.position.maxScrollExtent);
              scrollable.position.animateTo(
                target,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              );
            } else if (itemTop < 12) {
              // When moving back up, scroll up just enough to keep item visible
              final target = (currentOffset + itemTop - 12).clamp(0.0, scrollable.position.maxScrollExtent);
              scrollable.position.animateTo(
                target,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              );
            }
          }
        }
      }
      widget.onFocusChange?.call(_focusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
    _isFocused = _focusNode.hasFocus;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picked = widget.isReorderPicked;
    final isFocused = _focusNode.hasFocus || _isFocused;
    final reorderFocused = widget.isReorderMode && (isFocused || _isHovered);
    final isHighlighted = isFocused || _isHovered || picked;
    final activeColor = widget.isOffline
        ? PlixTheme.textMuted.withOpacity(0.4)
        : (widget.isSelected ? PlixTheme.plexGold : PlixTheme.textSecondary);
    final fgColor = picked
        ? PlixTheme.plexGold
        : isHighlighted
            ? Colors.black
            : activeColor;
    final bgColor = picked
        ? PlixTheme.plexGold.withOpacity(0.16)
        : isHighlighted
            ? PlixTheme.plexGold
            : Colors.transparent;
    final shadows = picked
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.65),
              blurRadius: 22,
              offset: const Offset(0, 10),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: PlixTheme.plexGold.withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ]
        : reorderFocused
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: PlixTheme.plexGold.withOpacity(0.25),
                  blurRadius: 9,
                  spreadRadius: 1,
                ),
              ]
            : null;

    return AnimatedSlide(
      offset: Offset(0, picked ? -0.05 : reorderFocused ? -0.02 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: picked ? 1.09 : reorderFocused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.arrowUp) {
                if (widget.onUp != null) {
                  widget.onUp!();
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
              if (key == LogicalKeyboardKey.arrowRight) {
                if (widget.onNavigateRight != null) {
                  widget.onNavigateRight!();
                  return KeyEventResult.handled;
                }
              }
              if (event is KeyDownEvent && (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
                widget.onTap();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onTap: widget.onTap,
            onHover: (hovered) {
              if ((Platform.isWindows || Platform.isLinux) && mounted) {
                setState(() => _isHovered = hovered);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: shadows,
                ),
                child: CustomPaint(
                  foregroundPainter: picked
                      ? _DottedBorderPainter(color: PlixTheme.plexGold)
                      : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: widget.subtitle != null ? 8 : 12,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: 245.0 - 48.0,
                        child: Row(
                          children: [
                            Opacity(
                              opacity: widget.isOffline && !isHighlighted ? 0.4 : 1.0,
                              child: Icon(
                                widget.icon,
                                size: 22,
                                color: fgColor,
                              ),
                            ),
                        if (widget.isExpanded) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Opacity(
                              opacity: widget.isOffline && !isHighlighted ? 0.4 : 1.0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isOffline ? '${widget.label} (Offline)' : widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: fgColor,
                                      fontSize: 13.5,
                                      fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      widget.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isHighlighted
                                            ? Colors.black.withOpacity(0.7)
                                            : PlixTheme.textMuted,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (widget.trailing != null) ...[
                            const SizedBox(width: 8),
                            widget.trailing!,
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  final Color color;

  const _DottedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const strokeWidth = 2.0;
    const radius = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      math.max(0, size.width - strokeWidth),
      math.max(0, size.height - strokeWidth),
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 2.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 6.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ReorderToggleButton extends StatefulWidget {
  final FocusNode focusNode;
  final bool isActive;
  final VoidCallback onToggle;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback? onNavigateRight;

  const _ReorderToggleButton({
    required this.focusNode,
    required this.isActive,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    this.onNavigateRight,
  });

  @override
  State<_ReorderToggleButton> createState() => _ReorderToggleButtonState();
}

class _ReorderToggleButtonState extends State<_ReorderToggleButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ReorderToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      _isFocused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlixDeviceHelper.isTelevision;
    final isHighlighted = _isFocused || _isHovered;

    Color backgroundColor;
    Color iconColor;
    Border border;
    List<BoxShadow>? boxShadow;

    if (isTv) {
      if (isHighlighted) {
        if (widget.isActive) {
          backgroundColor = PlixTheme.plexGold;
          iconColor = Colors.black;
          border = Border.all(color: Colors.white, width: 2.0);
          boxShadow = [
            BoxShadow(
              color: PlixTheme.plexGold.withOpacity(0.55),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ];
        } else {
          backgroundColor = Colors.transparent;
          iconColor = PlixTheme.plexGold;
          border = Border.all(color: PlixTheme.plexGold, width: 2.0);
          boxShadow = [
            BoxShadow(
              color: PlixTheme.plexGold.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ];
        }
      } else {
        if (widget.isActive) {
          backgroundColor = PlixTheme.plexGold;
          iconColor = Colors.black;
          border = Border.all(color: Colors.transparent, width: 2.0);
          boxShadow = null;
        } else {
          backgroundColor = Colors.transparent;
          iconColor = PlixTheme.textMuted;
          border = Border.all(color: Colors.transparent, width: 2.0);
          boxShadow = null;
        }
      }
    } else {
      backgroundColor = isHighlighted
          ? PlixTheme.plexGold
          : (widget.isActive ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent);
      iconColor = isHighlighted
          ? Colors.black
          : (widget.isActive ? PlixTheme.plexGold : PlixTheme.textMuted);
      border = Border.all(color: Colors.transparent, width: 2.0);
      boxShadow = null;
    }

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            widget.onUp();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onNavigateRight?.call();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if ((Platform.isWindows || Platform.isLinux) && mounted) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if ((Platform.isWindows || Platform.isLinux) && mounted) {
            setState(() => _isHovered = false);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
              border: border,
              boxShadow: boxShadow,
            ),
            child: Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}



class _ProfilePopupMenuItem extends StatefulWidget {
  final FocusNode focusNode;
  final bool autofocus;
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onOtherDirection;
  final VoidCallback onBack;

  const _ProfilePopupMenuItem({
    required this.focusNode,
    this.autofocus = false,
    required this.icon,
    required this.label,
    required this.onSelect,
    required this.onDown,
    required this.onUp,
    required this.onOtherDirection,
    required this.onBack,
  });

  @override
  State<_ProfilePopupMenuItem> createState() => _ProfilePopupMenuItemState();
}

class _ProfilePopupMenuItemState extends State<_ProfilePopupMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            widget.onUp();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
            widget.onOtherDirection();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
            widget.onBack();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.gameButtonSelect ||
              key == LogicalKeyboardKey.numpadEnter)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: widget.focusNode,
        builder: (context, _) {
          final isFocused = widget.focusNode.hasFocus || _isHovered;
          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onSelect,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isFocused ? PlixTheme.plexGold : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 20,
                        color: isFocused
                            ? (PlixTheme.plexGold.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                            : PlixTheme.plexGold.withOpacity(0.85),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isFocused
                                ? (PlixTheme.plexGold.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                : PlixTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
