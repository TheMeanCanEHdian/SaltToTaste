import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/setting.dart';
import '../repositories/settings_repository.dart';

class GetSettings {
  final SettingsRepository repository;

  GetSettings({required this.repository});

  Future<Either<Failure, List<Setting>>> call() async {
    return await repository.getSettings();
  }
}
