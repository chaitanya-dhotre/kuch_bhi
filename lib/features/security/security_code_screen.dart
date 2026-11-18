import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../services/security_code.dart';
import '../chat/providers/chat_provider.dart' show currentUserIdProvider;
import 'key_change_providers.dart';

/// Opens the Security code screen (registry C22).
Future<void> openSecurityCode(
  BuildContext context, {
  required String userId,
  required String name,
  String? avatarUrl,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        SecurityCodeScreen(userId: userId, name: name, avatarUrl: avatarUrl),
  ),
);

/// Spec D3/D-10: accept a contact's new code; a verified contact gets an
/// R20 confirm first. Returns true when the code was accepted.
Future<bool> confirmAndAcceptKey(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
}) async {
  final pin = ref.read(contactKeyProvider(userId)).asData?.value;
  if (pin != null && pin.verified) {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Accept the new code?',
      body:
          "You had verified $name's old code. Only accept if $name told you "
          'they reinstalled or started fresh.',
      confirmLabel: 'Accept',
    );
    if (!ok) return false;
  }
  await acceptContactKey(ref, userId);
  return true;
}

final _myLocalKeyProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.read(secureStorageProvider).getLocalPublicKey(),
);

class SecurityCodeScreen extends ConsumerWidget {
  const SecurityCodeScreen({
    super.key,
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final pin = ref.watch(contactKeyProvider(userId)).asData?.value;
    final myId = ref.watch(currentUserIdProvider).asData?.value;
    final myKey = ref.watch(_myLocalKeyProvider).asData?.value;
    final theirKey = pin?.pendingKey ?? pin?.key;
    final pending = pin?.isPending ?? false;

    Future<void> scan(String code) async {
      final scanned = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const _ScanCodePage()));
      if (scanned == null || !context.mounted) return;
      if (!scanned.startsWith(kSecurityCodeQrPrefix)) {
        showToast(context, "That's not a kuch bhi security code.", error: true);
        return;
      }
      if (scanned.substring(kSecurityCodeQrPrefix.length) != code) {
        showToast(
          context,
          "These codes don't match. Don't accept until you've talked to $name.",
          error: true,
        );
        return;
      }
      if (pending) {
        await acceptContactKey(ref, userId, verified: true);
      } else {
        await ref.read(contactKeyStoreProvider).setVerified(userId, true);
      }
      if (context.mounted) {
        showToast(context, 'Codes match. $name is verified.');
      }
    }

    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Security code'),
      body: SafeArea(
        top: false,
        child:
            (pin == null || theirKey == null || myId == null || myKey == null)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "$name's security code isn't available yet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: t.inkSoft),
                  ),
                ),
              )
            : FutureBuilder<String>(
                key: ValueKey('$myKey|$theirKey'),
                future: computeSecurityCode(myId, myKey, userId, theirKey),
                builder: (context, snap) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (pending) ...[
                      _PendingNote(name: name, since: pin.pendingSince),
                      const SizedBox(height: 12),
                    ],
                    Center(
                      child: AppAvatar(
                        url: avatarUrl,
                        initials: initialsOf(name),
                        radius: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You and $name',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CodeCard(code: snap.data),
                    const SizedBox(height: 12),
                    Text(
                      'To check that your chat is private, compare these '
                      'numbers with $name in person or on a call, or scan '
                      'their code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 18 / 13,
                        color: t.inkSoft,
                      ),
                    ),
                    if (!pending && pin.verified) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: t.success, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppButton(
                      key: const ValueKey('security-code-scan'),
                      expanded: true,
                      onPressed: snap.data == null
                          ? null
                          : () => unawaited(scan(snap.data!)),
                      child: Text("Scan $name's code"),
                    ),
                    const SizedBox(height: 8),
                    if (pending)
                      AppButton(
                        key: const ValueKey('security-code-accept'),
                        variant: AppButtonVariant.secondary,
                        expanded: true,
                        onPressed: () async {
                          final ok = await confirmAndAcceptKey(
                            context,
                            ref,
                            userId: userId,
                            name: name,
                          );
                          if (ok && context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Accept new code'),
                      )
                    else if (pin.verified)
                      AppButton(
                        key: const ValueKey('security-code-clear'),
                        variant: AppButtonVariant.text,
                        expanded: true,
                        onPressed: () => ref
                            .read(contactKeyStoreProvider)
                            .setVerified(userId, false),
                        child: const Text('Clear verified'),
                      )
                    else
                      AppButton(
                        key: const ValueKey('security-code-verify'),
                        variant: AppButtonVariant.secondary,
                        expanded: true,
                        onPressed: () => ref
                            .read(contactKeyStoreProvider)
                            .setVerified(userId, true),
                        child: const Text('Mark as verified'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PendingNote extends StatelessWidget {
  const _PendingNote({required this.name, required this.since});
  final String name;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final when = since == null
        ? ''
        : ' on ${DateFormat('d MMM').format(since!)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: t.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$name's code changed$when. These are the new numbers.",
              style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final String? code;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = code;
    final groups = c == null ? const <String>[] : securityCodeGroups(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        border: Border.all(color: t.line),
      ),
      child: Column(
        children: [
          // D9: read group by group; wraps by whole groups at large text.
          Semantics(
            label: c == null ? 'Working out the code' : groups.join(', '),
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, box) {
                  final style = TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    color: t.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  );
                  final cells = c == null ? List.filled(12, '·····') : groups;
                  // D1: 3 rows of 4 (a wide phone wrapped 7 + 5); fewer per
                  // row only when 4 whole groups don't fit (large text).
                  final groupWidth = (TextPainter(
                    text: TextSpan(text: '00000', style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout()).width;
                  final perRow = [4, 3, 2, 1].firstWhere(
                    (n) => n * groupWidth + (n - 1) * 12 <= box.maxWidth,
                    orElse: () => 1,
                  );
                  return Column(
                    key: const ValueKey('security-code-digits'),
                    children: [
                      for (var i = 0; i < cells.length; i += perRow)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (
                                var j = i;
                                j < i + perRow && j < cells.length;
                                j++
                              ) ...[
                                if (j > i) const SizedBox(width: 12),
                                Text(cells[j], style: style),
                              ],
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (c != null) ...[
            const SizedBox(height: 12),
            // A white tile in both themes so it scans (spec D2), as Profile's.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WarmPopTokens.surface,
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              ),
              child: ExcludeSemantics(
                child: QrImageView(
                  data: '$kSecurityCodeQrPrefix$c',
                  version: QrVersions.auto,
                  size: 176,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: WarmPopTokens.ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: WarmPopTokens.ink,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen scanner (spec D4). Pops with the raw QR text.
class _ScanCodePage extends StatefulWidget {
  const _ScanCodePage();

  @override
  State<_ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<_ScanCodePage> {
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Scan their code'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          child: MobileScanner(
            errorBuilder: (context, error, child) {
              if (!_done) {
                _done = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  showToast(context, "Couldn't open the camera.", error: true);
                  Navigator.of(context).pop();
                });
              }
              return ColoredBox(color: t.surface2);
            },
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (_done || raw == null) return;
              _done = true;
              Navigator.of(context).pop(raw);
            },
          ),
        ),
      ),
    );
  }
}
