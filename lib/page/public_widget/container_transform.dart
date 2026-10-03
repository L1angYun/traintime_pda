// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const containerTransformForwardDuration = Duration(milliseconds: 430);
const containerTransformReverseDuration = Duration(milliseconds: 330);

/// A small center arc keeps the expanding container from feeling mechanical.
class ContainerTransformRectTween extends RectTween {
  ContainerTransformRectTween({super.begin, super.end});

  @override
  Rect? lerp(double t) {
    final start = begin;
    final finish = end;
    if (start == null || finish == null) return super.lerp(t);

    final startCenter = start.center;
    final endCenter = finish.center;
    final delta = endCenter - startCenter;
    final distance = delta.distance;
    final normal = distance == 0
        ? Offset.zero
        : Offset(-delta.dy / distance, delta.dx / distance);
    final control =
        Offset.lerp(startCenter, endCenter, 0.5)! +
        normal * math.min(distance * 0.12, 72.0);
    final first = Offset.lerp(startCenter, control, t)!;
    final center = Offset.lerp(first, Offset.lerp(control, endCenter, t)!, t)!;
    final size = Size.lerp(start.size, finish.size, t)!;
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }
}

RectTween containerTransformRectTween(Rect? begin, Rect? end) =>
    ContainerTransformRectTween(begin: begin, end: end);

/// The shuttle is intentionally a static surface rather than a live page/card.
/// This avoids ticking animations and scrollables in the overlay flight layer.
Widget containerTransformShuttleBuilder(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = animation.value.clamp(0.0, 1.0);
      final scheme = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(scheme.surfaceContainerLow, scheme.surface, t),
          borderRadius: BorderRadius.lerp(
            BorderRadius.circular(14),
            BorderRadius.zero,
            t,
          ),
          boxShadow: [
            BoxShadow.lerp(
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              const BoxShadow(color: Colors.transparent),
              t,
            )!,
          ],
        ),
      );
    },
  );
}

/// Fades page content after the expanding surface has done most of its work.
class ContainerTransformPageFade extends StatelessWidget {
  const ContainerTransformPageFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.55, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0, 0.45, curve: Curves.easeOut),
    );
    return FadeTransition(opacity: curved, child: child);
  }
}

Hero containerTransformHero({required Object tag, required Widget child}) {
  return Hero(
    tag: tag,
    createRectTween: containerTransformRectTween,
    flightShuttleBuilder: containerTransformShuttleBuilder,
    child: child,
  );
}

Widget containerTransformTarget({required Object tag, required Widget child}) {
  return containerTransformHero(tag: tag, child: child);
}

Widget containerTransformSource({required Object tag, required Widget child}) {
  return containerTransformHero(tag: tag, child: child);
}
