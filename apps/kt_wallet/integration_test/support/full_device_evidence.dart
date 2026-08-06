import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/widgets/pin_pad.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart';

/// Captures machine-readable UI evidence from a physical-device integration
/// run. Screenshots are deliberately secondary: assertions and the report use
/// widget/semantics/input/control state collected from the live Flutter tree.
class FullDeviceEvidence {
  FullDeviceEvidence._({required this.directory, required this.runId});

  final Directory directory;
  final String runId;
  final GlobalKey screenshotBoundaryKey = GlobalKey(
    debugLabel: 'full-device-evidence-boundary',
  );
  final Map<String, Object?> _facts = <String, Object?>{};
  final Map<String, Object?> _secrets = <String, Object?>{};
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _steps = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _frameworkErrors = <Map<String, Object?>>[];
  final DateTime _startedAt = DateTime.now().toUtc();
  static const viewerPause = Duration(seconds: 5);
  String _status = 'running';
  int _sequence = 0;
  void Function(FlutterErrorDetails details)? _previousFlutterErrorHandler;

  static Future<FullDeviceEvidence> create({required String runId}) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documents.path, 'kt-e2e-evidence', 'latest'),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    final report = FullDeviceEvidence._(directory: directory, runId: runId);
    await report._flush();
    return report;
  }

  String get databasePath => p.join(directory.path, 'journey.sqlite');

  /// Adds Flutter framework failures (including layout overflows) to the
  /// private report while preserving the integration-test binding's original
  /// failure handling.
  void startFrameworkErrorCapture() {
    if (_previousFlutterErrorHandler != null) return;
    final previous = FlutterError.onError;
    _previousFlutterErrorHandler = previous;
    FlutterError.onError = (details) {
      _frameworkErrors.add(<String, Object?>{
        'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
        'exception': details.exceptionAsString(),
        if (details.library != null) 'library': details.library,
        if (details.context != null)
          'context': details.context!.toDescription(),
        if (details.stack != null) 'stack': details.stack.toString(),
      });
      previous?.call(details);
    };
  }

  void stopFrameworkErrorCapture() {
    final previous = _previousFlutterErrorHandler;
    if (previous == null) return;
    FlutterError.onError = previous;
    _previousFlutterErrorHandler = null;
  }

  Future<void> setFact(String name, Object? value) async {
    _facts[name] = value;
    await _flush();
  }

  Future<void> setSecret(String name, Object? value) async {
    _secrets[name] = value;
    await _flush();
  }

  Future<void> event(
    String name, {
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    _events.add(<String, Object?>{
      'sequence': ++_sequence,
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
      'name': name,
      'details': details,
    });
    await _flush();
  }

  /// Records every visible text/input/semantic/control state in the current
  /// viewport. Nothing is redacted: this report is an explicitly private E2E
  /// artifact and includes mnemonic input/output as requested by the owner.
  Future<Map<String, Object?>> snapshot(
    IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester,
    String name, {
    Map<String, Object?> facts = const <String, Object?>{},
    bool screenshot = true,
  }) async {
    await tester.pump();
    final sequence = ++_sequence;
    final slug = _slug(name);
    String? screenshotFile;
    String? screenshotError;
    if (screenshot) {
      screenshotFile = '${sequence.toString().padLeft(3, '0')}-$slug.png';
      try {
        final boundary = screenshotBoundaryKey.currentContext
            ?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('evidence screenshot boundary is unavailable');
        }
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (byteData == null) throw StateError('PNG encoding failed');
        final bytes = byteData.buffer.asUint8List();
        await File(
          p.join(directory.path, screenshotFile),
        ).writeAsBytes(bytes, flush: true);
      } on Object catch (error) {
        screenshotError = error.runtimeType.toString();
        screenshotFile = null;
      }
    }

    final visible = <Map<String, Object?>>[];
    for (final element in tester.allElements) {
      final entry = _elementEvidence(element);
      if (entry != null) visible.add(entry);
    }
    final deduplicated = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final entry in visible) {
      final signature = jsonEncode(entry);
      if (seen.add(signature)) deduplicated.add(entry);
    }
    if (deduplicated.isEmpty) {
      throw TestFailure('No visible structured UI evidence captured for $name');
    }

    final view = tester.view;
    final record = <String, Object?>{
      'sequence': sequence,
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
      'name': name,
      'screenshot': screenshotFile,
      'screenshot_error': ?screenshotError,
      'viewport': <String, Object?>{
        'physical_width': view.physicalSize.width,
        'physical_height': view.physicalSize.height,
        'device_pixel_ratio': view.devicePixelRatio,
      },
      'facts': facts,
      'framework_error_count': _frameworkErrors.length,
      'visible_element_count': deduplicated.length,
      'visible_elements': deduplicated,
    };
    _steps.add(record);
    await _flush();
    // Keep every captured state on the physical screen long enough for a
    // person watching the mirrored iPhone to read it. This also slows PIN-dot
    // and other per-control transitions instead of only pausing at pages.
    await tester.runAsync(() => Future<void>.delayed(viewerPause));
    return record;
  }

  /// Captures each vertical viewport of the current page and restores the
  /// original scroll offset afterwards. This makes content below the fold part
  /// of the structured report instead of leaving it only in a screenshot.
  Future<void> scanPage(
    IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester,
    String name, {
    Map<String, Object?> facts = const <String, Object?>{},
    bool screenshots = true,
  }) async {
    final candidates = <(ScrollableState, Finder)>[];
    for (final element in find.byType(Scrollable).evaluate()) {
      if (!_isVisible(element)) continue;
      final widget = element.widget as Scrollable;
      if (widget.axisDirection != AxisDirection.down &&
          widget.axisDirection != AxisDirection.up) {
        continue;
      }
      // Navigator keeps covered routes mounted. Geometry alone therefore
      // mistakes an underlying records list for the current detail page's
      // scrollable. Require the scrollable to participate in the current hit
      // test so only the top interactive route is scanned.
      final finder = find.byWidget(widget).hitTestable();
      if (finder.evaluate().isEmpty) continue;
      final state = tester.state<ScrollableState>(finder);
      if (state.position.maxScrollExtent > state.position.minScrollExtent) {
        candidates.add((state, finder));
      }
    }
    if (candidates.isEmpty) {
      await snapshot(
        binding,
        tester,
        '$name viewport 1',
        facts: facts,
        screenshot: screenshots,
      );
      return;
    }

    final (state, _) = candidates.first;
    final position = state.position;
    final original = position.pixels;
    if (position.hasPixels &&
        (position.pixels - position.minScrollExtent).abs() > 0.5) {
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
    }
    await snapshot(
      binding,
      tester,
      '$name viewport 1',
      facts: <String, Object?>{
        ...facts,
        'scroll_offset': position.pixels,
        'scroll_max': position.maxScrollExtent,
      },
      screenshot: screenshots,
    );
    var viewport = 1;
    while (position.pixels < position.maxScrollExtent - 0.5 && viewport < 20) {
      final next = math.min(
        position.maxScrollExtent,
        position.pixels + math.max(160, position.viewportDimension * 0.78),
      );
      position.jumpTo(next);
      await tester.pumpAndSettle();
      viewport++;
      await snapshot(
        binding,
        tester,
        '$name viewport $viewport',
        facts: <String, Object?>{
          ...facts,
          'scroll_offset': position.pixels,
          'scroll_max': position.maxScrollExtent,
        },
        screenshot: screenshots,
      );
    }
    if (position.hasPixels) {
      position.jumpTo(
        original.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> complete() async {
    _status = 'passed';
    await _flush();
  }

  Future<void> fail(Object error, StackTrace stackTrace) async {
    _status = 'failed';
    _facts['failure_type'] = error.runtimeType.toString();
    _facts['failure'] = error.toString();
    _facts['failure_stack'] = stackTrace.toString();
    await _flush();
  }

  Map<String, Object?>? _elementEvidence(Element element) {
    if (!_isVisible(element)) return null;
    final widget = element.widget;
    final data = <String, Object?>{
      'widget': widget.runtimeType.toString(),
      if (widget.key != null) 'key': widget.key.toString(),
      'rect': _rect(element),
    };
    var informative = widget.key != null;

    if (widget case final Text text) {
      final value = text.data ?? text.textSpan?.toPlainText() ?? '';
      if (value.isNotEmpty) {
        data['text'] = value;
        informative = true;
      }
    }
    if (widget case final RichText richText) {
      final value = richText.text.toPlainText();
      if (value.isNotEmpty) {
        data['rich_text'] = value;
        informative = true;
      }
    }
    if (widget case final TextField field) {
      data.addAll(<String, Object?>{
        'control': 'text_field',
        'value': field.controller?.text ?? '',
        'enabled': field.enabled ?? true,
        'read_only': field.readOnly,
        'obscured': field.obscureText,
      });
      informative = true;
    }
    if (widget case final EditableText editable) {
      data.addAll(<String, Object?>{
        'control': 'editable_text',
        'value': editable.controller.text,
        'selection_start': editable.controller.selection.start,
        'selection_end': editable.controller.selection.end,
        'read_only': editable.readOnly,
        'obscured': editable.obscureText,
      });
      informative = true;
    }
    if (widget case final Semantics semantics) {
      final props = semantics.properties;
      data.addAll(<String, Object?>{
        'control': 'semantics',
        if ((props.label ?? '').isNotEmpty) 'label': props.label,
        if ((props.value ?? '').isNotEmpty) 'value': props.value,
        if ((props.hint ?? '').isNotEmpty) 'hint': props.hint,
        if ((props.tooltip ?? '').isNotEmpty) 'tooltip': props.tooltip,
        if (props.enabled != null) 'enabled': props.enabled,
        if (props.checked != null) 'checked': props.checked,
        if (props.mixed != null) 'mixed': props.mixed,
        if (props.expanded != null) 'expanded': props.expanded,
        if (props.toggled != null) 'toggled': props.toggled,
        if (props.selected != null) 'selected': props.selected,
        if (props.inMutuallyExclusiveGroup != null)
          'in_mutually_exclusive_group': props.inMutuallyExclusiveGroup,
        if (props.button != null) 'button': props.button,
        if (props.link != null) 'link': props.link,
        if (props.textField != null) 'text_field': props.textField,
        if (props.readOnly != null) 'read_only': props.readOnly,
        if (props.focused != null) 'focused': props.focused,
        if (props.hidden != null) 'hidden': props.hidden,
        if (props.obscured != null) 'obscured': props.obscured,
      });
      informative = true;
    }
    if (widget case final ButtonStyleButton button) {
      data.addAll(<String, Object?>{
        'control': 'button',
        'enabled': button.onPressed != null,
        'long_press_enabled': button.onLongPress != null,
      });
      informative = true;
    }
    if (widget case final IconButton button) {
      data.addAll(<String, Object?>{
        'control': 'icon_button',
        'enabled': button.onPressed != null,
        if (button.tooltip != null) 'tooltip': button.tooltip,
      });
      informative = true;
    }
    if (widget case final GestureDetector gesture) {
      data.addAll(<String, Object?>{
        'control': 'gesture',
        'tap_enabled': gesture.onTap != null,
        'long_press_enabled': gesture.onLongPress != null,
        'vertical_drag_enabled': gesture.onVerticalDragUpdate != null,
        'horizontal_drag_enabled': gesture.onHorizontalDragUpdate != null,
      });
      informative = true;
    }
    if (widget case final InkWell ink) {
      data.addAll(<String, Object?>{
        'control': 'ink_well',
        'tap_enabled': ink.onTap != null,
        'long_press_enabled': ink.onLongPress != null,
      });
      informative = true;
    }
    if (widget case final ListTile tile) {
      data.addAll(<String, Object?>{
        'control': 'list_tile',
        'enabled': tile.enabled,
        'selected': tile.selected,
        'tap_enabled': tile.onTap != null,
      });
      informative = true;
    }
    if (widget case final Switch toggle) {
      data.addAll(<String, Object?>{
        'control': 'switch',
        'value': toggle.value,
        'enabled': toggle.onChanged != null,
      });
      informative = true;
    }
    if (widget case final Checkbox checkbox) {
      data.addAll(<String, Object?>{
        'control': 'checkbox',
        'value': checkbox.value,
        'enabled': checkbox.onChanged != null,
        'tristate': checkbox.tristate,
      });
      informative = true;
    }
    if (widget case final Slider slider) {
      data.addAll(<String, Object?>{
        'control': 'slider',
        'value': slider.value,
        'min': slider.min,
        'max': slider.max,
        'enabled': slider.onChanged != null,
      });
      informative = true;
    }
    if (widget case final PinDots dots) {
      data.addAll(<String, Object?>{
        'control': 'pin_dots',
        'filled': dots.filled,
        'total': 6,
      });
      informative = true;
    }
    if (widget case final KtQrCode qr) {
      data.addAll(<String, Object?>{'control': 'qr_code', 'data': qr.data});
      informative = true;
    }
    if (widget case final Icon icon) {
      final iconData = icon.icon;
      if (iconData != null) {
        data['icon'] = <String, Object?>{
          'code_point': iconData.codePoint,
          'font_family': iconData.fontFamily,
        };
        informative = true;
      }
    }
    if (widget case final CircularProgressIndicator progress) {
      data.addAll(<String, Object?>{
        'control': 'circular_progress',
        'value': progress.value,
      });
      informative = true;
    }
    if (widget case final LinearProgressIndicator progress) {
      data.addAll(<String, Object?>{
        'control': 'linear_progress',
        'value': progress.value,
      });
      informative = true;
    }
    if (widget case final Scrollable scrollable) {
      data.addAll(<String, Object?>{
        'control': 'scrollable',
        'axis_direction': scrollable.axisDirection.name,
      });
      informative = true;
    }
    return informative ? data : null;
  }

  static bool _isVisible(Element element) {
    var hidden = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if ((widget is Offstage && widget.offstage) ||
          (widget is Visibility && !widget.visible) ||
          (widget is Opacity && widget.opacity <= 0) ||
          (widget is FadeTransition && widget.opacity.value <= 0) ||
          (widget is IgnorePointer && widget.ignoring) ||
          (widget is TickerMode && !widget.enabled)) {
        hidden = true;
        return false;
      }
      return true;
    });
    if (hidden) return false;
    final render = element.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return false;
    }
    try {
      final topLeft = render.localToGlobal(render.paintBounds.topLeft);
      final bottomRight = render.localToGlobal(render.paintBounds.bottomRight);
      final rect = Rect.fromPoints(topLeft, bottomRight);
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      return !rect.isEmpty && rect.overlaps(Offset.zero & logicalSize);
    } on Object {
      return false;
    }
  }

  static Map<String, double> _rect(Element element) {
    final render = element.renderObject! as RenderBox;
    final topLeft = render.localToGlobal(render.paintBounds.topLeft);
    final bottomRight = render.localToGlobal(render.paintBounds.bottomRight);
    return <String, double>{
      'left': topLeft.dx,
      'top': topLeft.dy,
      'right': bottomRight.dx,
      'bottom': bottomRight.dy,
    };
  }

  Future<void> _flush() async {
    final endedAt = _status == 'running'
        ? null
        : DateTime.now().toUtc().toIso8601String();
    final document = <String, Object?>{
      'schema': 'kt-wallet-full-device-evidence-v1',
      'run_id': runId,
      'status': _status,
      'started_at_utc': _startedAt.toIso8601String(),
      'ended_at_utc': ?endedAt,
      'platform': Platform.operatingSystem,
      'platform_version': Platform.operatingSystemVersion,
      'evidence_policy': <String, Object?>{
        'screenshots_are_assertion_source': false,
        'structured_live_widget_state_is_assertion_source': true,
        'mnemonics_are_included_unredacted': true,
        'chain_data_is_mocked': false,
        'minimum_viewer_pause_ms_per_step': viewerPause.inMilliseconds,
      },
      'secrets_unredacted': _secrets,
      'facts': _facts,
      'events': _events,
      'framework_errors': _frameworkErrors,
      'steps': _steps,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await File(
      p.join(directory.path, 'report.json'),
    ).writeAsString(encoder.convert(document), flush: true);

    final markdown = StringBuffer()
      ..writeln('# KT Wallet 真机全流程 E2E 报告')
      ..writeln()
      ..writeln('> 私有测试证据：包含未脱敏助记词、PIN、地址和交易数据。')
      ..writeln()
      ..writeln('- Run ID: `$runId`')
      ..writeln('- Status: `$_status`')
      ..writeln('- Started (UTC): `${_startedAt.toIso8601String()}`')
      ..writeln('- Platform: `${Platform.operatingSystemVersion}`')
      ..writeln('- 判断来源：实机 Flutter widget / semantics / input / control 状态')
      ..writeln('- 截图：仅作辅助证据，不作为断言来源')
      ..writeln('- 链上数据：真实 RPC / Gateway / 测试网，未使用 mock')
      ..writeln()
      ..writeln('## 完整敏感数据（未脱敏）')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoder.convert(_secrets))
      ..writeln('```')
      ..writeln()
      ..writeln('## 运行事实')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoder.convert(_facts))
      ..writeln('```')
      ..writeln()
      ..writeln('## 控件操作与状态事件')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoder.convert(_events))
      ..writeln('```')
      ..writeln()
      ..writeln('## Flutter 框架错误与布局异常')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoder.convert(_frameworkErrors))
      ..writeln('```')
      ..writeln()
      ..writeln('## 每一步的全部可见信息与控件状态')
      ..writeln();
    for (final step in _steps) {
      markdown
        ..writeln('### ${step['sequence']}. ${step['name']}')
        ..writeln()
        ..writeln('```json')
        ..writeln(encoder.convert(step))
        ..writeln('```')
        ..writeln();
    }
    await File(
      p.join(directory.path, 'report.md'),
    ).writeAsString(markdown.toString(), flush: true);
  }

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'step' : slug;
  }
}
