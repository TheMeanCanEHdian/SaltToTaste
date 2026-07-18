import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:salt_app/core/theme/salt_theme.dart';
import 'package:salt_app/core/widgets/salt_logo.dart';

/// The centered card used by the login / setup / password screens (approved
/// P3 design): a brand header, then the form fields.
///
/// By default the header is the brand row ([title]) + [subtitle], inset like the
/// body. A caller may instead pass an edge-to-edge [header] widget (e.g. the
/// [AuthBrandHeader] band) that spans the card full-width and takes its rounded
/// top corners. With a band header, any [title]/[subtitle] still given lead the
/// body as a page sub-heading (login passes none — band only; recover passes
/// them so its functional instructions survive).
class AuthCardScaffold extends StatelessWidget {
  const AuthCardScaffold({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
    this.header,
  }) : assert(
         header != null || title != null,
         'a card needs either a header band or a title',
       );

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final head = header;
    final title = this.title;
    final subtitle = this.subtitle;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              // Clip so an edge-to-edge [header] adopts the card's rounded
              // corners instead of poking past them.
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // Border on TOP of the child so the header's fill can't paint over
              // it at the clipped rounded corners (which looked jagged / borderless).
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: SaltColors.hairline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (head != null)
                    head
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 28, 30, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const ExcludeSemantics(
                                child: SaltLogoMark(size: 40),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    title!,
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
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: SaltColors.muted,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(30, head == null ? 14 : 18, 30, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // With a band header, a page title/subtitle (if given)
                        // lead the body as a sub-heading — this is where the
                        // recover card keeps its purpose + how-to instructions.
                        if (head != null && title != null) ...[
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: SaltColors.maroon,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: SaltColors.muted,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                        ...children,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The edge-to-edge maroon brand band used as the [AuthCardScaffold.header] on
/// the sign-in and recover cards: the brand banner scaled to fit, on a solid
/// maroon field that spans the card and takes its rounded top corners.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 90,
      color: SaltColors.maroon,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Semantics(
        header: true,
        label: 'Salt to Taste',
        child: const ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SaltLogoBanner(
              color: Colors.white,
              titleSize: 40,
              gapFactor: 0.42,
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
