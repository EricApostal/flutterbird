import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/omnibox_bar.dart';
import 'package:ladybird/ladybird.dart';

class DetachedTabWindowScreen extends StatelessWidget {
  final LadybirdController controller;

  const DetachedTabWindowScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          BrowserOmniboxBar(currentTabController: controller),
          Expanded(child: LadybirdView(controller: controller)),
        ],
      ),
    );
  }
}
