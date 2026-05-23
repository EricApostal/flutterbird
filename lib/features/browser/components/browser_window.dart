import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:flutter/src/widgets/_window.dart';

class BrowserWindow extends ConsumerWidget {
  final int viewId;
  const BrowserWindow({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(browserTabProvider(viewId))!;

    return LadybirdView(controller: controller);
  }
}
