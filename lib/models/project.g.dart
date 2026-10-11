// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProjectAdapter extends TypeAdapter<Project> {
  @override
  final int typeId = 2;

  @override
  Project read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Project(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAt: fields[2] as DateTime,
      lastOpenedAt: fields[3] as DateTime?,
      colorIndex: fields[4] == null ? 0 : fields[4] as int,
      archived: fields[5] == null ? false : fields[5] as bool,
      favorite: fields[6] == null ? false : fields[6] as bool,
      activityLog:
          fields[7] == null ? [] : (fields[7] as List?)?.cast<ActivityEntry>(),
      comments:
          fields[8] == null ? [] : (fields[8] as List?)?.cast<ProjectComment>(),
      ownerId: fields[10] == null ? '' : fields[10] as String,
      departmentId: fields[11] == null ? '' : fields[11] as String,
      updatedAt: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Project obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.lastOpenedAt)
      ..writeByte(4)
      ..write(obj.colorIndex)
      ..writeByte(5)
      ..write(obj.archived)
      ..writeByte(6)
      ..write(obj.favorite)
      ..writeByte(7)
      ..write(obj.activityLog)
      ..writeByte(8)
      ..write(obj.comments)
      ..writeByte(10)
      ..write(obj.ownerId)
      ..writeByte(11)
      ..write(obj.departmentId)
      ..writeByte(12)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
