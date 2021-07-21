import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

import '../../../../core/widgets/nav_bar.dart';
import '../../../../injection_container.dart' as di;
import '../bloc/settings_bloc.dart';
import '../bloc/settings_update_bloc.dart';
import '../widgets/settings_section_heading.dart';
import '../widgets/settings_text_field.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => di.sl<SettingsUpdateBloc>(),
      child: const SettingsPageContent(),
    );
  }
}

class SettingsPageContent extends StatelessWidget {
  const SettingsPageContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final _formKey = GlobalKey<FormBuilderState>();

    return Scaffold(
      body: Stack(
        children: [
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              if (settingsState is SettingsInProgress) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              if (settingsState is SettingsSuccess) {
                return Padding(
                  padding: const EdgeInsets.only(
                    top: 64,
                    left: 4,
                    right: 4,
                  ),
                  child: DefaultTabController(
                    length: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: const [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey,
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TabBar(
                                isScrollable: true,
                                indicatorColor: Color.fromRGBO(145, 0, 6, 1),
                                labelColor: Color.fromRGBO(145, 0, 6, 1),
                                tabs: [
                                  Tab(
                                    child: Text(
                                      'Third Party',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TabBarView(
                              children: [
                                FormBuilder(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SettingsSectionHeading(),
                                      SettingsTextField(
                                        title: 'Edamam ID',
                                        formFieldName: 'edamam_id',
                                        initialValue: settingsState.settingsList
                                            .firstWhere(
                                              (setting) =>
                                                  setting.name == 'edamam_id',
                                            )
                                            .value,
                                      ),
                                      const SizedBox(height: 8),
                                      SettingsTextField(
                                        title: 'Edamam Key',
                                        formFieldName: 'edamam_key',
                                        initialValue: settingsState.settingsList
                                            .firstWhere(
                                              (setting) =>
                                                  setting.name == 'edamam_key',
                                            )
                                            .value,
                                      ),
                                      Row(
                                        children: [
                                          ElevatedButton(
                                            onPressed: () {
                                              _formKey.currentState?.save();
                                              if (_formKey
                                                      .currentState?.value !=
                                                  null) {
                                                context
                                                    .read<SettingsUpdateBloc>()
                                                    .add(
                                                      SettingsUpdateTrigger(
                                                        currentSettings:
                                                            settingsState
                                                                .settingsList,
                                                        settingsMap: _formKey
                                                            .currentState!
                                                            .value,
                                                      ),
                                                    );
                                              }
                                            },
                                            child: BlocBuilder<
                                                SettingsUpdateBloc,
                                                SettingsUpdateState>(
                                              builder: (context, state) {
                                                if (state
                                                    is SettingsUpdateInProgress) {
                                                  return const CircularProgressIndicator(
                                                    color: Colors.white,
                                                  );
                                                }
                                                return const Text('SAVE');
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (settingsState is SettingsFailure) {
                return const Center(
                  child: Text('Failed to load settings'),
                );
              }
              return const Center(
                child: Text('Unknown Bloc state'),
              );
            },
          ),
          const NavBar(),
        ],
      ),
    );
  }
}
