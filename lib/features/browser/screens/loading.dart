import 'package:bird_core/bird_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/frontend/components/adaptive_widgets.dart';
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
    final tab = ref.read(browserTabControllerProvider).first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go("/browser/tab/${tab.viewId}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return const FrontendScaffold(
      body: Center(child: FrontendProgressIndicator()),
    );
  }
}
