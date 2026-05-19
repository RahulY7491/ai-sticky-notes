import '../entities/brain_dump_result.dart';

/// Abstraction for turning raw brain-dump text into a structured note (testable / swappable).
abstract class BrainDumpRepository {
  Future<BrainDumpResult> organize(String rawText);
}
