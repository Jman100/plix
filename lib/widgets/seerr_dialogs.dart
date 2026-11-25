import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/seerr_service.dart';
import '../services/plix_device_helper.dart';
import 'plix_button.dart';
import 'plix_tv_text_field.dart';

class SeerrUrlConfigDialog extends StatefulWidget {
  final PlexServer server;
  final String? initialUrl;

  const SeerrUrlConfigDialog({
    super.key,
    required this.server,
    this.initialUrl,
  });

  static Future<String?> show(
    BuildContext context, {
    required PlexServer server,
    String? initialUrl,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => SeerrUrlConfigDialog(server: server, initialUrl: initialUrl),
    );
  }

  @override
  State<SeerrUrlConfigDialog> createState() => _SeerrUrlConfigDialogState();
}

class _SeerrUrlConfigDialogState extends State<SeerrUrlConfigDialog> {
  final TextEditingController _urlController = TextEditingController();
  late final FocusNode _urlFocusNode;
  final FocusNode _testFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _saveFocusNode = FocusNode();

  bool _isTesting = false;
  bool? _testSuccess;
  String? _testMessage;
  bool _isKeyboardOpen = false;

  @override
  void initState() {
    super.initState();
    _urlFocusNode = FocusNode();
    _urlFocusNode.addListener(_handleFocusChange);
    _loadInitialUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _urlFocusNode.requestFocus();
      }
    });
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitialUrl() async {
    String? url = widget.initialUrl;
    if (url == null || url.isEmpty) {
      url = await SeerrService().getSeerrUrl(widget.server.clientIdentifier);
    }
    if (url != null && mounted) {
      _urlController.text = url;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.removeListener(_handleFocusChange);
    _urlFocusNode.dispose();
    _testFocusNode.dispose();
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = 'Please enter a URL first.';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testMessage = null;
    });

    final success = await SeerrService().testConnection(raw);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _testSuccess = success;
      _testMessage = success
          ? 'Connected successfully to Seerr instance!'
          : 'Could not connect. Please check URL and network.';
    });
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final normalized = SeerrService().normalizeUrl(url);
    await SeerrService().setSeerrUrl(widget.server.clientIdentifier, normalized);
    if (mounted) {
      Navigator.of(context).pop(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final hasKeyboard = _isKeyboardOpen || mediaQuery.viewInsets.bottom > 0;
    final isUrlFocused = _urlFocusNode.hasFocus;
    final BoxBorder urlBorder = isUrlFocused && PlixTheme.isRainbowBorder
        ? PlixTheme.rainbowOutlineBorder(width: 2.0)
        : Border.all(
            color: isUrlFocused ? PlixTheme.plexGold : Colors.white.withOpacity(0.12),
            width: 2.0,
          );

    final bool isTv = PlixDeviceHelper.isTelevision;
    final bool isCompact = PlixDeviceHelper.isCompact(context);
    final double keyboardOffset = hasKeyboard ? (isTv ? -0.17 : -0.20) : 0.0;

    return MediaQuery(
      data: mediaQuery.copyWith(viewInsets: EdgeInsets.zero),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        offset: Offset(0, keyboardOffset),
        child: Dialog(
          backgroundColor: PlixTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(isCompact ? 16.0 : 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: PlixTheme.plexGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.link_rounded, color: PlixTheme.plexGold, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Configure Seerr URL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'For ${widget.server.name} (${widget.server.isJellyfin ? "Jellyfin" : "Plex"})',
                            style: const TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Enter the URL of your Seerr (Overseerr / Jellyseerr) instance to request media and report issues. No leading https:// is needed.',
                  style: TextStyle(color: PlixTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: urlBorder,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: SizedBox(
                    height: 32,
                    child: PlixTvTextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      isUrl: true,
                      hintText: 'seerr.example.com',
                      imeAction: 'done',
                      onKeyboardStateChanged: (open) {
                        if (mounted && _isKeyboardOpen != open) {
                          setState(() => _isKeyboardOpen = open);
                        }
                      },
                      onDown: () => _testFocusNode.requestFocus(),
                      onSubmitted: (_) => _testConnection(),
                    ),
                  ),
                ),
                if (_isTesting || _testMessage != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_isTesting) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: PlixTheme.plexGold),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Testing connection...',
                          style: TextStyle(color: PlixTheme.textSecondary, fontSize: 12),
                        ),
                      ] else if (_testSuccess == true) ...[
                        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage ?? 'Connected!',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                          ),
                        ),
                      ] else ...[
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage ?? 'Connection failed',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlixButton(
                      focusNode: _testFocusNode,
                      isPrimary: false,
                      label: 'Test',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onUp: () => _urlFocusNode.requestFocus(),
                      onRight: () => _cancelFocusNode.requestFocus(),
                      onPressed: _testConnection,
                    ),
                    const SizedBox(width: 10),
                    PlixButton(
                      focusNode: _cancelFocusNode,
                      isPrimary: false,
                      label: 'Cancel',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onUp: () => _urlFocusNode.requestFocus(),
                      onLeft: () => _testFocusNode.requestFocus(),
                      onRight: () => _saveFocusNode.requestFocus(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    PlixButton(
                      focusNode: _saveFocusNode,
                      isPrimary: true,
                      label: 'Save',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      onUp: () => _urlFocusNode.requestFocus(),
                      onLeft: () => _cancelFocusNode.requestFocus(),
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}

class ReportIssueDialog extends StatefulWidget {
  final PlexServer server;
  final PlexMediaItem item;

  const ReportIssueDialog({
    super.key,
    required this.server,
    required this.item,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PlexServer server,
    required PlexMediaItem item,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => ReportIssueDialog(server: server, item: item),
    );
  }

  @override
  State<ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<ReportIssueDialog> {
  final TextEditingController _commentController = TextEditingController();
  late final FocusNode _messageFocusNode;
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _submitFocusNode = FocusNode();
  final FocusNode _changeUrlFocusNode = FocusNode();

  final List<FocusNode> _categoryFocusNodes = [
    FocusNode(),
    FocusNode(),
    FocusNode(),
    FocusNode(),
  ];

  SeerrIssueType _selectedType = SeerrIssueType.video;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isKeyboardOpen = false;

  @override
  void initState() {
    super.initState();
    _messageFocusNode = FocusNode();
    _messageFocusNode.addListener(_handleStateChange);
    _commentController.addListener(_handleStateChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _categoryFocusNodes.first.requestFocus();
      }
    });
  }

  void _handleStateChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_handleStateChange);
    _messageFocusNode.removeListener(_handleStateChange);
    _commentController.dispose();
    _messageFocusNode.dispose();
    _cancelFocusNode.dispose();
    _submitFocusNode.dispose();
    _changeUrlFocusNode.dispose();
    for (final fn in _categoryFocusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  Future<void> _changeSeerrUrl() async {
    final currentUrl = await SeerrService().getSeerrUrl(widget.server.clientIdentifier);
    if (!mounted) return;
    await SeerrUrlConfigDialog.show(
      context,
      server: widget.server,
      initialUrl: currentUrl,
    );
  }

  Future<void> _submitReport() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      setState(() {
        _errorMessage = 'Please describe the issue before submitting.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await SeerrService().submitIssue(
      server: widget.server,
      item: widget.item,
      issueType: _selectedType.id,
      message: comment,
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.message ?? 'Failed to submit issue report.';
      });
    }
  }

  Widget _buildCategoryChip(SeerrIssueType type, int index) {
    final isSelected = _selectedType == type;
    final fn = _categoryFocusNodes[index];

    IconData icon;
    switch (type) {
      case SeerrIssueType.video:
        icon = Icons.videocam_rounded;
        break;
      case SeerrIssueType.audio:
        icon = Icons.volume_up_rounded;
        break;
      case SeerrIssueType.subtitles:
        icon = Icons.subtitles_rounded;
        break;
      case SeerrIssueType.other:
        icon = Icons.help_outline_rounded;
        break;
    }

    return Focus(
      focusNode: fn,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _messageFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
            _categoryFocusNodes[index - 1].requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
              index < _categoryFocusNodes.length - 1) {
            _categoryFocusNodes[index + 1].requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            setState(() {
              _selectedType = type;
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: fn,
        builder: (context, _) {
          final isFocused = fn.hasFocus;
          final BoxBorder chipBorder = isFocused && PlixTheme.isRainbowBorder
              ? PlixTheme.rainbowOutlineBorder(width: 2.0)
              : Border.all(
                  color: isFocused
                      ? PlixTheme.plexGold
                      : (isSelected
                          ? PlixTheme.plexGold.withOpacity(0.6)
                          : Colors.white.withOpacity(0.1)),
                  width: 2.0,
                );

          final isCompact = PlixDeviceHelper.isCompact(context);
          final double hPadding = isCompact ? 1.0 : 6.0;
          final double iconSize = isCompact ? 11.0 : 14.0;
          final double gap = isCompact ? 2.5 : 5.0;
          final double fontSize = isCompact ? 9.5 : 12.0;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedType = type;
              });
              fn.requestFocus();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? PlixTheme.plexGold.withOpacity(0.18)
                    : (isFocused ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.06)),
                borderRadius: BorderRadius.circular(8),
                border: chipBorder,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: iconSize,
                    color: isSelected
                        ? PlixTheme.plexGold
                        : (isFocused ? Colors.white : PlixTheme.textSecondary),
                  ),
                  SizedBox(width: gap),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        type.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isFocused ? Colors.white : PlixTheme.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final itemSubtitle = item.isEpisode
        ? '${item.grandparentTitle ?? ''} S${item.parentIndex ?? 1}:E${item.index ?? 1} - ${item.title}'
        : '${item.title}${item.year != null ? ' (${item.year})' : ''}';

    final mediaQuery = MediaQuery.of(context);
    final hasKeyboard = _isKeyboardOpen || mediaQuery.viewInsets.bottom > 0;
    final isMsgFocused = _messageFocusNode.hasFocus;
    final BoxBorder msgBorder = isMsgFocused && PlixTheme.isRainbowBorder
        ? PlixTheme.rainbowOutlineBorder(width: 2.0)
        : Border.all(
            color: isMsgFocused ? PlixTheme.plexGold : Colors.white.withOpacity(0.12),
            width: 2.0,
          );

    final bool isTv = PlixDeviceHelper.isTelevision;
    final bool isCompact = PlixDeviceHelper.isCompact(context);
    final double keyboardOffset = hasKeyboard ? (isTv ? -0.17 : -0.20) : 0.0;

    return MediaQuery(
      data: mediaQuery.copyWith(viewInsets: EdgeInsets.zero),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        offset: Offset(0, keyboardOffset),
        child: Dialog(
          backgroundColor: PlixTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 16.0 : 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.report_problem_rounded, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Report an Issue',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            itemSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PlixButton(
                      focusNode: _changeUrlFocusNode,
                      isPrimary: false,
                      label: 'Seerr URL',
                      fontSize: 11,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      icon: const Icon(Icons.settings_outlined, size: 14),
                      onDown: () => _categoryFocusNodes.first.requestFocus(),
                      onPressed: _changeSeerrUrl,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Issue Category',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (int i = 0; i < SeerrIssueType.values.length; i++) ...[
                      if (i > 0) SizedBox(width: isCompact ? 4 : 6),
                      Expanded(
                        child: _buildCategoryChip(SeerrIssueType.values[i], i),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Description / Details',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: msgBorder,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: SizedBox(
                    height: 32,
                    child: PlixTvTextField(
                      controller: _commentController,
                      focusNode: _messageFocusNode,
                      hintText: 'Describe the issue (e.g. video freezes at 14:20)...',
                      imeAction: 'done',
                      onKeyboardStateChanged: (open) {
                        if (mounted && _isKeyboardOpen != open) {
                          setState(() => _isKeyboardOpen = open);
                        }
                      },
                      onUp: () => _categoryFocusNodes.first.requestFocus(),
                      onDown: () => _submitFocusNode.requestFocus(),
                      onSubmitted: (_) => _submitReport(),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlixButton(
                      focusNode: _cancelFocusNode,
                      isPrimary: false,
                      label: 'Cancel',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onUp: () => _messageFocusNode.requestFocus(),
                      onRight: () => _submitFocusNode.requestFocus(),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 10),
                    PlixButton(
                      focusNode: _submitFocusNode,
                      isPrimary: true,
                      label: _isSubmitting ? 'Submitting...' : 'Submit Report',
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      onUp: () => _messageFocusNode.requestFocus(),
                      onLeft: () => _cancelFocusNode.requestFocus(),
                      onPressed: _isSubmitting ? () {} : _submitReport,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}
