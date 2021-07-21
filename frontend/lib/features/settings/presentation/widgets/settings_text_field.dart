import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

class SettingsTextField extends StatelessWidget {
  final String title;
  final String formFieldName;
  final String initialValue;

  const SettingsTextField({
    Key? key,
    required this.title,
    required this.formFieldName,
    this.initialValue = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(title),
          ),
        ),
        const SizedBox(width: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400,
          ),
          child: FormBuilderTextField(
            name: formFieldName,
            initialValue: initialValue,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        )
      ],
    );
  }
}
