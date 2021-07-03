import 'package:flutter/material.dart';

import '../../../../core/widgets/nav_bar.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GridView.count(
            padding: const EdgeInsets.only(
              top: 64,
              left: 4,
              right: 4,
            ),
            crossAxisCount: 4,
            childAspectRatio: 3 / 2,
            children: const [],
          ),
          const NavBar(),
        ],
      ),
    );
  }
}
