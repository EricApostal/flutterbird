import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindow extends StatefulWidget {
  const BrowserWindow({super.key});

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<LadybirdController> _controllers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _controllers = [LadybirdController()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [Tab(text: "Uno")],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: NeverScrollableScrollPhysics(),
              children: [_BrowserTab(controller: _controllers[0])],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowserTab extends StatefulWidget {
  final LadybirdController controller;
  const _BrowserTab({super.key, required this.controller});

  @override
  State<_BrowserTab> createState() => __BrowserTabState();
}

class __BrowserTabState extends State<_BrowserTab> {
  final _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final radius = 12.0;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _textController,
            onSubmitted: (value) {
              widget.controller.navigate(value);
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
        Expanded(child: LadybirdView(controller: widget.controller)),
      ],
    );
  }
}
