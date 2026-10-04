// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

import 'package:material_ui/material_ui.dart';

import 'package:watermeter/generated/translations.g.dart';
import 'package:watermeter/page/public_widget/setting/setting_section_scaffold.dart';
import 'package:watermeter/page/public_widget/setting/setting_segmented_list.dart';
import 'package:watermeter/repository/notification/course_live_update_service.dart';

class NotificationLiveUpdateSettings extends StatelessWidget {
  const NotificationLiveUpdateSettings({
    super.key,
    required this.isLoading,
    required this.isEnabled,
    required this.leadMinutes,
    required this.onEnabledChanged,
    required this.onLeadMinutesChanged,
  });

  final bool isLoading;
  final bool isEnabled;
  final int leadMinutes;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onLeadMinutesChanged;

  @override
  Widget build(BuildContext context) {
    final translations = context.t.setting.notificationPage;
    return SectionSettingScaffold(
      title: translations.liveUpdateSection,
      items: SettingSegmentedList(
        items: [
          SwitchListTile(
            title: Text(translations.liveUpdateEnabled),
            subtitle: Text(translations.liveUpdateEnabledHint),
            value: isEnabled,
            onChanged: isLoading ? null : onEnabledChanged,
          ),
          ListTile(
            enabled: !isLoading && isEnabled,
            title: Text(translations.liveUpdateLead),
            subtitle: Text(translations.liveUpdateLeadHint),
            trailing: DropdownButton<int>(
              value: leadMinutes,
              items: kLiveUpdateLeadMinuteOptions
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == 0
                            ? translations.liveUpdateLeadAtClass
                            : '$value ${translations.minutesUnit}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: isLoading || !isEnabled
                  ? null
                  : (value) {
                      if (value != null) onLeadMinutesChanged(value);
                    },
            ),
          ),
        ],
      ),
    );
  }
}
