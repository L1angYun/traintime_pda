// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

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

/// 背景模糊的省算力做法：**多级降采样缩略图叠加**（Kawase 那一类）。
///
/// 单张缩略图放大也能糊，但过渡生硬、容易发块；取 2~4 个尺度的缩略图叠起来，
/// 粗的几张补上细的那张缺的柔和过渡，观感更接近高斯模糊 ——
/// 代价依然只是每帧画几张位图，不像全屏 BackdropFilter 那样每帧重新采样背景
/// （那个在课表这种重页面上直接掉帧）。
final GlobalKey containerTransformBackgroundKey = GlobalKey();

/// 从粗到细的几档采样比例，画的时候从细往粗叠。
const List<double> containerTransformThumbScales = [0.35, 0.18, 0.09];
final List<ui.Image?> _backgroundThumbs = List.filled(
  containerTransformThumbScales.length,
  null,
);

/// 跳转前调用：抓几档首页的小图。失败就静静放弃，退回纯压暗。
Future<void> captureContainerTransformBackground() async {
  final boundary =
      containerTransformBackgroundKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return;
  for (var i = 0; i < containerTransformThumbScales.length; i++) {
    try {
      final image = await boundary.toImage(
        pixelRatio: containerTransformThumbScales[i],
      );
      _backgroundThumbs[i]?.dispose();
      _backgroundThumbs[i] = image;
    } catch (_) {
      // 抓不到就算了，别把跳转搞挂。
    }
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
            scale: 1 - 0.03 * value,
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
                  // 背景：先画那张降采样缩略图（放大后自然发糊），再压一层暗。
                  // 抓不到缩略图时就是纯压暗，不会报错。
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 从细到粗叠：细的留住一点结构，粗的把过渡糊匀。
                        for (var i = 0; i < _backgroundThumbs.length; i++)
                          if (_backgroundThumbs[i] != null)
                            Opacity(
                              opacity: i == 0 ? 1.0 : 0.55,
                              child: RawImage(
                                image: _backgroundThumbs[i],
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.16 * t),
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
