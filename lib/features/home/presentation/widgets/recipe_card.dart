import 'package:flutter/material.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      color: Colors.black12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        // Material is needed inside ClipRRect for InkWell to respect borderRadius
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(
                        left: 4,
                      ),
                      child: Text(
                        'Recipe Title',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 4,
                        left: 4,
                        bottom: 4,
                      ),
                      child: Row(
                        children: const [
                          Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Chip(
                              label: Text('chip'),
                            ),
                          ),
                          Chip(
                            label: Text('chip'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
