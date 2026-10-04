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
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(classTableSheetRadius),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
            blurRadius: 2 * classTableSheetShadowSigma,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(classTableSheetRadius),
        child: sheet,
      ),
    ),
  );
}
