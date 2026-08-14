import 'package:flutter/material.dart';

class CaptureHelpButton extends StatelessWidget {
  const CaptureHelpButton({
    super.key,
    required this.dialogTitle,
    required this.sections,
  });

  final String dialogTitle;
  final List<CaptureHelpSection> sections;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '使用說明',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(dialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < sections.length; index++) ...[
                  Text(
                    sections[index].title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(sections[index].body),
                  if (index != sections.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureHelpSection {
  const CaptureHelpSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}
