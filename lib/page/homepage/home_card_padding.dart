// Copyright 2023-2025 BenderBlog Rodriguez and contributors
// Copyright 2025 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

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
    final scheme = Theme.of(context).colorScheme;
    final cardColor = switch (type) {
      HomeCardType.warning => scheme.errorContainer,
      HomeCardType.filled => scheme.surfaceContainerHigh,
      HomeCardType.plain => scheme.surfaceContainerLow,
    };
    return Builder(
      builder: (sourceContext) => OutlinedButton(
        //elevation: 0,
        clipBehavior: Clip.antiAlias,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
          ),
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
        onPressed: onPressed == null || !enableContainerTransform
            ? onPressed
            : () => unawaited(
                runContainerTransform(
                  sourceContext,
                  color: cardColor,
                  open: () async {
                    await onPressed();
                    return null;
                  },
                ),
              ),
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
