import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../features/chat/message_offline_policy.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/friend_requests/providers/friend_request_provider.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/friends_provider.dart';

/// Registry C13: the ONE way to open Add a friend, always from a fresh state.
void showAddFriendSheet(BuildContext context, WidgetRef ref) {
  ref.read(addFriendProvider.notifier).reset();
  showAppSheet<void>(
    context: context,
    builder: (_) => const AddFriendSheet(),
  );
}

class AddFriendSheet extends ConsumerStatefulWidget {
  const AddFriendSheet({super.key});

  @override
  ConsumerState<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<AddFriendSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();
  bool _scannerActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // The code field keeps focus across tabs; the camera needs the room.
      if (_tabController.index == 1) FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _scannerActive = _tabController.index == 1);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final state = ref.watch(addFriendProvider);

    return AppSheetChrome(
      title: 'Add a friend',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: t.ink,
            unselectedLabelColor: t.inkSoft,
            labelStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(color: t.accent, width: 3),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: t.line,
            tabs: const [
              Tab(height: 48, text: 'Friend code'),
              Tab(height: 48, text: 'Scan QR'),
            ],
          ),
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CodeSearchTab(
                  controller: _codeController,
                  state: state,
                ),
                // Its own messenger: a toast on the root Scaffold sits under
                // this sheet, which stays open while the camera runs.
                ScaffoldMessenger(
                  child: Stack(
                    children: [
                      _QrScanTab(
                        isActive: _scannerActive,
                        onCodeFound: (code) {
                          _tabController.animateTo(0);
                          _codeController.text = code;
                          // E8: offline a scan only fills the field.
                          if (ref.read(isOnlineProvider).value ?? true) {
                            ref
                                .read(addFriendProvider.notifier)
                                .searchByCode(code);
                          }
                        },
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: Scaffold(backgroundColor: Colors.transparent),
                        ),
                      ),
                    ],
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

class _CodeSearchTab extends ConsumerWidget {
  const _CodeSearchTab({required this.controller, required this.state});
  final TextEditingController controller;
  final AddFriendState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final online = ref.watch(isOnlineProvider).value ?? true;
    final caption = TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft);
    final canSearch = online && !state.isSearching;
    void search() =>
        ref.read(addFriendProvider.notifier).searchByCode(controller.text);

    final found = state.foundUser;
    // Decision 3: local data only, no new server call.
    final myId = ref.watch(currentUserIdProvider).valueOrNull;
    final friends = ref.watch(friendshipsProvider).valueOrNull ?? const [];
    final String? blockedLine = found == null
        ? null
        : found.id == myId
            ? "That's your code."
            : friends.any((f) => f.friend.id == found.id)
                ? "You're already friends."
                : null;
    final showSend = found != null && !state.requestSent && blockedLine == null;

    final hint = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(kOfflineActionHint, style: caption),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.requestSent)
            _SentCard(name: found?.displayName ?? '')
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      UpperCaseTextFormatter(),
                    ],
                    style: TextStyle(fontSize: 15, color: t.ink),
                    decoration: appFieldDecoration(
                      context,
                      label: 'Friend code',
                      hint: 'e.g. CHAI42',
                      helper:
                          "Six letters or numbers, from your friend's profile.",
                    ).copyWith(
                      counterText: '',
                      helperMaxLines: 3,
                      error: state.searchError == null
                          ? null
                          : appFieldError(context, state.searchError!),
                    ),
                    onSubmitted: (v) {
                      if (canSearch) {
                        ref.read(addFriendProvider.notifier).searchByCode(v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                _SearchButton(
                  online: online,
                  searching: state.isSearching,
                  onPressed: canSearch ? search : null,
                ),
              ],
            ),
            if (!online && !showSend) hint,
            if (found != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
                ),
                child: Row(
                  children: [
                    AppAvatar(
                      url: found.avatarUrl,
                      initials: initialsOf(found.displayName),
                      radius: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            found.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              height: 22 / 16,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                          Text('@${found.username}', style: caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (blockedLine != null)
                Text(blockedLine, style: caption)
              else ...[
                Opacity(
                  opacity: online ? 1 : .38,
                  child: AppButton(
                    expanded: true,
                    busy: state.isSendingRequest,
                    onPressed: online
                        ? () =>
                            ref.read(addFriendProvider.notifier).sendRequest()
                        : null,
                    child: const Text('Send friend request'),
                  ),
                ),
                if (!online) hint,
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// The accent search button (48×56). Searching = the R3a ring on surface2
/// (an accent ring would vanish on the accent fill). Offline = one 38% dim.
class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.online,
    required this.searching,
    required this.onPressed,
  });

  final bool online;
  final bool searching;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Search',
      // excludeSemantics drops the child's tap; give it back here.
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: online ? 1 : .38,
        child: Material(
          color: searching ? t.surface2 : t.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          ),
          child: InkWell(
            key: const Key('add-friend-search'),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
            ),
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 56,
              child: Center(
                child: searching
                    ? const BusySpinner()
                    : Icon(Icons.search, color: t.onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, color: t.success, size: 36),
        const SizedBox(height: 12),
        Text(
          'Request sent to $name.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "They'll show up in your chats once they accept.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft),
        ),
        const SizedBox(height: 16),
        AppButton(
          variant: AppButtonVariant.secondary,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _QrScanTab extends StatefulWidget {
  const _QrScanTab({required this.isActive, required this.onCodeFound});
  final bool isActive;
  final ValueChanged<String> onCodeFound;

  @override
  State<_QrScanTab> createState() => _QrScanTabState();
}

class _QrScanTabState extends State<_QrScanTab> {
  bool _pickingFromGallery = false;

  void _parseCode(String raw) {
    String code = raw;
    if (raw.startsWith('kuchbhi://add/')) {
      code = raw.replaceFirst('kuchbhi://add/', '');
    }
    if (code.length == 6) widget.onCodeFound(code.toUpperCase());
  }

  Future<void> _pickFromGallery() async {
    if (_pickingFromGallery) return;
    setState(() => _pickingFromGallery = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      // The platform decodes the photo directly: a throwaway controller's
      // dispose() would also stop the live camera on this tab (E10).
      final result =
          await MobileScannerPlatform.instance.analyzeImage(picked.path);
      if (result == null || result.barcodes.isEmpty) {
        if (mounted) {
          showToast(context, 'No QR code in that photo.', error: true);
        }
        return;
      }
      final raw = result.barcodes.first.rawValue ?? '';
      if (raw.isNotEmpty) _parseCode(raw);
    } catch (e) {
      debugPrint('[AddFriend] QR photo read failed: $e');
      if (mounted) showToast(context, "Couldn't read that photo.", error: true);
    } finally {
      if (mounted) setState(() => _pickingFromGallery = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final radius = BorderRadius.circular(WarmPopTokens.radiusMd);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: !widget.isActive
                  ? ColoredBox(
                      color: t.surface2,
                      child: Center(
                        child: Icon(
                          Icons.qr_code_scanner,
                          size: 80,
                          color: t.inkSoft,
                        ),
                      ),
                    )
                  : MobileScanner(
                      errorBuilder: (context, error, child) =>
                          const _CameraUnavailable(),
                      onDetect: (capture) {
                        final barcode = capture.barcodes.firstOrNull;
                        if (barcode == null) return;
                        _parseCode(barcode.rawValue ?? '');
                      },
                    ),
            ),
          ),
          // Gallery pick button — bottom right
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: 'Pick a photo of a QR code',
              child: Material(
                color: _pickingFromGallery ? t.surface2 : t.accent,
                shape: RoundedRectangleBorder(borderRadius: radius),
                child: InkWell(
                  key: const Key('add-friend-gallery'),
                  customBorder: RoundedRectangleBorder(borderRadius: radius),
                  onTap: _pickingFromGallery ? null : _pickFromGallery,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: _pickingFromGallery
                          ? const BusySpinner()
                          : Icon(
                              Icons.photo_library_outlined,
                              color: t.onAccent,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// E10: shown instead of the scanner package's raw error widget.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ColoredBox(
      color: t.surface2,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined, size: 36, color: t.inkSoft),
              const SizedBox(height: 12),
              Text(
                'Camera unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Allow camera access in system settings, or pick a photo of '
                'the code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: t.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Forces text input to uppercase.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
