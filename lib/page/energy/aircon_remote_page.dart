// Copyright 2026 Traintime PDA authors.
// SPDX-License-Identifier: MPL-2.0

// 空调遥控页。
//
// 界面照米家（Mi Home）的空调遥控页复刻：顶上一个大温度加一行运行模式，
// 下面依次是用电信息、电源、温度调节（滑条）、风速、扫风/强力/电辅热、
// 运行模式，都是一张张白卡片，蓝色做强调色、橙色点电源。
//
// 下发的指令载荷和"乐观更新 + 轮询确认"那套逻辑沿用原来的实现，只换了外观。

import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:watermeter/controller/aircon_controller.dart';
import 'package:watermeter/model/aircon_state.dart';
import 'package:watermeter/page/public_widget/toast.dart';
import 'package:watermeter/page/setting/dialogs/aircon_imei_dialog.dart';
import 'package:watermeter/repository/miscellaneous_session/aircon_session.dart';

/// 米家那套蓝色与橙色。
const _miBlue = Color(0xFF2F6BE4);
const _miOrange = Color(0xFFFF6A00);

/// 温度的可调范围，和设备本身一致。
const _minTemperature = 18;
const _maxTemperature = 32;

class AirconRemotePage extends StatefulWidget {
  const AirconRemotePage({super.key});

  @override
  State<AirconRemotePage> createState() => _AirconRemotePageState();
}

class _AirconRemotePageState extends State<AirconRemotePage> {
  final _controller = AirconController.i;
  AirconState? _state;
  Object? _error;
  bool _isFetching = false;
  bool Function(AirconState state)? _pendingMatches;

  static const _pollInterval = Duration(milliseconds: 300);
  static const _pollAttempts = 12;

  @override
  void initState() {
    super.initState();
    _state = _controller.deviceStateSignal.peek().value;
    Future.microtask(_refreshDeviceState);
  }

