import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/setting.dart';

abstract class SettingsRepository {
  Future<Either<Failure, List<Setting>>> getSettings();
  Future<Either<Failure, bool>> updateSetting({
    required String section,
    required String name,
    required String value,
  });
}
