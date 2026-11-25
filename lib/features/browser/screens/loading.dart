import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BrowserLoadingScreen extends ConsumerStatefulWidget {
  const BrowserLoadingScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _BrowserLoadingScreenState();
}

class _BrowserLoadingScreenState extends ConsumerState<BrowserLoadingScreen> {
  @override
  void initState() {
    super.initState();
    final tabId = ref.read(browserSessionProvider).windows.first.activeTabId;

    // The engine is up now that there is a tab, so extensions can start. They
    // run for the life of the app, not only while their panel is open.
    ref.read(extensionServiceProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go("/browser/tab/$tabId");
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
