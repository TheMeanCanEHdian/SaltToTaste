import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/nav_bar.dart';
import '../../../../injection_container.dart' as di;
import '../bloc/home_bloc.dart';
import '../widgets/recipe_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => di.sl<HomeBloc>()
        ..add(
          HomeFetchRecipes(),
        ),
      child: const HomePageContent(),
    );
  }
}

class HomePageContent extends StatefulWidget {
  const HomePageContent({Key? key}) : super(key: key);

  @override
  _HomePageContentState createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        if (state is HomeInProgress) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        if (state is HomeFailure) {
          return const Text('Failure');
        }
        if (state is HomeSuccess) {
          return Stack(
            children: [
              GridView.count(
                padding: const EdgeInsets.only(
                  top: 64,
                  left: 4,
                  right: 4,
                ),
                crossAxisCount: 4,
                childAspectRatio: 3 / 2,
                children: state.recipes
                    .map(
                      (recipe) => RecipeCard(recipe: recipe),
                    )
                    .toList(),
              ),
              const NavBar(),
            ],
          );
        }
        return const Text('Unknown bloc state');
      },
    ));
  }
}
