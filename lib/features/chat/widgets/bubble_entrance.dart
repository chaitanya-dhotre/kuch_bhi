import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/entities/message.dart';
import 'expiry_badge.dart';

/// Motion C1–C3 / C10: how one chat row moves when it appears or leaves.
enum BubbleMotion {
  /// C1 (M-5 B): a short text, a voice note or a sticker grows out of the
  /// composer. Text morphs from the field's box; anything else (and an
  /// emoji-only text, which has no bubble fill) flies a snapshot of itself.
  grow,

  /// C1 simple: rise 12 dp, 0.96 → 1 from the bottom-right, fade in.
  send,

  /// C2: an incoming bubble, 8 dp from the bottom-left, 180 ms.
  arrive,
}

/// C1: the typed text (null for voice and stickers) and the composer
/// field's box at the frame of the tap.
class SendFlight {
  const SendFlight(this.text, this.from);
  final String? text;
  final Rect from;
}

/// C3: decides, once per message id, whether a row gets an entrance. The
/// first list the screen sees is history (none), and a re-emit of a known
/// id never replays one. Only the newest two rows may move (L5).
class ChatEntrances {
  final Set<String> _known = {};
  bool _primed = false;
  final Map<String, BubbleMotion> _motion = {};
  final Map<String, SendFlight> _flights = {};
  SendFlight? _pendingFlight;
  DateTime? _pendingAt;

  /// L6: a new send snaps every running entrance to its end.
  final ValueNotifier<int> snap = ValueNotifier(0);

  /// C1: the next own text row flies from [flight]. Null = the simple rise.
  void sending(SendFlight? flight) {
    _pendingFlight = flight;
    _pendingAt = DateTime.now();
    snap.value++;
  }

  /// [newestFirst] is the whole list as the screen will draw it. Returns
  /// how many of their messages arrived while [atBottom] was false (C7).
  int observe(
    List<Message> newestFirst, {
    required String myId,
    required bool atBottom,
  }) {
    if (!_primed) {
      _primed = true;
      _known.addAll(newestFirst.map((m) => m.localId));
      return 0;
    }
    var below = 0;
    for (var i = 0; i < newestFirst.length; i++) {
      final m = newestFirst[i];
      if (!_known.add(m.localId) || i >= 2 || m.type == 'system') continue;
      final mine = m.senderId == myId;
      if (!mine) {
        atBottom ? _motion[m.localId] = BubbleMotion.arrive : below++;
        continue;
      }
      final flight = _pendingFlight;
      final fresh =
          _pendingAt != null &&
          DateTime.now().difference(_pendingAt!) < const Duration(seconds: 2);
      if (flight != null &&
          fresh &&
          atBottom &&
          const {'text', 'voice', 'sticker'}.contains(m.type)) {
        _motion[m.localId] = BubbleMotion.grow;
        _flights[m.localId] = flight;
      } else {
        _motion[m.localId] = BubbleMotion.send;
      }
      _pendingFlight = null;
    }
    return below;
  }

  /// The row's entrance, handed out once.
  BubbleMotion? take(String localId) => _motion.remove(localId);

  SendFlight? takeFlight(String localId) => _flights.remove(localId);

  void dispose() => snap.dispose();
}

/// Wraps one chat row. [motion] is read once, when the row is first built.
/// [leaving] (C10) fades the row and closes its height, then [onLeft].
class BubbleEntrance extends StatefulWidget {
  const BubbleEntrance({
    super.key,
    required this.motion,
    required this.child,
    this.flight,
    this.snap,
    this.leaving = false,
    this.onLeft,
  });

  final BubbleMotion? motion;
  final SendFlight? flight;
  final Listenable? snap;
  final bool leaving;
  final VoidCallback? onLeft;
  final Widget child;

