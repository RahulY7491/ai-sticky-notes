# Architecture (MVP)

## Layers

| Layer | Path | Responsibility |
|-------|------|----------------|
| **Domain** | `lib/domain/` | Entities + repository **interfaces** (no Flutter, no IO) |
| **Data** | `lib/data/` | Repository implementations, maps to `services/` (Gemini, Hive) |
| **Features** | `lib/features/<name>/` | Use cases + feature UI (`application/`, `presentation/`) |
| **Services** | `lib/services/` | Platform + third-party adapters (singletons where appropriate) |
| **Presentation (legacy)** | `lib/screens/`, `lib/widgets/` | App shell, shared widgets; migrate gradually into `features/` |

## Dependency rule

- `domain` → nothing inside the app
- `data` → `domain`, `services`
- `features` → `domain`, `data` (use cases); `presentation` may use `provider`, `screens` for shared providers
- `services` → `domain` entities only when returning structured AI results (e.g. `BrainDumpResult`)

## MVP feature: Brain Dump

1. `OrganizeBrainDumpUseCase` → `BrainDumpRepository.organize()`
2. `BrainDumpRepositoryImpl` → `AiService.organizeBrainDump()`
3. `BrainDumpScreen` → use case + `UsageGate` + `NotesProvider`

## Auto-Action Engine (editor)

- `AssistantSuggestionBar` surfaces AI chips from existing `analyzeNoteContext` flow.
- **Apply all** sets reminder + appends `- [ ]` tasks in one action (`NoteEditorScreen._applyAllActions`).
