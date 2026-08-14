import 'package:flutter/material.dart';

import 'authenticated_selector_probe_panel.dart';
import 'disposable_webview_session.dart';

class DisposableWebViewSessionShell extends StatefulWidget {
  const DisposableWebViewSessionShell({
    super.key,
    required this.initialUri,
    required this.controller,
  });

  static const Key consentCheckboxKey =
      Key('lab_webview_consent_checkbox');
  static const Key startButtonKey = Key('lab_webview_start_button');
  static const Key finishButtonKey = Key('lab_webview_finish_button');
  static const Key cancelButtonKey = Key('lab_webview_cancel_button');
  static const Key resetButtonKey = Key('lab_webview_reset_button');
  static const Key runtimeViewKey = Key('lab_webview_runtime_view');
  static const Key blockedPanelKey = Key('lab_webview_blocked_panel');
  static const Key probeExpansionKey = Key('lab_webview_probe_expansion');

  final Uri initialUri;
  final DisposableWebViewSessionController controller;

  @override
  State<DisposableWebViewSessionShell> createState() =>
      _DisposableWebViewSessionShellState();
}

class _DisposableWebViewSessionShellState
    extends State<DisposableWebViewSessionShell> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DisposableWebViewSessionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('雲端發票登入實驗')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (widget.controller.phase) {
      case DisposableWebViewSessionPhase.consent:
        return _ConsentPanel(
          accepted: widget.controller.consentAccepted,
          canStart: widget.controller.canStart,
          onChanged: widget.controller.setConsentAccepted,
          onStart: () async {
            await widget.controller.start(widget.initialUri);
          },
        );
      case DisposableWebViewSessionPhase.starting:
        return const _ProgressPanel(
          title: '正在建立一次性登入工作階段',
          message: '尚未讀取或保存任何發票資料。',
        );
      case DisposableWebViewSessionPhase.active:
        return _ActiveSessionPanel(
          runtimeView: widget.controller.buildRuntimeView(),
          probePanel: AuthenticatedSelectorProbePanel(
            controller: widget.controller,
          ),
          onFinish: widget.controller.finish,
          onCancel: widget.controller.cancel,
        );
      case DisposableWebViewSessionPhase.cleaning:
        return const _ProgressPanel(
          title: '正在清除登入工作階段',
          message: '正在清除 Cookie、快取、儲存空間與瀏覽狀態。',
        );
      case DisposableWebViewSessionPhase.completed:
        return _CompletedPanel(
          onReset: widget.controller.resetAfterCompletion,
        );
      case DisposableWebViewSessionPhase.failed:
        return _FailurePanel(
          title: '登入工作階段無法啟動',
          message: widget.controller.errorMessage ?? '未知錯誤',
          onReset: widget.controller.resetAfterStartFailure,
          canReset: true,
        );
      case DisposableWebViewSessionPhase.blocked:
        return _FailurePanel(
          key: DisposableWebViewSessionShell.blockedPanelKey,
          title: '清理失敗，已封鎖後續登入',
          message: widget.controller.errorMessage ?? '未知錯誤',
          onReset: null,
          canReset: false,
        );
    }
  }
}

class _ConsentPanel extends StatelessWidget {
  const _ConsentPanel({
    required this.accepted,
    required this.canStart,
    required this.onChanged,
    required this.onStart,
  });

  final bool accepted;
  final bool canStart;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          '一次性登入工作階段',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          '此功能目前為實驗階段。您將在官方頁面自行登入；App 不保存帳號、密碼、驗證碼、Cookie、網頁內容或瀏覽歷程。',
        ),
        const SizedBox(height: 12),
        const Text(
          '本階段只允許使用者主動檢查查詢頁結構，不填寫欄位、不執行查詢、不讀取發票，也不寫入正式交易。',
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: DisposableWebViewSessionShell.consentCheckboxKey,
          contentPadding: EdgeInsets.zero,
          value: accepted,
          onChanged: (value) => onChanged(value ?? false),
          title: const Text('我了解這是一次性、無背景同步的登入工作階段'),
          subtitle: const Text('未勾選前無法開始。'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: DisposableWebViewSessionShell.startButtonKey,
          onPressed: canStart
              ? () async {
                  await onStart();
                }
              : null,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('開始一次性登入'),
        ),
      ],
    );
  }
}

class _ActiveSessionPanel extends StatelessWidget {
  const _ActiveSessionPanel({
    required this.runtimeView,
    required this.probePanel,
    required this.onFinish,
    required this.onCancel,
  });

  final Widget? runtimeView;
  final Widget probePanel;
  final Future<void> Function() onFinish;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        if (!keyboardVisible) ...[
          const MaterialBanner(
            content: Text(
              '登入過程不會被保存。相容性檢查只回傳控制項結構，不回傳欄位值或發票內容。',
            ),
            actions: [SizedBox.shrink()],
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          key: DisposableWebViewSessionShell.runtimeViewKey,
          child: runtimeView ??
              const Center(child: Text('WebView 工作階段尚未就緒')),
        ),
        if (!keyboardVisible) ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              key: DisposableWebViewSessionShell.probeExpansionKey,
              initiallyExpanded: false,
              maintainState: true,
              title: const Text('登入後頁面相容性檢查'),
              subtitle: const Text('登入或完成查詢後再展開；平時收合以保留網頁操作空間。'),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    primary: false,
                    child: probePanel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: DisposableWebViewSessionShell.cancelButtonKey,
                  onPressed: () async {
                    await onCancel();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('取消並清除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: DisposableWebViewSessionShell.finishButtonKey,
                  onPressed: () async {
                    await onFinish();
                  },
                  icon: const Icon(Icons.done),
                  label: const Text('完成並清除'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CompletedPanel extends StatelessWidget {
  const _CompletedPanel({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined, size: 56),
          const SizedBox(height: 12),
          Text(
            '工作階段已清除',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('相容性檢查報告已丟棄；再次登入前必須重新閱讀並同意。'),
          const SizedBox(height: 16),
          OutlinedButton(
            key: DisposableWebViewSessionShell.resetButtonKey,
            onPressed: onReset,
            child: const Text('返回同意畫面'),
          ),
        ],
      ),
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    super.key,
    required this.title,
    required this.message,
    required this.onReset,
    required this.canReset,
  });

  final String title;
  final String message;
  final VoidCallback? onReset;
  final bool canReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block_outlined, size: 56),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (canReset && onReset != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: DisposableWebViewSessionShell.resetButtonKey,
              onPressed: onReset,
              child: const Text('返回'),
            ),
          ],
        ],
      ),
    );
  }
}
