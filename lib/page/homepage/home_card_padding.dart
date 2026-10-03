// Copyright 2023-2025 BenderBlog Rodriguez and contributors
// Copyright 2025 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:based_split_view/based_split_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watermeter/page/public_widget/container_transform.dart';
import 'package:styled_widget/styled_widget.dart';

enum HomeCardType { plain, filled, warning }

extension HomeCardPadding on Widget {
  Widget withHomeCardStyle(
    BuildContext context, {
    HomeCardType type = HomeCardType.plain,
    FutureOr<void> Function()? onPressed,
    bool enableContainerTransform = true,
  }) {
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Builder(
      builder: (sourceContext) => OutlinedButton(
        //elevation: 0,
        clipBehavior: Clip.antiAlias,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(cardShape),
          iconColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.primary,
          ),
          iconSize: WidgetStateProperty.all(20),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            final colorScheme = Theme.of(context).colorScheme;
            if (type == HomeCardType.warning) {
              return colorScheme.errorContainer;
            }
            if (type == HomeCardType.filled) {
              return colorScheme.surfaceContainerHigh;
            }
            return colorScheme.surfaceContainerLow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final colorScheme = Theme.of(context).colorScheme;
            if (type == HomeCardType.warning) {
              return colorScheme.onErrorContainer;
            }
            if (type == HomeCardType.filled) {
              return colorScheme.onSurfaceVariant;
            }
            return colorScheme.onSurfaceVariant;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final colorScheme = Theme.of(context).colorScheme;
            if (type == HomeCardType.warning) {
              return BorderSide(color: colorScheme.error);
            }
            if (type == HomeCardType.filled) {
              return BorderSide.none;
            }
            final hoverColor = colorScheme.primary.withValues(alpha: 0.6);
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return BorderSide(color: hoverColor);
            }
            return BorderSide(color: colorScheme.surfaceContainerHighest);
          }),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                ContainerTransformSource.pending = null;
                // Use the whole BasedSplitView's available width, not the
                // left card column's width (364 in the default two-column UI).
                final splitContext = sourceContext
                    .findAncestorStateOfType<State<BasedSplitView>>()
                    ?.context;
                final splitBox = splitContext?.findRenderObject();
                final availableWidth = splitBox is RenderBox && splitBox.hasSize
                    ? splitBox.size.width
                    : MediaQuery.sizeOf(sourceContext).width;
                if (enableContainerTransform &&
                    availableWidth <= containerTransformSplitBreakpoint) {
                  final sourceBox = sourceContext.findRenderObject();
                  final navigatorBox = Navigator.of(
                    sourceContext,
                  ).context.findRenderObject();
                  if (sourceBox is RenderBox &&
                      navigatorBox is RenderBox &&
                      sourceBox.hasSize &&
                      navigatorBox.hasSize) {
                    // The Builder includes the card's outer four-pixel padding.
                    final bounds = const EdgeInsets.all(
                      4,
                    ).deflateRect(Offset.zero & sourceBox.size);
                    final rect = Rect.fromPoints(
                      sourceBox.localToGlobal(
                        bounds.topLeft,
                        ancestor: navigatorBox,
                      ),
                      sourceBox.localToGlobal(
                        bounds.bottomRight,
                        ancestor: navigatorBox,
                      ),
                    );
                    if (!rect.isEmpty) {
                      ContainerTransformSource.pending =
                          ContainerTransformSource(
                            fromRect: rect,
                            fromRadius: cardShape.borderRadius.resolve(
                              Directionality.of(sourceContext),
                            ),
                          );
                    }
                  }
                }
                try {
                  // Named navigation resolves the route synchronously, even
                  // when the callback returns a Future that completes on pop.
                  onPressed();
                } finally {
                  ContainerTransformSource.pending = null;
                }
              },
        child: DefaultTextStyle(
          style: TextStyle(
            color: type == HomeCardType.warning
                ? Theme.of(context).colorScheme.onErrorContainer
                : Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: this,
        ),
      ).padding(all: 4),
    );
  }
}
