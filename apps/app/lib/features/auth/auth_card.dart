import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';

/// The centered card used by the login / setup / password screens (approved
/// P3 design): brand row, subtitle, then the form fields.
class AuthCardScaffold extends StatelessWidget {
  const AuthCardScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: SaltColors.hairline),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Image.asset(
                          'assets/images/logo_circle.png',
                          width: 40,
                          height: 40,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: SaltColors.maroon,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'S',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: SaltColors.maroon,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SaltColors.muted,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled text field in the auth-card style.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.hint,
    this.helper,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? hint;
  final String? helper;
  final bool autofocus;
  final void Function(String)? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 5),
          // The field itself carries this text as its accessible name
          // (Semantics below), so exclude the visual label to avoid a
          // screen reader announcing it twice.
          child: ExcludeSemantics(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Semantics(
          label: label,
          child: FTextField(
            control: FTextFieldControl.managed(controller: controller),
            obscureText: obscure,
            autofocus: autofocus,
            onSubmit: onSubmitted,
            hint: hint,
            description: helper == null ? null : Text(helper!),
          ),
        ),
      ],
    );
  }
}

/// Inline red/amber notice used for login errors and lockout messages.
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, required this.message, this.warning = false});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFDF1E2) : const Color(0xFFFBE9E9),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: warning ? const Color(0xFF8A5A12) : const Color(0xFF8A1212),
          ),
        ),
      ),
    );
  }
}

/// The primary full-width maroon action button, with a progress state.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        width: double.infinity,
        // FButton primary paints maroon/white from the theme; it has no
        // built-in busy state, so while busy we disable it (onPress: null) and
        // swap the label for a small spinner — matching the old behaviour.
        child: FButton(
          onPress: busy ? null : onPressed,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}
