import 'package:flutter/material.dart';

import 'features/home/presentation/pages/home_page.dart';

class SaltToTaste extends StatefulWidget {
  SaltToTaste({Key? key}) : super(key: key);

  @override
  _SaltToTasteState createState() => _SaltToTasteState();
}

class _SaltToTasteState extends State<SaltToTaste> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salt To Taste',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
    );
  }
}
