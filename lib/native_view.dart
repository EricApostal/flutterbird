import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeViewScreen extends StatelessWidget {
  const NativeViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ladybird Platform View')),
      body: const AppKitView(
        viewType: 'ladybird_view',
        creationParams: {'url': 'https://serenityos.org'},
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
