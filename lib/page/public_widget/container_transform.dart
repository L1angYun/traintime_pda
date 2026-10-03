// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const containerTransformForwardDuration = Duration(milliseconds: 420);
const containerTransformReverseDuration = Duration(milliseconds: 320);

// HomePage uses BasedSplitView's defaults: left minimum 364, divider 1,
// right minimum 364. It switches to two columns only above their sum.
const containerTransformSplitBreakpoint = 364.0 + 1.0 + 364.0;

/// One-shot handoff from a home card to Routes.resolveRoute.
/// Clear after the navigation callback too, in case navigation was skipped.
class ContainerTransformSource {
  ContainerTransformSource({required this.fromRect, required this.fromRadius});

  final Rect fromRect;
  final BorderRadius fromRadius;
  static ContainerTransformSource? pending;

  static ContainerTransformSource? consume() {
    final source = pending;
    pending = null;
    return source;
  }
}

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

PageRouteBuilder<T> containerTransformRoute<T>({
  required WidgetBuilder builder,
  Rect? fromRect,
  BorderRadius? fromRadius,
  RouteSettings? settings,
}) {
  final hasSource = fromRect != null && !fromRect.isEmpty;
  return PageRouteBuilder<T>(
    settings: settings,
    // Keeping the source route visible also prevents its Cupertino transition
    // from reacting to this route's secondary animation. No barrier dims it.
    opaque: false,
    barrierColor: null,
    transitionDuration: hasSource
        ? containerTransformForwardDuration
        : Duration.zero,
    reverseTransitionDuration: hasSource
        ? containerTransformReverseDuration
        : Duration.zero,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      if (!hasSource) return child;
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.width > containerTransformSplitBreakpoint) return child;
          final corners = MediaQuery.displayCornerRadiiOf(context);
          final screenRadius = [
            corners?.topLeft.x ?? 0.0,
            corners?.topLeft.y ?? 0.0,
            corners?.topRight.x ?? 0.0,
            corners?.topRight.y ?? 0.0,
            corners?.bottomLeft.x ?? 0.0,
            corners?.bottomLeft.y ?? 0.0,
            corners?.bottomRight.x ?? 0.0,
            corners?.bottomRight.y ?? 0.0,
          ].reduce(math.max);
          final rectTween = ContainerTransformRectTween(
            begin: fromRect,
            end: Offset.zero & size,
          );
          final endRadius = BorderRadius.circular(screenRadius);
          return AnimatedBuilder(
            animation: animation,
            // Layout is always full-screen, including the very first frame.
            // FittedBox only maps that real page into the growing rectangle;
            // neither the page nor the source is faded or re-laid-out per tick.
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
            builder: (context, page) {
              final t = Curves.fastOutSlowIn.transform(animation.value);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rectTween.lerp(t)!,
                    child: ClipRRect(
                      borderRadius: BorderRadius.lerp(
                        fromRadius ?? BorderRadius.circular(16),
                        endRadius,
                        t,
                      )!,
                      child: FittedBox(fit: BoxFit.fill, child: page),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}
