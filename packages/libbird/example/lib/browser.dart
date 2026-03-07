import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindow extends StatefulWidget {
  const BrowserWindow({super.key});

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow> {
  final _controller = LadybirdController();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final radius = 12.0;
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _textController,
              onSubmitted: (value) {
                _controller.navigate(value);
              },
              scrollPadding: .all(0),
              decoration: InputDecoration(
                hintText: "Search",
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                hintStyle: theme.textTheme.labelLarge!.copyWith(
                  color: theme.colorScheme.surfaceContainerHighest,
                  fontWeight: .w400,
                  fontSize: 13.5,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radius),
                  borderSide: BorderSide(
                    color: theme.colorScheme.surfaceContainerHigh,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radius),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radius),
                  borderSide: BorderSide(
                    color: theme.colorScheme.error,
                    width: 1,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radius),
                  borderSide: BorderSide(
                    color: theme.colorScheme.error,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: LadybirdView(controller: _controller)),
        ],
      ),
    );
  }
}
