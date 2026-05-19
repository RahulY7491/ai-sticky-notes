import '../../domain/entities/brain_dump_result.dart';
import '../../domain/repositories/brain_dump_repository.dart';
import '../../services/ai_service.dart';

/// Production implementation: delegates to [AiService] (Gemini).
class BrainDumpRepositoryImpl implements BrainDumpRepository {
  const BrainDumpRepositoryImpl();

  @override
  Future<BrainDumpResult> organize(String rawText) {
    return AiService.instance.organizeBrainDump(rawText, DateTime.now());
  }
}
