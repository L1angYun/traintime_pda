// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const containerTransformForwardDuration = Duration(milliseconds: 430);
const containerTransformReverseDuration = Duration(milliseconds: 330);
const _surfaceFadeDuration = Duration(milliseconds: 180);

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

bool _containerTransformRunning = false;

/// Runs a source-driven full-screen container transform around [open].
///
/// [open] should start the existing navigation operation and return its pop
/// future. The root overlay remains above split-view navigators, so this does
/// not depend on Hero matching between separate navigators.
Future<void> runContainerTransform(
  BuildContext context, {
  required FutureOr<Object?> Function() open,
  Color? color,
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(14)),
  EdgeInsets sourcePadding = const EdgeInsets.all(4),
}) async {
  if (_containerTransformRunning || !context.mounted) return;

  final overlay = Overlay.of(context, rootOverlay: true);
  final sourceObject = context.findRenderObject();
  final overlayObject = overlay.context.findRenderObject();
  if (sourceObject is! RenderBox ||
      overlayObject is! RenderBox ||
      !sourceObject.hasSize ||
      !overlayObject.hasSize) {
    await Future<Object?>.sync(open);
    return;
  }

  final sourceRect = sourcePadding.deflateRect(Offset.zero & sourceObject.size);
  final start = Rect.fromPoints(
    overlayObject.globalToLocal(sourceObject.localToGlobal(sourceRect.topLeft)),
    overlayObject.globalToLocal(
      sourceObject.localToGlobal(sourceRect.bottomRight),
    ),
  );
  final finish = Offset.zero & overlayObject.size;
  if (start.isEmpty || finish.isEmpty) {
    await Future<Object?>.sync(open);
    return;
  }

  _containerTransformRunning = true;
  final controller = AnimationController(
    vsync: overlay,
    duration: containerTransformForwardDuration + _surfaceFadeDuration,
    reverseDuration: containerTransformReverseDuration,
  );
  final scheme = Theme.of(context).colorScheme;
  final surfaceColor = color ?? scheme.surfaceContainerLow;
  final rectTween = ContainerTransformRectTween(begin: start, end: finish);
  final expansionEnd =
      containerTransformForwardDuration.inMicroseconds /
      (containerTransformForwardDuration + _surfaceFadeDuration).inMicroseconds;
  var inserted = false;
  var routeFuture = Future<Object?>.value();
  final entry = OverlayEntry(
    builder: (_) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final forwardT = Curves.easeOutQuint.transform(
          (controller.value / expansionEnd).clamp(0.0, 1.0),
        );
        final fade = Curves.easeOut.transform(
          ((controller.value - expansionEnd) / (1 - expansionEnd)).clamp(
            0.0,
            1.0,
          ),
        );
        return Positioned.fromRect(
          rect: rectTween.lerp(forwardT)!,
          child: IgnorePointer(
            child: Opacity(
              opacity: 1 - fade,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(surfaceColor, scheme.surface, forwardT),
                  borderRadius: BorderRadius.lerp(
                    borderRadius,
                    BorderRadius.zero,
                    forwardT,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(
                        alpha: 0.18 * (1 - forwardT),
                      ),
                      blurRadius: 10 * (1 - forwardT),
                      offset: Offset(0, 3 * (1 - forwardT)),
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    ),
  );

  try {
    overlay.insert(entry);
    inserted = true;
    routeFuture = Future<Object?>.sync(open);
    await controller.forward();
    await routeFuture;
    if (inserted && entry.mounted) {
      await controller.reverse();
    }
  } catch (_) {
    // Navigation errors must never leave an overlay entry behind.
  } finally {
    if (inserted && entry.mounted) entry.remove();
    controller.dispose();
    _containerTransformRunning = false;
  }
}

/// Fades page content over the final part of the route transition.
class ContainerTransformPageFade extends StatelessWidget {
  const ContainerTransformPageFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return FadeTransition(
      opacity: animation.drive(
        CurveTween(curve: const Interval(0.55, 1, curve: Curves.easeOut)),
      ),
      child: child,
    );
  }
}
