import 'package:flutter/material.dart';

class BrowserTab extends StatelessWidget {
  const BrowserTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: .vertical(top: .circular(12), bottom: .circular(12)),
      ),
      child: Align(
        alignment: .centerLeft,
        child: Padding(padding: .only(left: 12), child: Text("ree")),
      ),
    );
  }
}
