// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import 'package:watermeter/page/classtable/classtable_constant.dart';
import 'package:watermeter/repository/preference.dart' as preference;

enum ClassTableFrameStyle { borderless, card }

class ClassTableFrameStyleConfig {
  static ClassTableFrameStyle frameStyle = ClassTableFrameStyle.borderless;

  static void loadFromPreference() {
    final stored = preference.getString(
      preference.Preference.classTableFrameStyle,
    );
    frameStyle = ClassTableFrameStyle.values.firstWhere(
      (style) => style.name == stored,
      orElse: () => ClassTableFrameStyle.borderless,
    );
  }

  static Future<void> saveToPreference() async {
    await preference.setString(
      preference.Preference.classTableFrameStyle,
      frameStyle.name,
    );
  }
}

/// Returns the original sheet unchanged when the frame is disabled.
Widget applyClassTableFrame(BuildContext context, Widget sheet) {
  if (ClassTableFrameStyleConfig.frameStyle != ClassTableFrameStyle.card) {
    return sheet;
  }
  return Padding(
    padding: const EdgeInsets.all(classTableSheetMargin),
    child: CustomPaint(
      painter: _ClassTableFrameShadowPainter(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(classTableSheetRadius),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(classTableSheetRadius),
          child: sheet,
        ),
      ),
    ),
  );
}

/// The sheet is transparent, so even a shadow behind ClipRRect would show
/// through it. Exclude its rounded interior before painting the blurred shell,
/// following the original _SheetShadowPainter approach.
class _ClassTableFrameShadowPainter extends CustomPainter {
  const _ClassTableFrameShadowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      box,
      const Radius.circular(classTableSheetRadius),
    );

    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(box.inflate(classTableSheetShadowSigma * 4)),
        Path()..addRRect(rrect),
      ),
      doAntiAlias: true,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          classTableSheetShadowSigma,
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClassTableFrameShadowPainter oldDelegate) =>
      oldDelegate.color != color;
}
