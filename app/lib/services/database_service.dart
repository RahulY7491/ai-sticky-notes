import 'package:hive_flutter/hive_flutter.dart';

import '../models/note.dart';

class DatabaseService {
  DatabaseService._internal();

  static final DatabaseService instance = DatabaseService._internal();

  static const _boxName = 'notes';

  Box? _box;

  Future<Box> get _openBox async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  Future<Note> createNote(Note note) async {
    final box = await _openBox;
    // box.add() auto-assigns a valid Hive integer key (no range issues)
    final key = await box.add(note.toMap());
    return note.copyWith(id: key);
  }

  Future<void> updateNote(Note note) async {
    if (note.id == null) throw ArgumentError('Note id required for update');
    final box = await _openBox;
    await box.put(note.id, note.toMap());
  }

  Future<void> deleteNote(int id) async {
    final box = await _openBox;
    await box.delete(id);
  }

  Future<List<Note>> getAllNotes() async {
    try {
      final box = await _openBox;
      final list = <Note>[];
      for (final entry in box.toMap().entries) {
        try {
          final map = Map<String, Object?>.from(entry.value as Map);
          map['id'] = entry.key;
          list.add(Note.fromMap(map));
        } catch (_) {}
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }
}
