// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'package:material_ui/material_ui.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:watermeter/page/classtable/class_table_view/class_table_frame_style.dart';
import 'package:watermeter/page/public_widget/setting/setting_choice_control.dart';
import 'package:watermeter/page/public_widget/setting/setting_section_scaffold.dart';
import 'package:watermeter/page/public_widget/setting/setting_segmented_list.dart';

class ClassTableFrameStyleSettings extends StatelessWidget {
  const ClassTableFrameStyleSettings({super.key, required this.onChanged});

  final VoidCallback onChanged;

  Future<void> _onStyleChanged(ClassTableFrameStyle style) async {
    ClassTableFrameStyleConfig.frameStyle = style;
    onChanged();
    await ClassTableFrameStyleConfig.saveToPreference();
  }

  @override
  Widget build(BuildContext context) {
    return SectionSettingScaffold(
      icon: Icons.crop_square,
      title: FlutterI18n.translate(
        context,
        'setting.class_table_style_page.frame_style',
      ),
      items: SettingSegmentedList(
        items: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SettingChoiceControl<ClassTableFrameStyle>(
              value: ClassTableFrameStyleConfig.frameStyle,
              options: [
                SettingChoiceOption(
                  value: ClassTableFrameStyle.card,
                  label: FlutterI18n.translate(
                    context,
                    'setting.class_table_style_page.frame_card',
                  ),
                ),
                SettingChoiceOption(
                  value: ClassTableFrameStyle.borderless,
                  label: FlutterI18n.translate(
                    context,
                    'setting.class_table_style_page.frame_borderless',
                  ),
                ),
              ],
              onChanged: _onStyleChanged,
            ),
          ),
        ],
      ),
    );
  }
}
