// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const containerTransformForwardDuration = Duration(milliseconds: 430);
const containerTransformReverseDuration = Duration(milliseconds: 300);
// 430 ms expansion followed by 180 ms of surface/content cross-fade.
const containerTransformRouteDuration = Duration(milliseconds: 610);

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

final _transformZoneKey = Object();
_TransformSession? _animationOwner;

bool get isContainerTransformNavigation =>
    (Zone.current[_transformZoneKey] as _TransformSession?)?.closed == false;

class _TransformSession {
  final routeReady = Completer<bool>();
  final finished = Completer<bool>();
  bool closed = false;

  void bind() {
    if (!closed && !routeReady.isCompleted) routeReady.complete(true);
  }

  void finish(bool popped) {
    if (!routeReady.isCompleted) routeReady.complete(false);
    if (!finished.isCompleted) finished.complete(popped);
  }
}

/// Captures the actual destination in the click's zone, including callbacks
/// which discard the navigation Future. Replacement/removal is cancellation,
/// whereas a successful didPop is the only signal to animate back.
class ContainerTransformRoute<T> extends PageRouteBuilder<T> {
  ContainerTransformRoute({
    required super.settings,
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  }) : _session = Zone.current[_transformZoneKey] as _TransformSession? {
    _session?.bind();
  }

  final _TransformSession? _session;
  bool _popping = false;

  @override
  bool didPop(T? result) {
    _popping = true;
    final popped = super.didPop(result);
    _popping = false;
    if (popped) _session?.finish(true);
    return popped;
  }

  @override
  void didComplete(T? result) {
    super.didComplete(result);
    if (!_popping) _session?.finish(false);
  }

  @override
  void dispose() {
    _session?.finish(false);
    super.dispose();
  }
}

/// Source-driven transform; route lifecycle, never callback completion,
/// decides whether to shrink. The root overlay also covers split navigators.
Future<void> runContainerTransform(
  BuildContext context, {
  required FutureOr<Object?> Function() open,
  Color? color,
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(14)),
  EdgeInsets sourcePadding = const EdgeInsets.all(4),
}) async {
  if (_animationOwner != null || !context.mounted) return;
  final session = _TransformSession();
  _animationOwner = session;
  AnimationController? controller;
  OverlayEntry? entry;
  var inserted = false;
  var reversing = false;

  void removeEntry() {
    if (inserted) {
      entry!.remove();
      inserted = false;
    }
  }

  try {
    final overlay = Overlay.of(context, rootOverlay: true);
    final sourceObject = context.findRenderObject();
    final overlayObject = overlay.context.findRenderObject();
    final scheme = Theme.of(context).colorScheme;
    final pageColor = Theme.of(context).scaffoldBackgroundColor;
    // Attach error handling immediately, even when a callback returns a
    // navigation Future that won't complete until long after expansion.
    unawaited(
      runZoned(
        () => Future<Object?>.sync(open),
        zoneValues: {_transformZoneKey: session},
      ).then<void>(
        (_) {
          if (!session.routeReady.isCompleted) session.finish(false);
        },
        onError: (Object error, StackTrace stack) {
          session.finish(false);
        },
      ),
    );
    if (!await session.routeReady.future || !context.mounted) return;

    if (sourceObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !sourceObject.hasSize ||
        !overlayObject.hasSize) {
      return;
    }

    Rect sourceBounds() {
      final rect = sourcePadding.deflateRect(Offset.zero & sourceObject.size);
      return Rect.fromPoints(
        overlayObject.globalToLocal(sourceObject.localToGlobal(rect.topLeft)),
        overlayObject.globalToLocal(
          sourceObject.localToGlobal(rect.bottomRight),
        ),
      );
    }

    final start = sourceBounds();
    final finish = Offset.zero & overlayObject.size;
    if (start.isEmpty || finish.isEmpty) return;
    final animation = AnimationController(
      vsync: overlay,
      duration: containerTransformRouteDuration,
      reverseDuration: containerTransformReverseDuration,
    );
    controller = animation;
    final surfaceColor = color ?? scheme.surfaceContainerLow;
    var rectTween = ContainerTransformRectTween(begin: start, end: finish);
    final expansionEnd =
        containerTransformForwardDuration.inMicroseconds /
        containerTransformRouteDuration.inMicroseconds;
    entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final geometry = reversing
              ? Curves.easeInCubic.transform(animation.value)
              : Curves.easeOutQuint.transform(
                  (animation.value / expansionEnd).clamp(0.0, 1.0),
                );
          final fade = reversing
              ? ((animation.value - 0.85) / 0.15).clamp(0.0, 1.0)
              : Curves.easeOut.transform(
                  ((animation.value - expansionEnd) / (1 - expansionEnd)).clamp(
                    0.0,
                    1.0,
                  ),
                );
          return Positioned.fromRect(
            rect: rectTween.lerp(geometry)!,
            child: AbsorbPointer(
              child: Opacity(
                opacity: 1 - fade,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(surfaceColor, pageColor, geometry),
                    borderRadius: BorderRadius.lerp(
                      borderRadius,
                      BorderRadius.zero,
                      geometry,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(
                          alpha: 0.18 * (1 - geometry),
                        ),
                        blurRadius: 10 * (1 - geometry),
                        offset: Offset(0, 3 * (1 - geometry)),
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
    overlay.insert(entry);
    inserted = true;
    // A pop, replacement or failed navigation during expansion cancels it
    // promptly, without keeping a surface over the new page.
    final expanded = await Future.any<bool>([
      animation.forward().orCancel.then((_) => true),
      session.finished.future.then((_) => false),
    ]);
    if (!expanded) return;
    removeEntry();
    if (identical(_animationOwner, session)) _animationOwner = null;

    final popped = await session.finished.future;
    if (!popped ||
        !context.mounted ||
        !overlay.mounted ||
        !sourceObject.attached ||
        _animationOwner != null) {
      return;
    }
    _animationOwner = session;
    rectTween = ContainerTransformRectTween(begin: sourceBounds(), end: finish);
    reversing = true;
    overlay.insert(entry);
    inserted = true;
    await animation.reverse().orCancel;
  } catch (_) {
    // Navigation/layout/animation failures must never strand the root overlay.
  } finally {
    session.closed = true;
    removeEntry();
    entry?.dispose();
    controller?.dispose();
    if (identical(_animationOwner, session)) _animationOwner = null;
  }
}

/// Fades content only once the container has reached its full-screen bounds.
class ContainerTransformPageFade extends StatelessWidget {
  const ContainerTransformPageFade({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return FadeTransition(
      opacity: animation.drive(
        CurveTween(curve: const Interval(0.70, 1, curve: Curves.easeOut)),
      ),
      child: child,
    );
  }
}