  Future<void> _configure() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const AirconImeiDialog(),
    );
    if (!mounted) return;
    setState(() {
      _state = null;
      _error = null;
    });
    await _refreshDeviceState();
  }

  Future<void> _refreshDeviceState() async {
    final imei = _controller.imeiSignal.value;
    if (imei.isEmpty || _isFetching) return;

    setState(() {
      _isFetching = true;
      _error = null;
    });

    try {
      final state = await _controller.session.getDeviceState(imei);
      if (!mounted || imei != _controller.imeiSignal.value) return;

      final matches = _pendingMatches;
      if (matches != null && !matches(state)) {
        setState(() {
          _error = const AirconResponseException("设备状态仍未确认");
          _isFetching = false;
        });
        return;
      }

      setState(() {
        _state = state;
        _error = null;
        _isFetching = false;
        _pendingMatches = null;
      });
      _controller.setDeviceState(state);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isFetching = false;
      });
    }
  }

  Future<void> _sendCommand({
    required Map<String, dynamic> command,
    required AirconState optimisticState,
    required bool Function(AirconState state) matches,
  }) async {
    final imei = _controller.imeiSignal.value;
    final previous = _state;
    if (imei.isEmpty ||
        previous == null ||
        _pendingMatches != null ||
        _isFetching) {
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _state = optimisticState;
      _error = null;
      _isFetching = true;
      _pendingMatches = matches;
    });

    var commandSent = false;
    try {
      await _controller.session.sendCommand(imei: imei, command: command);
      commandSent = true;
      AirconState? confirmedState;
      Object? pollError;

      for (var attempt = 0; attempt < _pollAttempts; attempt++) {
        if (attempt > 0) await Future<void>.delayed(_pollInterval);
        if (!mounted || imei != _controller.imeiSignal.value) return;

        try {
          final state = await _controller.session.getDeviceState(imei);
          if (matches(state)) {
            confirmedState = state;
            break;
          }
        } catch (error) {
          pollError = error;
        }
      }

      if (!mounted || imei != _controller.imeiSignal.value) return;
      if (confirmedState == null) {
        throw pollError ?? const AirconResponseException("设备状态未确认");
      }

      setState(() {
        _state = confirmedState;
        _error = null;
        _isFetching = false;
        _pendingMatches = null;
      });
      _controller.setDeviceState(confirmedState);
      showToast(
        context: context,
        msg: FlutterI18n.translate(context, "electricity.aircon_command_ok"),
      );
    } catch (error) {
      if (!mounted || imei != _controller.imeiSignal.value) return;
      setState(() {
        _error = error;
        _isFetching = false;
        if (!commandSent) {
          _state = previous;
          _pendingMatches = null;
        }
      });
      showToast(context: context, msg: error.toString());
    }
  }

  // --- 各个控件的下发 ---

  void _setPower(AirconState state, bool value) => _sendCommand(
    command: value
        ? {"switchStatus": 1}
        : {
            "switchStatus": 0,
            "indoorClean": 0,
            "outdoorClean": 0,
            "electricHeating": 0,
          },
    optimisticState: state.copyWith(
      isOn: value,
      electricHeating: value ? state.electricHeating : false,
    ),
    matches: (state) => state.isOn == value,
  );

  void _setTemperature(AirconState state, int value) {
    if (value < _minTemperature || value > _maxTemperature) {
      showToast(
        context: context,
        msg: FlutterI18n.translate(
          context,
          "electricity.aircon_temperature_range",
        ),
      );
      return;
    }
    _sendCommand(
      command: {"tempSet": value},
      optimisticState: state.copyWith(targetTemperature: value),
      matches: (state) => state.targetTemperature == value,
    );
  }

  void _setMode(AirconState state, AirconMode mode) {
    if (mode == state.mode) return;

    /// 换模式时设备会顺手改温度和风速，这里跟着一起报上去，
    /// 免得轮询确认时对不上。
    final temperature = switch (mode) {
      AirconMode.heat => 23,
      AirconMode.cool => 26,
      _ => 25,
    };
    final windSpeed = mode == AirconMode.fan
        ? AirconWindSpeed.medium
        : AirconWindSpeed.auto;
    _sendCommand(
      command: {
        "runMode": mode.value.toString(),
        "indoorClean": 0,
        "outdoorClean": 0,
        "strongMode": 0,
        "electricHeating": 0,
        "tempView": temperature,
        "tempSet": temperature,
        "windSpeed": windSpeed.value,
      },
      optimisticState: state.copyWith(
        mode: mode,
        targetTemperature: temperature,
        windSpeed: windSpeed,
        strongMode: false,
        electricHeating: false,
      ),
      matches: (state) =>
          state.mode == mode &&
          state.targetTemperature == temperature &&
          state.windSpeed == windSpeed &&
          !state.strongMode &&
          !state.electricHeating,
    );
  }

  void _setWindSpeed(AirconState state, AirconWindSpeed speed) {
    if (speed == state.windSpeed && !state.strongMode) return;
    _sendCommand(
      command: {"windSpeed": speed.value.toString(), "strongMode": 0},
      optimisticState: state.copyWith(windSpeed: speed, strongMode: false),
      matches: (state) => state.windSpeed == speed && !state.strongMode,
    );
  }

  void _setVerticalSwing(AirconState state, bool value) => _sendCommand(
    command: {"verticalSwing": value ? 1 : 0},
    optimisticState: state.copyWith(verticalSwing: value),
    matches: (state) => state.verticalSwing == value,
  );

  void _setStrongMode(AirconState state, bool value) => _sendCommand(
    command: {
      "strongMode": value ? 1 : 0,
      if (value) "windSpeed": AirconWindSpeed.auto.value,
    },
    optimisticState: state.copyWith(
      strongMode: value,
      windSpeed: value ? AirconWindSpeed.auto : state.windSpeed,
    ),
    matches: (state) =>
        state.strongMode == value &&
        (!value || state.windSpeed == AirconWindSpeed.auto),
  );

  void _setElectricHeating(AirconState state, bool value) => _sendCommand(
    command: {"electricHeating": value ? 1 : 0},
    optimisticState: state.copyWith(electricHeating: value),
    matches: (state) => state.electricHeating == value,
  );

  // --- 外观 ---

  /// 顶上那层渐变跟着运行模式走，开关机时也会淡下去，和米家一样。
  List<Color> _gradientColors(AirconState? state) {
    if (state == null || !state.isOn) {
      return const [Color(0xFFE8EDF5), Color(0xFFF7F9FC)];
    }
    return switch (state.mode) {
      AirconMode.cool => const [Color(0xFF7FB4F5), Color(0xFFD9E8FB)],
      AirconMode.heat => const [Color(0xFFFFB27A), Color(0xFFFFE3D0)],
      AirconMode.dry => const [Color(0xFF7FD2D6), Color(0xFFD8F0F1)],
      AirconMode.fan => const [Color(0xFFB6C4D4), Color(0xFFE7ECF2)],
      AirconMode.auto => const [Color(0xFF8FD8C0), Color(0xFFDCF2EA)],
    };
  }

  IconData _modeIcon(AirconMode mode) => switch (mode) {
    AirconMode.cool => Icons.ac_unit,
    AirconMode.heat => Icons.wb_sunny_outlined,
    AirconMode.dry => Icons.water_drop_outlined,
    AirconMode.fan => Icons.air,
    AirconMode.auto => Icons.auto_mode,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          FlutterI18n.translate(context, "electricity.aircon_remote"),
        ),
        actions: [
          IconButton(
            onPressed: _isFetching ? null : _refreshDeviceState,
            tooltip: FlutterI18n.translate(context, "electricity.update"),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _isFetching || _pendingMatches != null
                ? null
                : _configure,
            tooltip: FlutterI18n.translate(
              context,
              "setting.aircon_imei_title",
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SignalBuilder(
        builder: (context) {
          if (_controller.imeiSignal.value.isEmpty) {
            return _message(
              context,
              "electricity.aircon_imei_missing",
              onPressed: _configure,
              actionKey: "electricity.aircon_add_imei",
              actionIcon: Icons.settings_outlined,
            );
          }

          final state = _state;
          if (state == null) {
            if (_error != null) {
              return _message(
                context,
                "electricity.aircon_control_error",
                details: _error.toString(),
                onPressed: _refreshDeviceState,
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final busy = _isFetching || _pendingMatches != null;
          final gradient = _gradientColors(state);

          return Stack(
            children: [
              /// 背景渐变随模式变化，AnimatedContainer 会把颜色揉过去。
              AnimatedContainer(
                duration: const Duration(milliseconds: 480),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            Color.lerp(gradient.first, Colors.black, 0.72)!,
                            scheme.surface,
                          ]
                        : gradient,
                    stops: const [0, 0.55],
                  ),
                ),
              ),
              ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                  16,
                  28,
                ),
                children: [
                  _hero(context, state),
                  if (_error != null) _errorCard(context, _error!),
                  const SizedBox(height: 4),
                  _energyCard(context),
                  _powerCard(context, state, busy),
                  _temperatureCard(context, state, busy),
                  _windCard(context, state, busy),
                  _switchCard(context, state, busy),
                  _modeCard(context, state, busy),
                ],
              ),
              if (busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 顶上那个大温度：数字换的时候上下滑一下。
  Widget _hero(BuildContext context, AirconState state) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          if (!state.isOn)
            Text(
              FlutterI18n.translate(context, "electricity.aircon_power"),
              style: textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.35),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Text(
                    "${state.targetTemperature}",
                    key: ValueKey(state.targetTemperature),
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 88,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 2),
                  child: Text(
                    "℃",
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Row(
              key: ValueKey("${state.isOn}-${state.mode}"),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _modeIcon(state.mode),
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  FlutterI18n.translate(context, state.mode.labelKey),
                  style: textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, Object error) {
    final scheme = Theme.of(context).colorScheme;
    return _MiCard(
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error.toString(),
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: _isFetching ? null : _refreshDeviceState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  /// 用电信息：平台用电量、室内温度、更新时间。
  Widget _energyCard(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final async = _controller.energyInfoStateSignal.value;
        final info = async.value?.data;
        final state = _state;

        String amount = "--";
        String update = "--";
        if (info != null) {
          amount = info.electricAmount.toString();
          final time = info.stateTime;
          update =
              "${time.hour.toString().padLeft(2, "0")}:"
              "${time.minute.toString().padLeft(2, "0")}";
        }
        final indoor = state?.indoorTemperature;

        return _MiCard(
          onTap: _isFetching ? null : _controller.refreshEnergyInfo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      FlutterI18n.translate(
                        context,
                        "electricity.aircon_title",
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _energyValue(
                    context,
                    amount,
                    FlutterI18n.translate(context, "electricity.aircon_amount"),
                  ),
                  _energyValue(
                    context,
                    indoor == null ? "--" : indoor.toString(),
                    FlutterI18n.translate(context, "electricity.aircon_indoor"),
                  ),
                  _energyValue(
                    context,
                    update,
                    FlutterI18n.translate(
                      context,
                      "electricity.aircon_update_time",
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _energyValue(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 电源：一个圆钮，按下去会缩一下。
  Widget _powerCard(BuildContext context, AirconState state, bool busy) {
    return _MiCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _RoundButton(
            icon: Icons.power_settings_new,
            size: 46,
            selected: state.isOn,
            accent: state.isOn ? _miBlue : _miOrange,
            enabled: !busy,
            onTap: () => _setPower(state, !state.isOn),
          ),
          const SizedBox(width: 14),
          Text(
            FlutterI18n.translate(context, "electricity.aircon_power"),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// 温度调节：减号、滑条、加号。
  Widget _temperatureCard(BuildContext context, AirconState state, bool busy) {
    final scheme = Theme.of(context).colorScheme;
    final fraction =
        (state.targetTemperature - _minTemperature) /
        (_maxTemperature - _minTemperature);

    return _MiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                FlutterI18n.translate(
                  context,
                  "electricity.aircon_target_temperature",
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "$_minTemperature-$_maxTemperature℃",
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _RoundButton(
                icon: Icons.remove,
                selected: false,
                accent: _miBlue,
                enabled: !busy && state.targetTemperature > _minTemperature,
                onTap: () =>
                    _setTemperature(state, state.targetTemperature - 1),
              ),
              const SizedBox(width: 12),

              /// 滑条：底槽是灰的，填充是蓝的，中间写着当前温度。
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Stack(
                      children: [
                        FractionallySizedBox(
                          widthFactor: value,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            decoration: BoxDecoration(
                              color: state.isOn
                                  ? _miBlue
                                  : scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(23),
                            ),
                          ),
                        ),
                        Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              "${state.targetTemperature}℃",
                              key: ValueKey(state.targetTemperature),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _RoundButton(
                icon: Icons.add,
                selected: false,
                accent: _miBlue,
                enabled: !busy && state.targetTemperature < _maxTemperature,
                onTap: () =>
                    _setTemperature(state, state.targetTemperature + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 风速：一排圆钮，选中的是蓝底白字。
  Widget _windCard(BuildContext context, AirconState state, bool busy) {
    final scheme = Theme.of(context).colorScheme;
    return _MiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                FlutterI18n.translate(context, "electricity.aircon_wind_speed"),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                FlutterI18n.translate(context, state.windSpeed.labelKey),
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final speed in AirconWindSpeed.values)
                Expanded(
                  child: _OptionButton(
                    letter: _windLetter(speed),
                    label: FlutterI18n.translate(context, speed.labelKey),
                    selected: state.windSpeed == speed && !state.strongMode,
                    enabled: !busy,
                    onTap: () => _setWindSpeed(state, speed),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _windLetter(AirconWindSpeed speed) => switch (speed) {
    AirconWindSpeed.auto => "A",
    AirconWindSpeed.silent => "S",
    AirconWindSpeed.low => "L",
    AirconWindSpeed.medium => "M",
    AirconWindSpeed.high => "H",
  };

  /// 扫风、强力、电辅热三个开关。
  Widget _switchCard(BuildContext context, AirconState state, bool busy) {
    Widget row({
      required IconData icon,
      required String key,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return _SwitchRow(
        icon: icon,
        label: FlutterI18n.translate(context, key),
        value: value,
        enabled: !busy,
        onChanged: onChanged,
      );
    }

    return _MiCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          row(
            icon: Icons.swap_vert,
            key: "electricity.aircon_vertical_swing",
            value: state.verticalSwing,
            onChanged: (value) => _setVerticalSwing(state, value),
          ),
          const Divider(height: 1),
          row(
            icon: Icons.bolt_outlined,
            key: "electricity.aircon_strong_mode",
            value: state.strongMode,
            onChanged: (value) => _setStrongMode(state, value),
          ),
          const Divider(height: 1),
          row(
            icon: Icons.local_fire_department_outlined,
            key: "electricity.aircon_electric_heating",
            value: state.electricHeating,
            onChanged: (value) => _setElectricHeating(state, value),
          ),
        ],
      ),
    );
  }

  /// 运行模式：一排圆钮。
  Widget _modeCard(BuildContext context, AirconState state, bool busy) {
    /// 顺序照米家：制冷、制热、自动、送风、除湿。
    const order = [
      AirconMode.cool,
      AirconMode.heat,
      AirconMode.auto,
      AirconMode.fan,
      AirconMode.dry,
    ];

    return _MiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            FlutterI18n.translate(context, "electricity.aircon_mode"),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final mode in order)
                Expanded(
                  child: _OptionButton(
                    icon: _modeIcon(mode),
                    label: FlutterI18n.translate(context, mode.labelKey),
                    selected: state.mode == mode,
                    enabled: !busy,
                    onTap: () => _setMode(state, mode),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _message(
    BuildContext context,
    String key, {
    String? details,
    required VoidCallback onPressed,
    String actionKey = "electricity.aircon_retry",
    IconData actionIcon = Icons.refresh,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ac_unit, size: 56),
            const SizedBox(height: 16),
            Text(
              FlutterI18n.translate(context, key),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(actionIcon),
              label: Text(FlutterI18n.translate(context, actionKey)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 米家那种白卡片：大圆角、很淡的阴影。
class _MiCard extends StatelessWidget {
  const _MiCard({required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTap,
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// 圆形按钮：选中是实心蓝，未选中是浅灰底。
class _RoundButton extends StatefulWidget {
  const _RoundButton({
    this.icon,
    this.letter,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.size = 44,
  });

  final IconData? icon;

  /// 画一个字母而不是图标，风速那排用得上（A/S/L/M/H）。
  final String? letter;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;
  final double size;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = !widget.enabled
        ? scheme.surfaceContainerHighest
        : widget.selected
        ? widget.accent
        : scheme.surfaceContainerHighest;
    final foreground = !widget.enabled
        ? scheme.outline
        : widget.selected
        ? Colors.white
        : scheme.onSurfaceVariant;

    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: widget.letter != null
              ? Center(
                  child: Text(
                    widget.letter!,
                    style: TextStyle(
                      fontSize: widget.size * 0.42,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                )
              : Icon(
                  widget.icon ?? Icons.circle,
                  size: widget.size * 0.5,
                  color: foreground,
                ),
        ),
      ),
    );
  }
}

/// 图标/字母加一行文字的圆钮，风速和模式都用它。
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    this.icon,
    this.letter,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData? icon;
  final String? letter;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? _miBlue : scheme.surfaceContainerHighest;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          icon: icon,
          letter: letter,
          selected: selected,
          accent: background,
          enabled: enabled,
          onTap: onTap,
          size: 46,
        ),
        const SizedBox(height: 8),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 12,
            color: selected ? _miBlue : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 一行开关，左边一个圆图标、中间文字、右边开关。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: value ? _miBlue : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? Colors.white : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
