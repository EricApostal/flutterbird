import 'package:flutter/material.dart';

class NativeViewScreen extends StatelessWidget {
  const NativeViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('macOS Native View')),
      body: Center(
        child: SizedBox(
          width: 300,
          height: 200,
          child: AppKitView(viewType: 'hosted_platform_view'),
        ),
      ),
    );
  }
}
