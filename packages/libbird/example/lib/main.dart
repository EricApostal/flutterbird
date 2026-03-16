import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

void main() {
  runApp(const MinimalLadybirdApp());
}

class MinimalLadybirdApp extends StatelessWidget {
  const MinimalLadybirdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MinimalLadybirdScreen());
  }
}

class MinimalLadybirdScreen extends StatefulWidget {
  const MinimalLadybirdScreen({super.key});

  @override
  State<MinimalLadybirdScreen> createState() => _MinimalLadybirdScreenState();
}

class _MinimalLadybirdScreenState extends State<MinimalLadybirdScreen> {
  late final LadybirdController _controller;
  final TextEditingController _urlController = TextEditingController(
    text: 'https://example.com',
  );

  @override
  void initState() {
    super.initState();
    _controller = LadybirdController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ladybird Minimal Example')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _controller.navigate,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _controller.navigate(_urlController.text),
                  child: const Text('Go'),
                ),
              ],
            ),
          ),
          Expanded(child: LadybirdView(controller: _controller)),
        ],
      ),
    );
  }
}
