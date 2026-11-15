import 'package:flutter/material.dart';

import 'tokens.dart';

bool get _reduced => WidgetsBinding
    .instance
    .platformDispatcher
    .accessibilityFeatures
    .disableAnimations;

/// Motion B2 (M-1 A): the incoming page slides in from 24 dp to the right
/// and fades up, the page under it moves 8 dp left and dims to 0.6. Pop is
/// the reverse at 240 ms. A predictive back gesture still drives Flutter's
/// own Android transition. Reduced motion (L7): a 150 ms fade.
class WarmPopPageTransitionsBuilder extends PageTransitionsBuilder {
  const WarmPopPageTransitionsBuilder();

  static const _predictive = PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      _reduced ? WarmPopTokens.motionFast : WarmPopTokens.motionPage;

  @override
  Duration get reverseTransitionDuration =>
      _reduced ? WarmPopTokens.motionFast : WarmPopTokens.motionPagePop;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The page subtree is keyed by the route, so switching branches when a
    // back gesture starts keeps its state.
    final gesture = route.popGestureInProgress;
    final ours = MediaQuery.disableAnimationsOf(context)
        ? FadeTransition(opacity: animation, child: child)
        : _SlideFade(
            animation: gesture ? kAlwaysCompleteAnimation : animation,
            secondary: gesture ? kAlwaysDismissedAnimation : secondaryAnimation,
            child: child,
          );
    return _predictive.buildTransitions(
      route,
      context,
      gesture ? animation : kAlwaysCompleteAnimation,
      gesture ? secondaryAnimation : kAlwaysDismissedAnimation,
      ours,
    );
  }
}

class _SlideFade extends StatelessWidget {
  const _SlideFade({
    required this.animation,
    required this.secondary,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _PageOpacity(animation, secondary),
      child: AnimatedBuilder(
        animation: Listenable.merge([animation, secondary]),
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            24 * (1 - _eased(animation)) - 8 * _eased(secondary),
            0,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Enter on curveEnter; leaving (status reverse) accelerates away on
/// curveExit in real time (L3).
double _eased(Animation<double> a) => a.status == AnimationStatus.reverse
    ? 1 - WarmPopTokens.curveExit.transform(1 - a.value)
    : WarmPopTokens.curveEnter.transform(a.value);

/// In: 0 → 1. Covered by the next page: down to 0.6.
class _PageOpacity extends CompoundAnimation<double> {
  _PageOpacity(Animation<double> incoming, Animation<double> covered)
    : super(first: incoming, next: covered);

  @override
  double get value =>
      (_eased(first) * (1 - 0.4 * _eased(next))).clamp(0.0, 1.0);
}

/// The one page transitions theme (motion B2), every platform alike.
const warmPopPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: WarmPopPageTransitionsBuilder(),
    TargetPlatform.iOS: WarmPopPageTransitionsBuilder(),
    TargetPlatform.linux: WarmPopPageTransitionsBuilder(),
    TargetPlatform.macOS: WarmPopPageTransitionsBuilder(),
    TargetPlatform.windows: WarmPopPageTransitionsBuilder(),
    TargetPlatform.fuchsia: WarmPopPageTransitionsBuilder(),
  },
);
