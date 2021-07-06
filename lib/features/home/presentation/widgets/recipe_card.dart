import 'package:flutter/material.dart';

class RecipeCard extends StatelessWidget {
  final String title;

  const RecipeCard({
    Key? key,
    required this.title,
  }) : super(key: key);

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
                Positioned.fill(
                  child: Image.network(
                    'http://127.0.0.1:5000/api/recipe-image',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: [0, 0.6],
                        colors: [Colors.black, Colors.transparent],
                      ),
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
                        title,
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
