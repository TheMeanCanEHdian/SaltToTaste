import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/extensions/string_extension.dart';
import '../../../../core/helpers/color_helper.dart';
import '../../../recipe/domain/entities/tag.dart';

class TagChip extends StatefulWidget {
  final Tag tag;

  TagChip({
    Key? key,
    required this.tag,
  }) : super(key: key);

  @override
  _TagChipState createState() => _TagChipState();
}

class _TagChipState extends State<TagChip> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    final chipColor = Colors.grey[300];

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (event) {
          setState(() {
            isHover = true;
          });
        },
        onExit: (event) {
          setState(() {
            isHover = false;
          });
        },
        child: ActionChip(
          onPressed: () {},
          backgroundColor:
              isHover ? ColorHelper.darken(chipColor!, .2) : chipColor,
          avatar: const FaIcon(
            FontAwesomeIcons.accessibleIcon,
            size: 18,
          ),
          labelPadding: const EdgeInsets.only(
            right: 4,
          ),
          label: Text(widget.tag.name.capitalizeEach),
        ),
      ),
    );
  }
}
