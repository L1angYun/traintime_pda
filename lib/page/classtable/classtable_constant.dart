// Copyright 2023-2025 BenderBlog Rodriguez and contributors
// Copyright 2025 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0 OR Apache-2.0

// These are some constant used in the class table.

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

/// The width of the button.
const weekButtonWidth = 74.0;

/// The horizontal padding of the button.
const weekButtonHorizontalPadding = 2.0;

/// The width ratio for the week column.
const double leftRow = 26;

/// The height of the top row.
const topRowHeightBig = 96.0;
const topRowHeightSmall = 50.0;

/// Change page time in milliseconds.
const changePageTime = 200;

/// The height of the middle row.
const midRowHeight = 54.0;

/// The gap kept between the classtable sheet and the edges of the display.
///
/// The sheet gets the window insets of the system bars as well, this is only
/// the breathing room on top of them.
const double classTableSheetMargin = 8.0;

/// The least amount of room kept below the sheet.
///
/// Devices which do not report the corners of their display would otherwise
/// only get the (possibly zero) navigation bar inset.
const double classTableMinimumBottomInset = 16.0;

/// The corner radius of the classtable sheet.
///
/// The sheet no longer reaches the edges of the display, so its own corners
/// are rounded as well.
const double classTableSheetRadius = 14.0;

/// The largest blur which can be applied to a user defined background image.
const double maxClassTableBackgroundBlur = 30.0;

String getWeekString(BuildContext context, int index) {
  List<String> weekList = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  return FlutterI18n.translate(context, "weekday.${weekList[index]}");
}
