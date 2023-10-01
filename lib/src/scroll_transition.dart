import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'animated_effect.dart';
import 'extensions.dart';
import 'scroll_phase.dart';

class ScrollTransitionEvent {
  final ScrollPhase phase;

  /// The current progress an element's phase is going through.
  /// If [phase] is identity this value is 1.
  /// If [phase] is topLeading, it goes from 0 towards 1 as it leaves the
  /// screen.
  /// If [phase] is bottomTrailing, it goes from 0 towards 1 as it enters the
  /// screen.
  final double phaseOffsetFraction;

  /// The current progress an element is going through the scrolling viewport.
  /// If the item is near the center of the scroll view, the value tends towards
  /// 0.
  /// As the item moves towards the ceiling of the scroll view, the value tends
  /// towards 1. It clamps to 1 when the item is fully out of the scroll view.
  /// As the item moves towards the floor of the scroll view, the value tends
  /// towards -1. It clamps to -1 when the item is fully out of the scroll view.
  final double screenOffsetFraction;

  ScrollTransitionEvent({
    required this.phase,
    required this.phaseOffsetFraction,
    required this.screenOffsetFraction,
  });
}

/// A function that builds a widget based on the current phase of the scroll
/// animation.
typedef ScrollTransitionBuilder = Widget Function(
  BuildContext context,
  Widget widget,
  ScrollTransitionEvent event,
);

extension ScrollTransitionExt on Widget {
  Widget scrollTransition(int index, ScrollTransitionBuilder builder) {
    return ScrollTransition(
      index: index,
      builder: builder,
      child: this,
    );
  }
}

/// A widget that applies a set of effects to its child based on the current
/// phase and position of the scroll position of the parent scrollable widget.
class ScrollTransition extends StatefulWidget {
  /// The index of the scroll animation in the parent scrollable widget.
  /// TODO
  @Deprecated('Delete')
  final int index;

  /// A function that builds a widget based on the current phase of the scroll
  /// animation.
  final ScrollTransitionBuilder? builder;

  /// The child widget to apply the effects to.
  final Widget child;

  /// Creates a widget that applies a set of effects to its child based on the
  /// current phase and position of the scroll position of the parent scrollable
  /// widget.
  const ScrollTransition({
    super.key,
    required this.child,
    this.builder,
    this.index = 0,
  });

  @override
  State<ScrollTransition> createState() => _ScrollTransitionState();
}

class _ScrollTransitionState extends State<ScrollTransition> {
  /// The parent scrollable widget.
  ScrollableState? scrollable;

  ScrollPosition? scrollPosition;

  /// The current phase of the scroll animation.
  ScrollPhase phase = ScrollPhase.identity;

  /// The current animation value indicating the progress of the scroll
  /// animation through its phase in the parent viewport.
  double phaseOffsetFraction = 0;

  double screenOffsetFraction = 0;

  bool isFirstFrame = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      isFirstFrame = false;
      updateCurrentState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scrollable = Scrollable.maybeOf(context);
    if (scrollPosition != scrollable?.position) {
      scrollPosition?.removeListener(onScrollChanged);
      scrollPosition = scrollable?.position;
      scrollPosition?.addListener(onScrollChanged);
    }
  }

  @override
  void dispose() {
    scrollPosition?.removeListener(onScrollChanged);
    scrollPosition = null;
    scrollable = null;
    super.dispose();
  }

  /// Calculates the current phase of the scroll animation.
  /// Returns a record of the current phase and it's associated progress
  /// through the viewport as a value between 0 and 1.
  ({
    ScrollPhase phase,
    double phaseOffsetFraction,
    double screenOffsetFraction,
  }) calculatePhase() {
    if (scrollable case var scrollable?) {
      final viewPort = scrollable.context.globalPaintBounds;
      final paintBounds = context.globalPaintBounds;

      if (paintBounds != null && viewPort != null) {
        final bool isVertical = scrollPosition!.axis == Axis.vertical;
        final double paintBoundsStart =
            isVertical ? paintBounds.top : paintBounds.left;
        final double paintBoundsEnd =
            isVertical ? paintBounds.bottom : paintBounds.right;
        final double paintBoundsSize =
            isVertical ? paintBounds.height : paintBounds.width;

        final double viewPortStart = isVertical ? viewPort.top : viewPort.left;
        final double viewPortEnd =
            isVertical ? viewPort.bottom : viewPort.right;

        final bool doesFit = isVertical
            ? viewPort.top <= paintBounds.top &&
                viewPort.bottom >= paintBounds.bottom
            : viewPort.left <= paintBounds.left &&
                viewPort.right >= paintBounds.right;

        double screenOffsetFraction = isVertical
            ? (viewPort.center.dy - paintBounds.center.dy) / viewPort.height
            : (viewPort.center.dx - paintBounds.center.dx) / viewPort.width;
        screenOffsetFraction *= 2;

        if (doesFit) {
          return (
            phase: ScrollPhase.identity,
            phaseOffsetFraction: 1.0,
            screenOffsetFraction: screenOffsetFraction
          );
        } else if (viewPortStart > paintBoundsStart) {
          // Cutting at the top.
          double value = (viewPortStart - paintBoundsStart) / paintBoundsSize;
          value = value.clamp(0, 1);
          if (scrollPosition!.atStart) value = 0;
          return (
            phase: ScrollPhase.topLeading,
            phaseOffsetFraction: value,
            screenOffsetFraction: screenOffsetFraction,
          );
        } else if (viewPortEnd < paintBoundsEnd) {
          double value = (paintBoundsEnd - viewPortEnd) / paintBoundsSize;
          value = value.clamp(0, 1);
          if (scrollPosition!.atEnd) value = 0;
          return (
            phase: ScrollPhase.bottomTrailing,
            phaseOffsetFraction: value,
            screenOffsetFraction: screenOffsetFraction,
          );
        }
      }
    }
    return (
      phase: ScrollPhase.identity,
      phaseOffsetFraction: 1,
      screenOffsetFraction: screenOffsetFraction,
    );
  }

  /// Calculates the current phase of the scroll animation and its associated
  /// progress through the viewport as a value between 0 and 1.
  ///
  /// If the phase or value has changed, the current phase and value are updated
  /// and the effects are recalculated.
  ///
  /// If the [onChanged] callback is provided, it is called if the phase or
  /// value has changed.
  void updateCurrentState() {
    final (:phase, :phaseOffsetFraction, :screenOffsetFraction) =
        calculatePhase();
    this.phase = phase;
    this.phaseOffsetFraction = phaseOffsetFraction;
    this.screenOffsetFraction = screenOffsetFraction;

    if (mounted) setState(() {});
  }

  /// Called when the parent scrollable widget sends a notification that the
  /// scroll position has changed.
  void onScrollChanged() => updateCurrentState();

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (scrollable != null) {
      child = widget.builder?.call(
              context,
              widget.child,
              ScrollTransitionEvent(
                phase: phase,
                phaseOffsetFraction: phaseOffsetFraction,
                screenOffsetFraction: screenOffsetFraction,
              )) ??
          widget.child;
    } else {
      child = widget.child;
    }

    final visible = !isFirstFrame || scrollable == null;

    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: EffectAnimationValue(
        value: phaseOffsetFraction,
        isTransition: true,
        child: child,
      ),
    );
  }
}
