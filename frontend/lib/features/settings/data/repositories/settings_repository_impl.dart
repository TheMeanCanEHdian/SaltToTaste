import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/setting.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_data_source.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsDataSource dataSource;

  SettingsRepositoryImpl({
    required this.dataSource,
  });

  @override
  Future<Either<Failure, List<Setting>>> getSettings() async {
    try {
      final settingsList = await dataSource.getSettings();
      return Right(settingsList);
    } catch (exception) {
      //TODO: Customize failures
      return Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateSetting({
    required String section,
    required String name,
    required String value,
  }) async {
    try {
      final result = await dataSource.updateSetting(
        section: section,
        name: name,
        value: value,
      );
      return Right(result);
    } catch (exception) {
      //TODO: Customize failures
      return Left(UnknownFailure());
    }
  }
}