  @override
  State<BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<BubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final BubbleMotion? _motion = widget.motion;
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: _motion == null ? 1 : 0,
    duration: switch (_motion) {
      BubbleMotion.grow => WarmPopTokens.motionSend,
      BubbleMotion.arrive => WarmPopTokens.motionArrive,
      _ => WarmPopTokens.motionEnter,
    },
    reverseDuration: WarmPopTokens.motionExit,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _c,
    curve: _motion == BubbleMotion.grow
        ? WarmPopTokens.curveMove
        : WarmPopTokens.curveEnter,
    // L3: leaving accelerates away in real time.
    reverseCurve: WarmPopTokens.curveExit.flipped,
  );
  late final Animation<double> _growSize = _eased.drive(
    Tween(begin: 0.02, end: 1.0),
  );
  bool _leaving = false;
  final _content = GlobalKey();
  final _boundary = GlobalKey();
  OverlayEntry? _overlay;
  bool _started = false;

  /// Snapshot flight: the row paints at alpha 1/255 for its first frame so
  /// the snapshot has pixels, then hides until the copy lands.
  bool _ghost = false;
  ui.Image? _shot;

  bool get _landed => _motion != BubbleMotion.grow || _c.isCompleted;

  @override
  void initState() {
    super.initState();
    widget.snap?.addListener(_snapToEnd);
    _c.addStatusListener((s) {
      if (!s.isAnimating) _removeOverlay();
      if (s.isDismissed && _leaving) widget.onLeft?.call();
      if (s.isCompleted && _motion == BubbleMotion.grow && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _motion == null) return;
    _started = true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _c.value = 1;
      return;
    }
    _c.forward();
    final flight = widget.flight;
    if (_motion == BubbleMotion.grow && flight != null) {
      _ghost = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fly(flight));
    }
  }

  @override
  void didUpdateWidget(BubbleEntrance old) {
    super.didUpdateWidget(old);
    if (!widget.leaving || _leaving) return;
    _leaving = true;
    _removeOverlay();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onLeft?.call(),
      );
    } else {
      _c.reverse(from: 1);
    }
  }

  void _snapToEnd() {
    if (_c.isAnimating && !_leaving) _c.value = 1;
  }

  void _fly(SendFlight flight) {
    if (!mounted) return;
    final ghost = _ghost;
    _ghost = false;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = _bubbleBox();
    if (overlay == null || !_c.isAnimating) {
      if (ghost) setState(() {});
      return;
    }
    final text = flight.text;
    if (text != null && box != null) {
      _insert(overlay, _textFlight(flight, text));
    } else {
      final rest = box?.rect ?? _visualRect();
      final shot = rest == null ? null : _snapshot(rest);
      if (shot == null) {
        _c.value = 1; // nothing to fly: show the bubble where it rests
      } else {
        _insert(overlay, _shotFlight(flight.from, rest!, shot));
      }
    }
    setState(() {});
  }

  void _insert(OverlayState overlay, Widget flight) {
    _overlay = OverlayEntry(builder: (_) => IgnorePointer(child: flight));
    overlay.insert(_overlay!);
  }

  /// The field's box turns into the bubble: size, corners, fill, padding.
  Widget _textFlight(SendFlight flight, String text) {
    final t = context.t;
    // The bubble's own text style: the app font from the row's context.
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: t.ink,
        fontSize: 15,
        height: 20 / 15,
        decoration: TextDecoration.none,
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _eased,
        builder: (context, _) {
          final target = _bubbleBox();
          if (target == null) return const SizedBox.shrink();
          final v = _eased.value;
          final rect = Rect.lerp(flight.from, target.rect, v)!;
          final radius = BorderRadius.lerp(
            BorderRadius.circular(WarmPopTokens.radiusXl),
            target.radius,
            v,
          )!;
          const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 9);
          final inner = target.rect.width - pad.horizontal;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(t.surface2, target.fill, v),
                    borderRadius: radius,
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Padding(
                      // The field puts its text 16 in, centred in 48.
                      padding: EdgeInsets.lerp(
                        const EdgeInsets.fromLTRB(16, 14, 8, 0),
                        pad,
                        v,
                      )!,
                      // Laid out at the bubble's width all the way, so the
                      // text wraps once, as it will in the bubble.
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: inner > 0 ? inner + 1 : 0, // +1: rounding never wraps
                        maxHeight: double.infinity,
                        child: Text(text, style: style, textScaler: scaler),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A snapshot of the bubble starts small inside the composer and grows to
  /// where the bubble rests.
  Widget _shotFlight(Rect from, Rect rest, ({ui.Image image, Rect src}) shot) {
    _shot = shot.image;
    final s = (from.height / rest.height).clamp(0.2, 1.0);
    final start = Rect.fromLTWH(
      from.left + 12,
      from.center.dy - rest.height * s / 2,
      rest.width * s,
      rest.height * s,
    );
    return AnimatedBuilder(
      animation: _eased,
      builder: (context, _) => Stack(
        children: [
          Positioned.fromRect(
            rect: Rect.lerp(start, rest, _eased.value)!,
            child: CustomPaint(painter: _ShotPainter(shot.image, shot.src)),
          ),
        ],
      ),
    );
  }

  ({ui.Image image, Rect src})? _snapshot(Rect rest) {
    final rb = _boundary.currentContext?.findRenderObject();
    if (rb is! RenderRepaintBoundary || !rb.hasSize || !rb.attached) {
      return null;
    }
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final local = rest.shift(-rb.localToGlobal(Offset.zero));
      return (
        image: rb.toImageSync(pixelRatio: dpr),
        src: Rect.fromLTRB(
          local.left * dpr,
          local.top * dpr,
          local.right * dpr,
          local.bottom * dpr,
        ),
      );
    } catch (_) {
      return null; // a missed snapshot only skips the flight
    }
  }

  /// No fill box (emoji, sticker): the box [ChatBubbleFrame] marks.
  Rect? _visualRect() {
    final root = _content.currentContext?.findRenderObject();
    if (root == null) return null;
    final queue = <RenderObject>[root];
    while (queue.isNotEmpty) {
      final r = queue.removeAt(0);
      if (r is RenderMetaData &&
          r.metaData == ChatBubbleFrame.box &&
          r.hasSize &&
          r.size.height > 0) {
        return r.localToGlobal(Offset.zero) & r.size;
      }
      r.visitChildren(queue.add);
    }
    return null;
  }

  /// The bubble's own fill box inside this row: rect, radius and colour.
  ({Rect rect, BorderRadius radius, Color fill})? _bubbleBox() {
    final root = _content.currentContext;
    if (root == null || !root.mounted) return null;
    ({Rect rect, BorderRadius radius, Color fill})? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is DecoratedBox &&
          w.position == DecorationPosition.background &&
          w.decoration is BoxDecoration) {
        final d = w.decoration as BoxDecoration;
        final box = e.renderObject;
        if (d.color != null &&
            d.borderRadius != null &&
            box is RenderBox &&
            box.hasSize &&
            box.attached) {
          found = (
            rect: box.localToGlobal(Offset.zero) & box.size,
            radius: d.borderRadius!.resolve(TextDirection.ltr),
            fill: d.color!,
          );
          return;
        }
      }
      e.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);
    return found;
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _shot?.dispose();
    _shot = null;
  }

  @override
  void dispose() {
    widget.snap?.removeListener(_snapToEnd);
    _removeOverlay();
    _eased.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyed, so the row keeps its state when it starts leaving.
    final child = KeyedSubtree(
      key: _content,
      child: _motion == BubbleMotion.grow
          ? RepaintBoundary(key: _boundary, child: widget.child)
          : widget.child,
    );
    if (_leaving) {
      return SizeTransition(
        sizeFactor: _eased,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: _eased, child: child),
      );
    }
    if (_motion == null) return child;
    final mine = _motion != BubbleMotion.arrive;
    final rise = _motion == BubbleMotion.arrive ? 8.0 : 12.0;
    return SizeTransition(
      // A list skips painting a row of no height; the grow's first frame
      // must paint (at alpha 1/255) for its snapshot, so it starts ~1 dp tall.
      sizeFactor: _motion == BubbleMotion.grow ? _growSize : _eased,
      alignment: Alignment.bottomCenter,
      child: switch (_motion) {
        BubbleMotion.grow => FadeTransition(
          opacity: _landed
              ? kAlwaysCompleteAnimation
              : AlwaysStoppedAnimation(_ghost ? 1 / 255 : 0),
          child: child,
        ),
        _ => AnimatedBuilder(
          animation: _eased,
          child: child,
          builder: (context, child) => Opacity(
            opacity: _eased.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, rise * (1 - _eased.value)),
              child: Transform.scale(
                scale: 0.96 + 0.04 * _eased.value,
                alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
                child: child,
              ),
            ),
          ),
        ),
      },
    );
  }
}

class _ShotPainter extends CustomPainter {
  _ShotPainter(this.image, this.src);
  final ui.Image image;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    src,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.medium,
  );

  @override
  bool shouldRepaint(_ShotPainter old) => old.image != image;
}
