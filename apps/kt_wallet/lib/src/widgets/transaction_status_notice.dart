import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/history_controller.dart';

/// App-wide, non-blocking transaction confirmation notice.
///
/// The controller resumes polling as soon as the app returns to foreground.
/// When a pending row changes to confirmed/failed this banner makes that
/// transition visible even if the user is no longer on the history screen.
class TransactionStatusNoticeHost extends StatefulWidget {
  const TransactionStatusNoticeHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final HistoryController controller;
  final Widget child;

  @override
  State<TransactionStatusNoticeHost> createState() =>
      _TransactionStatusNoticeHostState();
}

class _TransactionStatusNoticeHostState
    extends State<TransactionStatusNoticeHost> {
  TransactionStatusNotice? _notice;
  Timer? _timer;
  String? _lastKey;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(TransactionStatusNoticeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onController);
    widget.controller.addListener(_onController);
  }

  void _onController() {
    final notice = widget.controller.notice;
    if (notice == null) return;
    final key = '${notice.hash}:${notice.confirmed}';
    widget.controller.clearNotice(notice);
    if (key == _lastKey || !mounted) return;
    _lastKey = key;
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() => _notice = notice);
    _timer = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _notice = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    return Stack(
      children: [
        widget.child,
        if (notice != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: _StatusBanner(notice: notice, onDismiss: _dismiss),
            ),
          ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.notice, required this.onDismiss});

  final TransactionStatusNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = notice.confirmed
        ? l10n.transactionConfirmedNotice
        : l10n.transactionFailedNotice;
    final color = notice.confirmed ? WalletColors.green : WalletColors.red;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Material(
        elevation: 12,
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                notice.confirmed
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.actionClose,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
