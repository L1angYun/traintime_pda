// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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

/// 打开页面时下面那层（首页）缩一点、带点圆角，也就是 iOS / HyperOS 那种"下沉"。
///
/// 首页在另一个 Navigator 里，路由碰不到它，所以用一个全局值让它自己动：
/// 路由的转场驱动这个值，首页用 [ContainerTransformSink] 监听。
final ValueNotifier<double> containerTransformSink = ValueNotifier<double>(0);

/// 包在首页外面，跟着 [containerTransformSink] 缩放。
class ContainerTransformSink extends StatelessWidget {
  const ContainerTransformSink({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: containerTransformSink,
      child: child,
      builder: (context, value, child) {
        if (value <= 0.001) return child!;
        return Transform.scale(
          scale: 1 - 0.05 * value,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18 * value),
            child: child,
          ),
        );
      },
    );
  }
}

/// 把路由动画值同步给 [containerTransformSink]，页面离开时归零。
class _SinkDriver extends StatefulWidget {
  const _SinkDriver({required this.animation});

  final Animation<double> animation;

  @override
  State<_SinkDriver> createState() => _SinkDriverState();
}

class _SinkDriverState extends State<_SinkDriver> {
  void _sync() => containerTransformSink.value = widget.animation.value;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    containerTransformSink.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 直线插值，不要走弧线。
///
/// 之前这里做过"中心弧线"，结果长条形的卡片打开时会明显左右抽动
/// （卡片越长横向偏移越大）。参考里说的非线性是**时间曲线**，不是空间路径。
class ContainerTransformRectTween extends RectTween {
  ContainerTransformRectTween({super.begin, super.end});
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
    // 即使没量到来源矩形也要有动画（退化成从屏幕中下方长出来），
    // 否则一旦量失败就变成"直接出现"，之前就是这么翻车的。
    transitionDuration: containerTransformForwardDuration,
    reverseTransitionDuration: containerTransformReverseDuration,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
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
            begin: hasSource
                ? fromRect
                : Rect.fromCenter(
                    center: Offset(size.width / 2, size.height * 0.62),
                    width: size.width * 0.42,
                    height: size.height * 0.14,
                  ),
            end: Offset.zero & size,
          );
          final startRadius = fromRadius ?? BorderRadius.circular(14);
          final endRadius = BorderRadius.circular(screenRadius);
          return AnimatedBuilder(
            animation: animation,
            // 页面按整屏尺寸构建（第一帧就是），下面只裁不缩。
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
            builder: (context, page) {
              final raw = animation.value;
              // 收尾这一帧直接交还真页面：否则会从"裁剪版"切到真页面，
              // 中间闪一下底下的首页。
              if (raw >= 0.999) return page!;
              final t = Curves.fastOutSlowIn.transform(raw);
              return Stack(
                children: [
                  // 驱动首页那层的"下沉"（首页在另一个 Navigator，只能靠全局值联动）。
                  _SinkDriver(animation: animation),
                  // 打开时把下面那层（首页）虚化并压暗一点，
                  // 就是 iOS / HyperOS 桌面打开应用那个味道。
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 10 * t,
                        sigmaY: 10 * t,
                      ),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.16 * t),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rectTween.lerp(t)!,
                    child: ClipRRect(
                      borderRadius: BorderRadius.lerp(
                        startRadius,
                        endRadius,
                        t,
                      )!,
                      // 等比缩放：整页缩进卡片里再长出来（iOS 那个观感）。
                      // 不要用 BoxFit.fill —— 那会把页面压扁；
                      // 也不要"整屏 + 左上角裁切" —— 那样锚点在左上角，很别扭。
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: size.width,
                            height: size.height,
                            child: page,
                          ),
                        ),
                      ),
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
