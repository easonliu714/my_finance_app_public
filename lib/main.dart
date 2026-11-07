import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Exact production application root shared by the installed entrypoint and
/// disposable Release-AOT router witness; no alternate diagnostic app shell.
Widget buildProductionApp() => const ProviderScope(child: MyFinanceApp());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildProductionApp());
}
