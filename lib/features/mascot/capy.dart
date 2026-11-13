import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../../core/utils/app_haptic.dart';
import 'capy_look.dart';

/// Page 10 mascot (spec docs/design/pages/mascot.md §C–D). One bundled
/// `assets/mascot/capy.riv` (source: `mascot/capy/scene.rml`), four views,
/// one view model `Capy`. Decorative: never blocks anything (F1), never
/// announced (F4), and a load failure leaves an empty box.
enum CapyView { sit, front, head, onsen }

enum CapyMood { chill, active, happy, sleepy, worried, focused }

enum CapyPose { none, pet, celebrate, guard, search, vault }

/// One-shots a capybara can play when it first shows (names = rig triggers).
enum CapyOneShot { wave, swapKey, lookAround }

/// One artboard + view-model instance. The real one wraps Rive; tests fake it.
abstract class CapyRig {
  void setMood(CapyMood mood);
  void setPose(CapyPose pose);
  void setBool(String name, bool value);
  void setQueued(int queued);
  void setLookX(double x);
  void setLook(CapyLook look);
  void fire(String trigger);
  Widget get view;
  void dispose();
}

/// Makes rigs from the loaded file.
abstract class CapySource {
  CapyRig create(CapyView view);
}

/// Loads the `.riv` once per app run and caches it (D2). `null` = it could
/// not load (F1: the slot stays empty).
class CapyLoader {
  CapyLoader._();

  static Future<CapySource?>? _pending;

  /// The loaded source once ready, for a first frame without a blank box.
  static CapySource? ready;

  /// Tests set a fake (or null) here before pumping.
  @visibleForTesting
  static set debugSource(CapySource? source) {
    ready = source;
    _pending = Future.value(source);
  }

  static Future<CapySource?> get source => _pending ??= _load();

  static Future<CapySource?> _load() async {
    // The host test VM has no Rive native library.
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      final file = await rive.File.asset(
        'assets/mascot/capy.riv',
        riveFactory: rive.Factory.rive,
      );
      return ready = file == null ? null : _RiveCapySource(file);
    } catch (e) {
      debugPrint('[Capy] load failed: $e');
      return null;
    }
  }
}

class _RiveCapySource implements CapySource {
  _RiveCapySource(this.file);
  final rive.File file;

  @override
  CapyRig create(CapyView view) {
    final name = '${view.name[0].toUpperCase()}${view.name.substring(1)}';
    final c = rive.RiveWidgetController(
      file,
      artboardSelector: rive.ArtboardSelector.byName(name),
    );
    return _RiveCapyRig(c, c.dataBind(rive.DataBind.auto()));
  }
}

class _RiveCapyRig implements CapyRig {
  _RiveCapyRig(this.controller, this.vmi);
  final rive.RiveWidgetController controller;
  final rive.ViewModelInstance vmi;

  @override
  void setMood(CapyMood mood) => vmi.enumerator('mood')?.value = mood.name;
  @override
  void setPose(CapyPose pose) => vmi.enumerator('pose')?.value = pose.name;
  @override
  void setBool(String name, bool value) => vmi.boolean(name)?.value = value;
  @override
  void setQueued(int queued) => vmi.number('queued')?.value = queued.toDouble();
  @override
  void setLookX(double x) => vmi.number('lookX')?.value = x;
  @override
  void setLook(CapyLook look) => vmi.enumerator('look')?.value = look.name;
  @override
  void fire(String trigger) => vmi.trigger(trigger)?.trigger();
  @override
  late final Widget view = rive.RiveWidget(
    controller: controller,
    fit: rive.Fit.contain,
    hitTestBehavior: rive.RiveHitTestBehavior.none,
  );
  @override
  void dispose() {
    vmi.dispose();
    controller.dispose();
  }
}

