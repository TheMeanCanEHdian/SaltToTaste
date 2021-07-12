import 'package:flutter/material.dart';

import '../../../../core/widgets/nav_bar.dart';

class RecipePage extends StatelessWidget {
  final String titleSanitized;

  const RecipePage({
    Key? key,
    required this.titleSanitized,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 64,
              left: 4,
              right: 4,
            ),
            child: Text(titleSanitized),
          ),
          const NavBar(),
        ],
      ),
    );
  }
}
