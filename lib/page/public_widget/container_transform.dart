// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
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

/// 背景模糊：照小米那份专利来（CN121599866A，申请日 2024-08-26）。
///
/// 专利的做法是三步：把图**降采样** → 在**小图**上做高斯模糊 → 再**升采样**回原尺寸。
/// 关键在于模糊的运算量只跟小图的像素数有关，所以极便宜；
/// 我们这边就是：跳转前抓一张 1/8 的首页小图，转场里对小图做 ImageFilter.blur，
/// 再交给 RawImage 放大铺满 —— 放大这一步顺带把小图的模糊一起放大，
/// 观感就是全屏高斯模糊，而每帧只是「一张小图 + 一次小范围模糊」。
/// （全屏 BackdropFilter 是每帧重新采样整个背景，课表那种重页面直接掉帧。）
///
/// 降采样比例和模糊半径是配着来的：缩得越狠，小图上的 sigma 就该越小。
final GlobalKey containerTransformBackgroundKey = GlobalKey();
const double containerTransformThumbScale = 0.12;
ui.Image? _backgroundThumb;

/// 跳转前调用：抓一张首页的小图。失败就静静放弃，退回纯压暗。
Future<void> captureContainerTransformBackground() async {
  final boundary =
      containerTransformBackgroundKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return;
  try {
    final image = await boundary.toImage(
      pixelRatio: containerTransformThumbScale,
    );
    _backgroundThumb?.dispose();
    _backgroundThumb = image;
  } catch (_) {
    // 抓不到就算了，别把跳转搞挂。
  }
}

/// 打开页面时下面那层（首页）缩一点、带点圆角，也就是 iOS / HyperOS 那种"下沉"。
///
/// 首页在另一个 Navigator 里，路由碰不到它，所以用一个全局值让它自己动：
/// 路由的转场驱动这个值，首页用 [ContainerTransformSink] 监听。
final ValueNotifier<double> containerTransformSink = ValueNotifier<double>(0);

/// 包在首页外面：跟着 [containerTransformSink] 缩放，
/// 并且在首页画完第一帧后**提前**把背景缩略图抓好 ——
/// 这样点卡片时图已经在了，不会出现"动画开始后图才啪一下出现"的断裂感。
class ContainerTransformSink extends StatefulWidget {
  const ContainerTransformSink({super.key, required this.child});

  final Widget child;

  @override
  State<ContainerTransformSink> createState() => _ContainerTransformSinkState();
}

class _ContainerTransformSinkState extends State<ContainerTransformSink> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(captureContainerTransformBackground());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: containerTransformSink,
      child: widget.child,
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
                  // 背景：小图 + 小图上的高斯模糊（专利那三步的后两步），
                  // 再压一层暗。抓不到小图时就是纯压暗，不会报错。
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_backgroundThumb != null)
                          // 模糊半径**跟着动画一起长大**（0 → 满）：
                          // 恒定 sigma 会一开场就糊满，看着是「啪」的一下；
                          // 从 0 开始长才是连续的糊起来。
                          // 同时小图本身也淡入 —— t 很小时透出来的是真实首页，
                          // 所以第一帧和首页完全一样，不会有任何跳变。
                          Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: ImageFiltered(
                              // 小图上的 sigma；后面要放大 8 倍左右，
                              // 视觉上相当于全屏图上十几的 sigma。
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 1.8 * t,
                                sigmaY: 1.8 * t,
                              ),
                              child: RawImage(
                                image: _backgroundThumb,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
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
