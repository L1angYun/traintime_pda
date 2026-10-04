// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermeter/page/classtable/class_table_view/class_table_frame_style.dart';

void main() {
  tearDown(() {
    ClassTableFrameStyleConfig.frameStyle = ClassTableFrameStyle.borderless;
  });

  testWidgets('borderless returns the original sheet without a wrapper', (
    tester,
  ) async {
    const sheet = SizedBox(width: 100, height: 100);
    ClassTableFrameStyleConfig.frameStyle = ClassTableFrameStyle.borderless;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              identical(applyClassTableFrame(context, sheet), sheet),
              isTrue,
            );
            return sheet;
          },
        ),
      ),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'card shadow stays outside the transparent sheet ($brightness)',
      (tester) async {
        ClassTableFrameStyleConfig.frameStyle = ClassTableFrameStyle.card;
        const sheetKey = ValueKey('transparent-sheet');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Center(
              child: SizedBox(
                width: 116,
                height: 116,
                child: Builder(
                  builder: (context) => applyClassTableFrame(
                    context,
                    const SizedBox.expand(key: sheetKey),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byKey(sheetKey)), const Size(100, 100));
        final clip = tester.widget<ClipRRect>(
          find.ancestor(
            of: find.byKey(sheetKey),
            matching: find.byType(ClipRRect),
          ),
        );
        expect(clip.borderRadius, BorderRadius.circular(14));
        final paint = tester.widget<CustomPaint>(
          find
              .ancestor(
                of: find.byKey(sheetKey),
                matching: find.byType(CustomPaint),
              )
              .first,
        );

        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(32, 32);
          paint.painter!.paint(canvas, const Size(100, 100));
          final picture = recorder.endRecording();
          final image = await picture.toImage(164, 164);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int alphaAt(int x, int y) => bytes.getUint8((y * 164 + x) * 4 + 3);

          // Check every interior pixel away from the antialiased rounded edge,
          // including the area near the perimeter where BoxShadow leaked in.
          final interior = RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 100, 100),
            const Radius.circular(14),
          ).deflate(1);
          for (var y = 0; y < 100; y++) {
            for (var x = 0; x < 100; x++) {
              if (interior.contains(Offset(x + 0.5, y + 0.5))) {
                expect(alphaAt(x + 32, y + 32), 0, reason: 'interior ($x, $y)');
              }
            }
          }
          expect(
            alphaAt(31, 82),
            greaterThan(0),
            reason: 'left exterior shadow',
          );
          expect(
            alphaAt(132, 82),
            greaterThan(0),
            reason: 'right exterior shadow',
          );
          expect(
            alphaAt(82, 31),
            greaterThan(0),
            reason: 'top exterior shadow',
          );
          expect(
            alphaAt(82, 132),
            greaterThan(0),
            reason: 'bottom exterior shadow',
          );
          image.dispose();
          picture.dispose();
        });
      },
    );
  }
}
