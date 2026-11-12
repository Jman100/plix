import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../models/plix_profile.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/profile_service.dart';
import '../widgets/brand_logo.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/profile_avatar_widget.dart';
import 'auth_chooser_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';

class ProfilesScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const ProfilesScreen({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final Map<String, FocusNode> _cardFocusNodes = {};
  final Map<String, FocusNode> _editFocusNodes = {};
  final FocusNode _addFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    PlixTheme.resetToDefaultModern();
    _initFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = ProfileService.instance.activeProfile;
      final targetNode = (active != null ? _cardFocusNodes[active.id] : null) ??
          _cardFocusNodes.values.firstOrNull ??
          _addFocusNode;
      targetNode.requestFocus();
    });
  }

  void _initFocusNodes() {
    for (final profile in ProfileService.instance.profiles) {
      _cardFocusNodes.putIfAbsent(profile.id, () => FocusNode());
      _editFocusNodes.putIfAbsent(profile.id, () => FocusNode());
    }
  }

  @override
  void dispose() {
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    for (final node in _editFocusNodes.values) {
      node.dispose();
    }
    _addFocusNode.dispose();
    super.dispose();
  }

  Future<void> _selectProfile(PlixProfile profile) async {
    final currentActive = ProfileService.instance.activeProfile;

    // If profile has a PIN lock, verify PIN first
    if (profile.hasPin) {
      final unlocked = await PinDialog.show(context, profile);
      if (!unlocked) return;
    }

    // If it's already the active profile, restore theme and pop back
    if (currentActive?.id == profile.id) {
      await PlixTheme.loadSavedTheme();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Clear home screen caches so previous profile data is never briefly shown
    HomeScreen.clearMemoryCaches();

    // Switch active profile
    await ProfileService.instance.setActiveProfile(profile.id);
    widget.authService.clearCache();
    await PlixTheme.loadSavedTheme();

    if (!mounted) return;

    // Check if switched profile has connected servers
    final token = await widget.authService.getSavedToken();
    final jfServers = await widget.serverService.getSavedJellyfinServers();
    final hasPlex = token != null && token.isNotEmpty;
    final hasJf = jfServers.isNotEmpty;

    if (!hasPlex && !hasJf) {
      // Profile has no servers yet: lead to connect to a server page
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AuthChooserScreen(
            authService: widget.authService,
            serverService: widget.serverService,
          ),
        ),
        (route) => false,
      );
      return;
    }

    // Resolve active server for this profile
    try {
      final servers = <PlexServer>[];
      if (hasPlex) {
        final fetched = await widget.serverService.fetchServers(token);
        servers.addAll(fetched);
      } else {
        servers.addAll(jfServers);
      }

      if (servers.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AuthChooserScreen(
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
          (route) => false,
        );
        return;
      }

      final savedActiveId = await widget.serverService.getActiveServerId();
      final selectedServer = servers.firstWhere(
        (s) => s.clientIdentifier == savedActiveId,
        orElse: () => servers.first,
      );

      await widget.serverService.setActiveServerId(selectedServer.clientIdentifier);
      await widget.serverService.testAndResolveBestConnection(selectedServer);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            server: selectedServer,
            authService: widget.authService,
            serverService: widget.serverService,
          ),
        ),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AuthChooserScreen(
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  void _openEditProfile(PlixProfile profile) async {
    if (profile.hasPin) {
      final unlocked = await PinDialog.show(context, profile);
      if (!unlocked) return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          profileToEdit: profile,
        ),
      ),
    );

    if (result == true && mounted) {
      _initFocusNodes();
      setState(() {});
    }
  }

  void _openAddProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          isInitialSetup: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ProfileService.instance.profiles;
    final activeProfile = ProfileService.instance.activeProfile;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          await PlixTheme.loadSavedTheme();
        }
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        body: SafeArea(
          child: Stack(
            children: [
              // Top Back Button
              Positioned(
                top: 16,
                left: 20,
                child: PlixBackButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await PlixTheme.loadSavedTheme();
                    if (mounted) nav.pop();
                  },
                ),
              ),

            // Center Content
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Logo
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PlixAppLogo(size: 38, glow: true, borderRadius: 10),
                        SizedBox(width: 10),
                        PlixWordmark(fontSize: 26),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Title
                    const Text(
                      "Who's Watching?",
                      style: TextStyle(
                        color: PlixTheme.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a profile to switch, or add a new one.',
                      style: TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Horizontal Profiles Row + Add Button
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Cards
                          for (final profile in profiles) ...[
                            _buildProfileCard(profile, isActive: profile.id == activeProfile?.id),
                            const SizedBox(width: 32),
                          ],

                          // Add Profile Card (+)
                          _buildAddProfileCard(),
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
    ),
    );
  }

  Widget _buildProfileCard(PlixProfile profile, {required bool isActive}) {
    final cardNode = _cardFocusNodes.putIfAbsent(profile.id, () => FocusNode());
    final editNode = _editFocusNodes.putIfAbsent(profile.id, () => FocusNode());
    final isCardFocused = cardNode.hasFocus;
    final isEditFocused = editNode.hasFocus;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar Button / Card
        InkWell(
          focusNode: cardNode,
          onFocusChange: (_) => setState(() {}),
          onTap: () => _selectProfile(profile),
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isCardFocused
                    ? PlixTheme.plexGold
                    : isActive
                        ? PlixTheme.plexGold.withOpacity(0.5)
                        : Colors.transparent,
                width: 3.0,
              ),
              boxShadow: isCardFocused
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ProfileAvatarWidget(
                  avatarId: profile.avatarId,
                  avatarColorId: profile.avatarColorId,
                  size: 110,
                  borderRadius: 24,
                  glow: isCardFocused || isActive,
                ),
                if (isActive)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: PlixTheme.plexGold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Profile Name (Max 12 Chars) with PIN lock icon if locked
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? PlixTheme.plexGold : PlixTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (profile.hasPin) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_rounded,
                size: 13,
                color: PlixTheme.textMuted.withOpacity(0.8),
              ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        // Selectable Edit / Pencil Icon Button
        Tooltip(
          message: 'Edit ${profile.name}',
          child: InkWell(
            focusNode: editNode,
            onFocusChange: (_) => setState(() {}),
            onTap: () => _openEditProfile(profile),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isEditFocused
                    ? PlixTheme.plexGold.withOpacity(0.25)
                    : PlixTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isEditFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: isEditFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Edit',
                    style: TextStyle(
                      color: isEditFocused ? PlixTheme.plexGold : PlixTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddProfileCard() {
    final isAddFocused = _addFocusNode.hasFocus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          focusNode: _addFocusNode,
          onFocusChange: (_) => setState(() {}),
          onTap: _openAddProfile,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              color: isAddFocused
                  ? PlixTheme.plexGold.withOpacity(0.15)
                  : PlixTheme.surface.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(
                color: isAddFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                width: 2.5,
              ),
              boxShadow: isAddFocused
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isAddFocused
                      ? PlixTheme.plexGold
                      : Colors.white.withOpacity(0.08),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 32,
                  color: isAddFocused ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          'Add Profile',
          style: TextStyle(
            color: PlixTheme.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 10),

        // Invisible placeholder matching height of edit button
        const SizedBox(height: 28),
      ],
    );
  }
}
