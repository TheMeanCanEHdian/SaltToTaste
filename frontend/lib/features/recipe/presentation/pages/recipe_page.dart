import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/nav_bar.dart';
import '../../../../injection_container.dart' as di;
import '../bloc/recipe_bloc.dart';

class RecipePage extends StatelessWidget {
  final String titleSanitized;

  const RecipePage({
    Key? key,
    required this.titleSanitized,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => di.sl<RecipeBloc>()
        ..add(
          RecipeFetch(titleSanitized: titleSanitized),
        ),
      child: const RecipePageContent(),
    );
  }
}

class RecipePageContent extends StatelessWidget {
  const RecipePageContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<RecipeBloc, RecipeState>(
        builder: (context, state) {
          if (state is RecipeInProgress) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (state is RecipeFailure) {
            return const Text('Failure');
          }
          if (state is RecipeSuccess) {
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: 64,
                    left: 4,
                    right: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 500,
                            child: Text(
                              state.recipe.title,
                              style: TextStyle(
                                fontSize: 30,
                              ),
                            ),
                          ),
                          Placeholder(),
                        ],
                      ),
                    ],
                  ),
                ),
                const NavBar(),
              ],
            );
          }
          return const Text('Unknown bloc state');
        },
      ),
    );
  }
}
