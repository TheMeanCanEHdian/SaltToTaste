import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../repositories/settings_repository.dart';

class UpdateSetting {
  final SettingsRepository repository;

  UpdateSetting({required this.repository});

  Future<Either<Failure, bool>> call({
    required String section,
    required String name,
    required String value,
  }) async {
    return await repository.updateSetting(
      section: section,
      name: name,
      value: value,
    );
  }
}
