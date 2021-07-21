import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'injection_container.dart' as di;
import 'salt_to_taste.dart';

void main() async {
  await di.init();
  runApp(
    BlocProvider(
      create: (context) => di.sl<SettingsBloc>()..add(SettingsFetch()),
      child: SaltToTaste(),
    ),
  );
}
