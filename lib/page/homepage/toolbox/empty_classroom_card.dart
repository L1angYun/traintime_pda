// Copyright 2023-2025 BenderBlog Rodriguez and contributors
// Copyright 2025 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:watermeter/page/homepage/home_card_padding.dart';
import 'package:watermeter/page/public_widget/context_extension.dart';
import 'package:watermeter/page/public_widget/toast.dart';
import 'package:watermeter/repository/ids_session/ids_session.dart';
import 'package:watermeter/routing/routes.dart';

const _emptyClassroomHeaderHeroTag = 'empty-classroom-header';

class EmptyClassroomCard extends StatelessWidget {
  const EmptyClassroomCard({super.key});

  @override
  Widget build(BuildContext context) {
    Future<void> onPressed() async {
      if (offline) {
        showToast(
          context: context,
          msg: FlutterI18n.translate(context, "homepage.offline_mode"),
        );
      } else {
        context.pushReplacementNamed(Routes.emptyClassroom);
      }
    }

    return Hero(
      tag: _emptyClassroomHeaderHeroTag,
      child:
          [
                Icon(
                  MingCuteIcons.mgc_building_2_line,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  FlutterI18n.translate(
                    context,
                    "homepage.toolbox.empty_classroom",
                  ),
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ]
              .toColumn(mainAxisAlignment: MainAxisAlignment.center)
              .alignment(Alignment.center),
    ).withHomeCardStyle(context, onPressed: onPressed);
  }
}