class Capy extends StatefulWidget {
  const Capy({
    super.key,
    required this.view,
    this.mood = CapyMood.chill,
    this.size = 120,
    this.animated = false,
    this.flip = false,
    this.pose = CapyPose.none,
    this.queued = 0,
    this.pettable = true,
    this.lookX = 0,
    this.playOnShow,
    this.hops = 0,
    this.flushes = 0,
    this.tosses = 0,
    this.envelopes = 0,
  });

  final CapyView view;
  final CapyMood mood;

  /// Side of the square box, dp.
  final double size;

  /// false = parked on the mood's still pose (F2: at most 2 animated on screen).
  final bool animated;

  /// Mirror a profile view so it faces its content (A5).
  final bool flip;
  final CapyPose pose;

  /// Onsen yuzus (0–3 shown).
  final int queued;
  final bool pettable;

  /// Eyes and face toward a side, −1…1 (Front, Head). 0 under reduced motion.
  final double lookX;

  /// Played once when the rig first shows (X1 wave, K3 swapKey, X8 lookAround).
  final CapyOneShot? playOnShow;

  /// Each increase fires one hop / flush / tossKey / envelope (C4, E1, K1b).
  final int hops;
  final int flushes;
  final int tosses;
  final int envelopes;

  @override
  State<Capy> createState() => _CapyState();
}

class _CapyState extends State<Capy> {
  CapyRig? _rig;
  CapySource? _source;

  // K1: every capybara wears the current look (not stickers: they are PNGs).
  void _onLook() => _rig?.setLook(CapyLook.current.value);

  @override
  void initState() {
    super.initState();
    CapyLook.current.addListener(_onLook);
    if (CapyLoader.ready == null) {
      CapyLoader.source.then((s) {
        if (mounted && s != null) setState(() {});
      });
    }
  }

  CapyRig? _ensureRig(CapySource? source) {
    if (source == null || identical(source, _source)) return _rig;
    _rig?.dispose();
    _source = source;
    try {
      _rig = source.create(widget.view);
    } catch (e) {
      debugPrint('[Capy] ${widget.view.name} failed: $e');
      _rig = null;
      return null;
    }
    _sync(_rig!);
    if (widget.playOnShow case final shot?) _rig!.fire(shot.name);
    return _rig;
  }

  void _sync(CapyRig rig) {
    rig
      ..setMood(widget.mood)
      ..setPose(widget.pose)
      ..setBool('still', !widget.animated)
      ..setQueued(widget.queued.clamp(0, 3))
      ..setLook(CapyLook.current.value);
  }

  @override
  void didUpdateWidget(Capy old) {
    super.didUpdateWidget(old);
    final rig = _rig;
    if (rig == null) return;
    if (old.view != widget.view) {
      rig.dispose();
      _rig = null;
      _source = null;
      return;
    }
    _sync(rig);
    for (var i = old.flushes; i < widget.flushes; i++) {
      rig.fire('flush');
    }
    for (var i = old.hops; i < widget.hops; i++) {
      rig.fire('hop');
    }
    for (var i = old.tosses; i < widget.tosses; i++) {
      rig.fire('tossKey');
    }
    for (var i = old.envelopes; i < widget.envelopes; i++) {
      rig.fire('envelope');
    }
  }

  @override
  void dispose() {
    CapyLook.current.removeListener(_onLook);
    _rig?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rig = _ensureRig(CapyLoader.ready);
    final box = SizedBox.square(dimension: widget.size);
    if (rig == null) return box;
    final reduced = MediaQuery.disableAnimationsOf(context);
    rig
      ..setBool('reducedMotion', reduced)
      ..setLookX(reduced ? 0 : widget.lookX.clamp(-1.0, 1.0));
    Widget child = Transform.flip(flipX: widget.flip, child: rig.view);
    if (widget.pettable) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          rig.fire('pet');
          appHaptic(HapticsType.light);
        },
        onLongPressStart: (_) => rig.setBool('holding', true),
        onLongPressEnd: (_) => rig.setBool('holding', false),
        onLongPressCancel: () => rig.setBool('holding', false),
        child: child,
      );
    }
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(dimension: widget.size, child: child),
      ),
    );
  }
}
