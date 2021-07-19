import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/nav_bar.dart';
import '../../../../injection_container.dart' as di;
import '../../../recipe/domain/entities/recipe.dart';
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

class HomePageContent extends StatelessWidget {
  const HomePageContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          BlocBuilder<HomeBloc, HomeState>(
            builder: (context, state) {
              if (state is HomeInProgress) {
                if (state.recipes.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                return _HomeGrid(recipes: state.recipes);
              }
              if (state is HomeSuccess) {
                if (state.recipes.isEmpty) {
                  return const Center(
                    child: Text('No recipes found'),
                  );
                }
                return _HomeGrid(recipes: state.recipes);
              }
              if (state is HomeFailure) {
                return const Center(
                  child: Text('Failed to load recipes'),
                );
              }
              return const Center(
                child: Text('ERROR: Unknown bloc state'),
              );
            },
          ),
          BlocBuilder<HomeBloc, HomeState>(
            builder: (context, state) {
              return NavBar(
                loading: state is HomeInProgress && state.recipes.isNotEmpty,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeGrid extends StatefulWidget {
  final List<Recipe> recipes;

  const _HomeGrid({
    Key? key,
    required this.recipes,
  }) : super(key: key);

  @override
  __HomeGridState createState() => __HomeGridState();
}

class __HomeGridState extends State<_HomeGrid> {
  static bool _isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.width < 800;
  static bool _isMediumScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= 800 &&
      MediaQuery.of(context).size.width <= 1200;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      cacheExtent: 7000,
      padding: const EdgeInsets.only(
        top: 64,
        left: 4,
        right: 4,
      ),
      crossAxisCount: _isSmallScreen(context)
          ? 1
          : _isMediumScreen(context)
              ? 3
              : 4,
      childAspectRatio: 3 / 2,
      children: widget.recipes
          .map(
            (recipe) => RecipeCard(recipe: recipe),
          )
          .toList(),
    );
  }
}
