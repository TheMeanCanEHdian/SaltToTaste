import 'package:flutter/material.dart';

class SettingsSectionHeading extends StatelessWidget {
  const SettingsSectionHeading({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(
        bottom: 8,
      ),
      child: Text(
        'Edamam Nutrition Analysis',
        style: TextStyle(
          fontSize: 16,
        ),
      ),
    );
  }
}
