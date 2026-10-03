// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

const containerTransformForwardDuration = Duration(milliseconds: 420);
const containerTransformReverseDuration = Duration(milliseconds: 320);

/// 没有来源卡片时用的短过渡：不然页面会是"闪现"出来的。
const containerTransformPlainDuration = Duration(milliseconds: 220);

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
        return ColoredBox(
          // 缩下去之后后面不能是黑的：先铺一层 App 自己的底色。
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Transform.scale(
            scale: 1 - 0.05 * value,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16 * value),
              child: child,
            ),
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
    // 有来源卡片：从卡片位置长到整屏。
    // 没有来源（比如从设置页打开「关于软件」）：不套这个动效，但也要有过渡。
    transitionDuration: hasSource
        ? containerTransformForwardDuration
        : containerTransformPlainDuration,
    reverseTransitionDuration: hasSource
        ? containerTransformReverseDuration
        : containerTransformPlainDuration,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      // 这个动效只属于「从首页卡片打开一个页面」。
      // 之前不管从哪进来都硬跑一次，还把首页的缩略图当背景画出来 ——
      // 从设置页打开「关于软件」时就露出了主页，明显不对。
      if (!hasSource) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      }
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
              // 收尾这一帧直接交还真页面：否则会从"缩放版"切到真页面，
              // 中间闪一下底下的首页。
              if (raw >= 0.999) return page!;
              final t = Curves.fastOutSlowIn.transform(raw);
              return Stack(
                children: [
                  // 驱动首页那层的"下沉"（首页在另一个 Navigator，只能靠全局值联动）。
                  _SinkDriver(animation: animation),
                  // 背景：**直接模糊活的背景**（BackdropFilter）。
                  // 之前试过「抓首页截图 + 在小图上模糊 + 放大」那套（小米专利的省算力做法），
                  // 但截图不会跟着首页一起下沉，于是截图和真实首页错开，看着是叠影。
                  // 模糊活内容就没这个问题。模糊半径同样从 0 长大，
                  // 所以第一帧和首页完全一致，不会跳变。
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (t > 0.001)
                          BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: 14 * t,
                              sigmaY: 14 * t,
                            ),
                            child: const ColoredBox(color: Color(0x00000000)),
                          ),
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.10 * t),
                        ),
                      ],
                    ),
                  ),
                  // 页面**等比铺满**正在长大的窗口（BoxFit.cover）：
                  //   fill    —— 会压扁；contain —— 长条形卡片两边留白太多；
                  //   cover   —— 既不压扁也不留白，正是参考录屏里的做法。
                  // 窗口本身从控件的位置长到整屏，看起来就是从那张卡片里长出来的。
                  // RepaintBoundary 很关键：窗口每帧都在变，
                  // 没有它，下面这个重页面（比如课表）会被逼着每帧重绘。
                  Positioned.fromRect(
                    rect: rectTween.lerp(t)!,
                    child: ClipRRect(
                      borderRadius: BorderRadius.lerp(
                        startRadius,
                        endRadius,
                        t,
                      )!,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: RepaintBoundary(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: page,
                            ),
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
