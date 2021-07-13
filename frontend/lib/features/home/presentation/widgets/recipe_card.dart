import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/extensions/string_extension.dart';
import '../../domain/entities/recipe.dart';

class RecipeCard extends StatefulWidget {
  final Recipe recipe;

  const RecipeCard({
    Key? key,
    required this.recipe,
  }) : super(key: key);

  @override
  _RecipeCardState createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      color: Colors.black12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        // Using InkWell for built in onHover
        child: InkWell(
          onHover: (value) {
            setState(() {
              isHover = value;
            });
          },
          onTap: () {
            Navigator.pushNamed(
              context,
              '/recipe/${widget.recipe.titleSanitized}',
            );
          },
          child: Stack(
            children: [
              // Ink.image allows for the ink effect on an image rather than fron InkWell
              Ink.image(
                image: NetworkImage(
                  'http://127.0.0.1:5000/api/image/${widget.recipe.titleSanitized}',
                ),
                fit: BoxFit.cover,
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: [0, 0.6],
                      colors: [Colors.black, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isHover ? Colors.black26 : Colors.transparent,
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                    ),
                    child: Text(
                      widget.recipe.title,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 4,
                      left: 8,
                      bottom: 8,
                    ),
                    child: Row(
                      children: widget.recipe.tags
                          .map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {},
                                    child: Chip(
                                      avatar: const FaIcon(
                                        FontAwesomeIcons.accessibleIcon,
                                        size: 18,
                                      ),
                                      labelPadding: const EdgeInsets.only(
                                        right: 4,
                                      ),
                                      label: Text(tag.name.capitalizeEach),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
