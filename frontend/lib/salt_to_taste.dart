import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';

import 'features/home/presentation/pages/home_page.dart';
import 'features/recipe/presentation/pages/recipe_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';

class SaltToTaste extends StatefulWidget {
  SaltToTaste({Key? key}) : super(key: key);

  @override
  _SaltToTasteState createState() => _SaltToTasteState();
}

class _SaltToTasteState extends State<SaltToTaste> {
  @override
  void initState() {
    super.initState();
    Flurorouter.setupRouter();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salt To Taste',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      onGenerateRoute: Flurorouter.router.generator,
    );
  }
}

class Flurorouter {
  static final FluroRouter router = FluroRouter();

  static final Handler _homePageHandler = Handler(
    handlerFunc: (context, parameters) => const HomePage(),
  );

  static final Handler _recipePageHandler = Handler(
    handlerFunc: (context, params) => RecipePage(
      titleSanitized: params['titleSanitized']![0],
    ),
  );

  static final Handler _settingsPageHandler = Handler(
    handlerFunc: (context, parameters) => const SettingsPage(),
  );

  static void setupRouter() {
    const transitionType = TransitionType.none;

    router.define(
      '/',
      handler: _homePageHandler,
      transitionType: transitionType,
    );
    router.define(
      '/recipe/:titleSanitized',
      handler: _recipePageHandler,
      transitionType: transitionType,
    );
    router.define(
      '/settings',
      handler: _settingsPageHandler,
      transitionType: transitionType,
    );
  }
}
