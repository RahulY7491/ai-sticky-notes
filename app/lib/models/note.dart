import 'package:flutter/material.dart';

class Note {
  final int? id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reminderTime;
  final int colorIndex;

  const Note({
    this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.reminderTime,
    this.colorIndex = 0,
  });

  Note copyWith({
    int? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reminderTime,
    int? colorIndex,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderTime: reminderTime ?? this.reminderTime,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'reminder_time': reminderTime?.toIso8601String(),
      'color_index': colorIndex,
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      reminderTime: map['reminder_time'] != null
          ? DateTime.parse(map['reminder_time'] as String)
          : null,
      colorIndex: (map['color_index'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.reminderTime == reminderTime &&
        other.colorIndex == colorIndex;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      content.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      reminderTime.hashCode ^
      colorIndex.hashCode;
}

/// Google Keep–style color palette for notes.
class NoteColors {
  NoteColors._();

  static const List<Color> light = [
    Color(0x00000000), // 0 = default (transparent → surface)
    Color(0xFFF28B82), // 1 = coral
    Color(0xFFFBBC04), // 2 = sand
    Color(0xFFFFF475), // 3 = lemon
    Color(0xFFCCFF90), // 4 = sage
    Color(0xFFA7FFEB), // 5 = mint
    Color(0xFFCBF0F8), // 6 = sky
    Color(0xFFD7AEFB), // 7 = lavender
    Color(0xFFFDCFE8), // 8 = rose
  ];

  static const List<Color> dark = [
    Color(0x00000000), // 0 = default
    Color(0xFF5C2B29), // 1 = coral
    Color(0xFF614A19), // 2 = sand
    Color(0xFF635D19), // 3 = lemon
    Color(0xFF345920), // 4 = sage
    Color(0xFF16504B), // 5 = mint
    Color(0xFF2D555E), // 6 = sky
    Color(0xFF42275E), // 7 = lavender
    Color(0xFF5B2245), // 8 = rose
  ];

  static Color of(int index, Brightness brightness) {
    final palette = brightness == Brightness.light ? light : dark;
    if (index <= 0 || index >= palette.length) return palette[0];
    return palette[index];
  }

  static int get count => light.length;
}
