import '../../../domain/entities/brain_dump_result.dart';
import '../../../domain/repositories/brain_dump_repository.dart';

/// Single-responsibility use case: organize raw text into a structured result.
class OrganizeBrainDumpUseCase {
  OrganizeBrainDumpUseCase(this._repository);

  final BrainDumpRepository _repository;

  Future<BrainDumpResult> call(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return Future.value(const BrainDumpResult(title: '', bullets: [], tasks: []));
    }
    return _repository.organize(trimmed);
  }
}
