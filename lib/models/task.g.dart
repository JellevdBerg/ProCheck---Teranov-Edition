// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 1;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      title: fields[1] as String,
      createdAt: fields[6] as DateTime,
      isChecked: fields[2] as bool,
      notes: fields[3] as String?,
      subtasks: (fields[4] as List?)?.cast<Subtask>(),
      projectId: fields[5] as String?,
      templateId: fields[7] as String?,
      dueDate: fields[8] as DateTime?,
      dueDateEnd: fields[13] as DateTime?,
      sortOrder: fields[9] == null ? 0.0 : fields[9] as double?,
      priorityIndex: fields[10] == null ? 0 : fields[10] as int,
      attachments:
          fields[11] == null ? [] : (fields[11] as List?)?.cast<Attachment>(),
      completedAt: fields[15] as DateTime?,
      ownerId: fields[16] == null ? '' : fields[16] as String,
      assigneeId: fields[17] as String?,
      departmentId: fields[18] == null ? '' : fields[18] as String,
    )..recurrenceIndex = fields[14] == null ? 0 : fields[14] as int;
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.isChecked)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.subtasks)
      ..writeByte(5)
      ..write(obj.projectId)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.templateId)
      ..writeByte(8)
      ..write(obj.dueDate)
      ..writeByte(13)
      ..write(obj.dueDateEnd)
      ..writeByte(9)
      ..write(obj.sortOrder)
      ..writeByte(10)
      ..write(obj.priorityIndex)
      ..writeByte(11)
      ..write(obj.attachments)
      ..writeByte(14)
      ..write(obj.recurrenceIndex)
      ..writeByte(15)
      ..write(obj.completedAt)
      ..writeByte(16)
      ..write(obj.ownerId)
      ..writeByte(17)
      ..write(obj.assigneeId)
      ..writeByte(18)
      ..write(obj.departmentId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
