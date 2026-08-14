import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'invoice_frozen_review_page.dart';
import 'invoice_image_import_page.dart';
import 'invoice_live_capture_page.dart';

class InvoiceCaptureEntryPage extends StatelessWidget {
  const InvoiceCaptureEntryPage({super.key});

  static const Key liveActionKey = Key('invoice_capture_entry_live');
  static const Key imageActionKey = Key('invoice_capture_entry_image');

  Future<void> _openLive(BuildContext context) async {
    final result = await context.pushNamed<InvoiceLiveCaptureResult>(
      InvoiceLiveCapturePage.routeName,
    );
    if (!context.mounted || result == null) return;
    await context.pushNamed(
      InvoiceFrozenReviewPage.routeName,
      extra: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('發票辨識')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: <Widget>[
          Text(
            '選擇辨識方式',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '正式入口只保留 Live 與圖片讀取。兩條路徑都先執行 Local QR/OCR，再依欄位完整度、警告與信心度決定是否自動 Gemini 覆核；結果頁永遠保留強制 Gemini 覆核。',
          ),
          const SizedBox(height: 18),
          _EntryCard(
            key: liveActionKey,
            icon: Icons.document_scanner_outlined,
            title: 'Live 即時辨識',
            subtitle: '先以低誤判 identity 證據判斷凍結時機；凍結後才詳細解析日期、金額、商家與其他欄位。',
            primary: true,
            onPressed: () => _openLive(context),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            key: imageActionKey,
            icon: Icons.photo_library_outlined,
            title: '從圖片讀取',
            subtitle: '使用手機已有的發票影像；不另外提供重複的「拍照後辨識」模式。',
            onPressed: () => context.pushNamed(InvoiceImageImportPage.routeName),
          ),
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '除錯原則：Live 凍結後可手動匯出 Evidence ZIP，包含實際影像、Local/Gemini 候選、Live frame 判讀歷程與 SHA-256。證據包不含 API Key、不會自動上傳，也不會寫入正式交易。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 14),
            if (primary)
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('開啟'),
              )
            else
              OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('開啟'),
              ),
          ],
        ),
      ),
    );
  }
}
