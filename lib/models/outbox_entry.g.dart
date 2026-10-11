// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OutboxEntryAdapter extends TypeAdapter<OutboxEntry> {
  @override
  final int typeId = 8;

  @override
  OutboxEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OutboxEntry(
      table: fields[0] as String,
      rowId: fields[1] as String,
      opIndex: fields[2] as int,
      payload: (fields[3] as Map?)?.cast<String, dynamic>(),
      baseUpdatedAt: fields[6] as String?,
      attempts: fields[4] as int,
      queuedAt: fields[5] as DateTime?,
      failed: fields[7] == null ? false : fields[7] as bool,
      lastError: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, OutboxEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.table)
      ..writeByte(1)
      ..write(obj.rowId)
      ..writeByte(2)
      ..write(obj.opIndex)
      ..writeByte(3)
      ..write(obj.payload)
      ..writeByte(4)
      ..write(obj.attempts)
      ..writeByte(5)
      ..write(obj.queuedAt)
      ..writeByte(6)
      ..write(obj.baseUpdatedAt)
      ..writeByte(7)
      ..write(obj.failed)
      ..writeByte(8)
      ..write(obj.lastError);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
