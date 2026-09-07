// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SyncQueueEntriesTable extends SyncQueueEntries
    with TableInfo<$SyncQueueEntriesTable, SyncQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entiteMeta = const VerificationMeta('entite');
  @override
  late final GeneratedColumn<String> entite = GeneratedColumn<String>(
    'entite',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tentativesMeta = const VerificationMeta(
    'tentatives',
  );
  @override
  late final GeneratedColumn<int> tentatives = GeneratedColumn<int>(
    'tentatives',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statutMeta = const VerificationMeta('statut');
  @override
  late final GeneratedColumn<String> statut = GeneratedColumn<String>(
    'statut',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en_attente'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entite,
    operation,
    payload,
    tentatives,
    statut,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entite')) {
      context.handle(
        _entiteMeta,
        entite.isAcceptableOrUnknown(data['entite']!, _entiteMeta),
      );
    } else if (isInserting) {
      context.missing(_entiteMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('tentatives')) {
      context.handle(
        _tentativesMeta,
        tentatives.isAcceptableOrUnknown(data['tentatives']!, _tentativesMeta),
      );
    }
    if (data.containsKey('statut')) {
      context.handle(
        _statutMeta,
        statut.isAcceptableOrUnknown(data['statut']!, _statutMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entite: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entite'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      tentatives: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tentatives'],
      )!,
      statut: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}statut'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncQueueEntriesTable createAlias(String alias) {
    return $SyncQueueEntriesTable(attachedDatabase, alias);
  }
}

class SyncQueueEntry extends DataClass implements Insertable<SyncQueueEntry> {
  final String id;
  final String entite;
  final String operation;
  final String payload;
  final int tentatives;
  final String statut;
  final DateTime createdAt;
  const SyncQueueEntry({
    required this.id,
    required this.entite,
    required this.operation,
    required this.payload,
    required this.tentatives,
    required this.statut,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entite'] = Variable<String>(entite);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['tentatives'] = Variable<int>(tentatives);
    map['statut'] = Variable<String>(statut);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncQueueEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueEntriesCompanion(
      id: Value(id),
      entite: Value(entite),
      operation: Value(operation),
      payload: Value(payload),
      tentatives: Value(tentatives),
      statut: Value(statut),
      createdAt: Value(createdAt),
    );
  }

  factory SyncQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueEntry(
      id: serializer.fromJson<String>(json['id']),
      entite: serializer.fromJson<String>(json['entite']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      tentatives: serializer.fromJson<int>(json['tentatives']),
      statut: serializer.fromJson<String>(json['statut']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entite': serializer.toJson<String>(entite),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'tentatives': serializer.toJson<int>(tentatives),
      'statut': serializer.toJson<String>(statut),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncQueueEntry copyWith({
    String? id,
    String? entite,
    String? operation,
    String? payload,
    int? tentatives,
    String? statut,
    DateTime? createdAt,
  }) => SyncQueueEntry(
    id: id ?? this.id,
    entite: entite ?? this.entite,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    tentatives: tentatives ?? this.tentatives,
    statut: statut ?? this.statut,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncQueueEntry copyWithCompanion(SyncQueueEntriesCompanion data) {
    return SyncQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      entite: data.entite.present ? data.entite.value : this.entite,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      tentatives: data.tentatives.present
          ? data.tentatives.value
          : this.tentatives,
      statut: data.statut.present ? data.statut.value : this.statut,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueEntry(')
          ..write('id: $id, ')
          ..write('entite: $entite, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('tentatives: $tentatives, ')
          ..write('statut: $statut, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entite,
    operation,
    payload,
    tentatives,
    statut,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueEntry &&
          other.id == this.id &&
          other.entite == this.entite &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.tentatives == this.tentatives &&
          other.statut == this.statut &&
          other.createdAt == this.createdAt);
}

class SyncQueueEntriesCompanion extends UpdateCompanion<SyncQueueEntry> {
  final Value<String> id;
  final Value<String> entite;
  final Value<String> operation;
  final Value<String> payload;
  final Value<int> tentatives;
  final Value<String> statut;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncQueueEntriesCompanion({
    this.id = const Value.absent(),
    this.entite = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.tentatives = const Value.absent(),
    this.statut = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueEntriesCompanion.insert({
    required String id,
    required String entite,
    required String operation,
    required String payload,
    this.tentatives = const Value.absent(),
    this.statut = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entite = Value(entite),
       operation = Value(operation),
       payload = Value(payload);
  static Insertable<SyncQueueEntry> custom({
    Expression<String>? id,
    Expression<String>? entite,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<int>? tentatives,
    Expression<String>? statut,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entite != null) 'entite': entite,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (tentatives != null) 'tentatives': tentatives,
      if (statut != null) 'statut': statut,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? entite,
    Value<String>? operation,
    Value<String>? payload,
    Value<int>? tentatives,
    Value<String>? statut,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncQueueEntriesCompanion(
      id: id ?? this.id,
      entite: entite ?? this.entite,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      tentatives: tentatives ?? this.tentatives,
      statut: statut ?? this.statut,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entite.present) {
      map['entite'] = Variable<String>(entite.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (tentatives.present) {
      map['tentatives'] = Variable<int>(tentatives.value);
    }
    if (statut.present) {
      map['statut'] = Variable<String>(statut.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueEntriesCompanion(')
          ..write('id: $id, ')
          ..write('entite: $entite, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('tentatives: $tentatives, ')
          ..write('statut: $statut, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReferentielCacheEntriesTable extends ReferentielCacheEntries
    with TableInfo<$ReferentielCacheEntriesTable, ReferentielCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReferentielCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cleMeta = const VerificationMeta('cle');
  @override
  late final GeneratedColumn<String> cle = GeneratedColumn<String>(
    'cle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _misAJourLeMeta = const VerificationMeta(
    'misAJourLe',
  );
  @override
  late final GeneratedColumn<DateTime> misAJourLe = GeneratedColumn<DateTime>(
    'mis_a_jour_le',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [type, cle, payload, misAJourLe];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'referentiel_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReferentielCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('cle')) {
      context.handle(
        _cleMeta,
        cle.isAcceptableOrUnknown(data['cle']!, _cleMeta),
      );
    } else if (isInserting) {
      context.missing(_cleMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('mis_a_jour_le')) {
      context.handle(
        _misAJourLeMeta,
        misAJourLe.isAcceptableOrUnknown(
          data['mis_a_jour_le']!,
          _misAJourLeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {type, cle};
  @override
  ReferentielCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReferentielCacheEntry(
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      cle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cle'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      misAJourLe: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}mis_a_jour_le'],
      )!,
    );
  }

  @override
  $ReferentielCacheEntriesTable createAlias(String alias) {
    return $ReferentielCacheEntriesTable(attachedDatabase, alias);
  }
}

class ReferentielCacheEntry extends DataClass
    implements Insertable<ReferentielCacheEntry> {
  final String type;
  final String cle;
  final String payload;
  final DateTime misAJourLe;
  const ReferentielCacheEntry({
    required this.type,
    required this.cle,
    required this.payload,
    required this.misAJourLe,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['type'] = Variable<String>(type);
    map['cle'] = Variable<String>(cle);
    map['payload'] = Variable<String>(payload);
    map['mis_a_jour_le'] = Variable<DateTime>(misAJourLe);
    return map;
  }

  ReferentielCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReferentielCacheEntriesCompanion(
      type: Value(type),
      cle: Value(cle),
      payload: Value(payload),
      misAJourLe: Value(misAJourLe),
    );
  }

  factory ReferentielCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReferentielCacheEntry(
      type: serializer.fromJson<String>(json['type']),
      cle: serializer.fromJson<String>(json['cle']),
      payload: serializer.fromJson<String>(json['payload']),
      misAJourLe: serializer.fromJson<DateTime>(json['misAJourLe']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'type': serializer.toJson<String>(type),
      'cle': serializer.toJson<String>(cle),
      'payload': serializer.toJson<String>(payload),
      'misAJourLe': serializer.toJson<DateTime>(misAJourLe),
    };
  }

  ReferentielCacheEntry copyWith({
    String? type,
    String? cle,
    String? payload,
    DateTime? misAJourLe,
  }) => ReferentielCacheEntry(
    type: type ?? this.type,
    cle: cle ?? this.cle,
    payload: payload ?? this.payload,
    misAJourLe: misAJourLe ?? this.misAJourLe,
  );
  ReferentielCacheEntry copyWithCompanion(
    ReferentielCacheEntriesCompanion data,
  ) {
    return ReferentielCacheEntry(
      type: data.type.present ? data.type.value : this.type,
      cle: data.cle.present ? data.cle.value : this.cle,
      payload: data.payload.present ? data.payload.value : this.payload,
      misAJourLe: data.misAJourLe.present
          ? data.misAJourLe.value
          : this.misAJourLe,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReferentielCacheEntry(')
          ..write('type: $type, ')
          ..write('cle: $cle, ')
          ..write('payload: $payload, ')
          ..write('misAJourLe: $misAJourLe')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(type, cle, payload, misAJourLe);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReferentielCacheEntry &&
          other.type == this.type &&
          other.cle == this.cle &&
          other.payload == this.payload &&
          other.misAJourLe == this.misAJourLe);
}

class ReferentielCacheEntriesCompanion
    extends UpdateCompanion<ReferentielCacheEntry> {
  final Value<String> type;
  final Value<String> cle;
  final Value<String> payload;
  final Value<DateTime> misAJourLe;
  final Value<int> rowid;
  const ReferentielCacheEntriesCompanion({
    this.type = const Value.absent(),
    this.cle = const Value.absent(),
    this.payload = const Value.absent(),
    this.misAJourLe = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReferentielCacheEntriesCompanion.insert({
    required String type,
    required String cle,
    required String payload,
    this.misAJourLe = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : type = Value(type),
       cle = Value(cle),
       payload = Value(payload);
  static Insertable<ReferentielCacheEntry> custom({
    Expression<String>? type,
    Expression<String>? cle,
    Expression<String>? payload,
    Expression<DateTime>? misAJourLe,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (type != null) 'type': type,
      if (cle != null) 'cle': cle,
      if (payload != null) 'payload': payload,
      if (misAJourLe != null) 'mis_a_jour_le': misAJourLe,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReferentielCacheEntriesCompanion copyWith({
    Value<String>? type,
    Value<String>? cle,
    Value<String>? payload,
    Value<DateTime>? misAJourLe,
    Value<int>? rowid,
  }) {
    return ReferentielCacheEntriesCompanion(
      type: type ?? this.type,
      cle: cle ?? this.cle,
      payload: payload ?? this.payload,
      misAJourLe: misAJourLe ?? this.misAJourLe,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (cle.present) {
      map['cle'] = Variable<String>(cle.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (misAJourLe.present) {
      map['mis_a_jour_le'] = Variable<DateTime>(misAJourLe.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReferentielCacheEntriesCompanion(')
          ..write('type: $type, ')
          ..write('cle: $cle, ')
          ..write('payload: $payload, ')
          ..write('misAJourLe: $misAJourLe, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _domaineMeta = const VerificationMeta(
    'domaine',
  );
  @override
  late final GeneratedColumn<String> domaine = GeneratedColumn<String>(
    'domaine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cleMeta = const VerificationMeta('cle');
  @override
  late final GeneratedColumn<String> cle = GeneratedColumn<String>(
    'cle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _misAJourLeMeta = const VerificationMeta(
    'misAJourLe',
  );
  @override
  late final GeneratedColumn<DateTime> misAJourLe = GeneratedColumn<DateTime>(
    'mis_a_jour_le',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    domaine,
    type,
    cle,
    payload,
    misAJourLe,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('domaine')) {
      context.handle(
        _domaineMeta,
        domaine.isAcceptableOrUnknown(data['domaine']!, _domaineMeta),
      );
    } else if (isInserting) {
      context.missing(_domaineMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('cle')) {
      context.handle(
        _cleMeta,
        cle.isAcceptableOrUnknown(data['cle']!, _cleMeta),
      );
    } else if (isInserting) {
      context.missing(_cleMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('mis_a_jour_le')) {
      context.handle(
        _misAJourLeMeta,
        misAJourLe.isAcceptableOrUnknown(
          data['mis_a_jour_le']!,
          _misAJourLeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {domaine, type, cle};
  @override
  CacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntry(
      domaine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domaine'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      cle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cle'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      misAJourLe: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}mis_a_jour_le'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntry extends DataClass implements Insertable<CacheEntry> {
  final String domaine;
  final String type;
  final String cle;
  final String payload;
  final DateTime misAJourLe;
  const CacheEntry({
    required this.domaine,
    required this.type,
    required this.cle,
    required this.payload,
    required this.misAJourLe,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['domaine'] = Variable<String>(domaine);
    map['type'] = Variable<String>(type);
    map['cle'] = Variable<String>(cle);
    map['payload'] = Variable<String>(payload);
    map['mis_a_jour_le'] = Variable<DateTime>(misAJourLe);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      domaine: Value(domaine),
      type: Value(type),
      cle: Value(cle),
      payload: Value(payload),
      misAJourLe: Value(misAJourLe),
    );
  }

  factory CacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntry(
      domaine: serializer.fromJson<String>(json['domaine']),
      type: serializer.fromJson<String>(json['type']),
      cle: serializer.fromJson<String>(json['cle']),
      payload: serializer.fromJson<String>(json['payload']),
      misAJourLe: serializer.fromJson<DateTime>(json['misAJourLe']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'domaine': serializer.toJson<String>(domaine),
      'type': serializer.toJson<String>(type),
      'cle': serializer.toJson<String>(cle),
      'payload': serializer.toJson<String>(payload),
      'misAJourLe': serializer.toJson<DateTime>(misAJourLe),
    };
  }

  CacheEntry copyWith({
    String? domaine,
    String? type,
    String? cle,
    String? payload,
    DateTime? misAJourLe,
  }) => CacheEntry(
    domaine: domaine ?? this.domaine,
    type: type ?? this.type,
    cle: cle ?? this.cle,
    payload: payload ?? this.payload,
    misAJourLe: misAJourLe ?? this.misAJourLe,
  );
  CacheEntry copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntry(
      domaine: data.domaine.present ? data.domaine.value : this.domaine,
      type: data.type.present ? data.type.value : this.type,
      cle: data.cle.present ? data.cle.value : this.cle,
      payload: data.payload.present ? data.payload.value : this.payload,
      misAJourLe: data.misAJourLe.present
          ? data.misAJourLe.value
          : this.misAJourLe,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntry(')
          ..write('domaine: $domaine, ')
          ..write('type: $type, ')
          ..write('cle: $cle, ')
          ..write('payload: $payload, ')
          ..write('misAJourLe: $misAJourLe')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(domaine, type, cle, payload, misAJourLe);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntry &&
          other.domaine == this.domaine &&
          other.type == this.type &&
          other.cle == this.cle &&
          other.payload == this.payload &&
          other.misAJourLe == this.misAJourLe);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntry> {
  final Value<String> domaine;
  final Value<String> type;
  final Value<String> cle;
  final Value<String> payload;
  final Value<DateTime> misAJourLe;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.domaine = const Value.absent(),
    this.type = const Value.absent(),
    this.cle = const Value.absent(),
    this.payload = const Value.absent(),
    this.misAJourLe = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String domaine,
    required String type,
    required String cle,
    required String payload,
    this.misAJourLe = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : domaine = Value(domaine),
       type = Value(type),
       cle = Value(cle),
       payload = Value(payload);
  static Insertable<CacheEntry> custom({
    Expression<String>? domaine,
    Expression<String>? type,
    Expression<String>? cle,
    Expression<String>? payload,
    Expression<DateTime>? misAJourLe,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (domaine != null) 'domaine': domaine,
      if (type != null) 'type': type,
      if (cle != null) 'cle': cle,
      if (payload != null) 'payload': payload,
      if (misAJourLe != null) 'mis_a_jour_le': misAJourLe,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? domaine,
    Value<String>? type,
    Value<String>? cle,
    Value<String>? payload,
    Value<DateTime>? misAJourLe,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      domaine: domaine ?? this.domaine,
      type: type ?? this.type,
      cle: cle ?? this.cle,
      payload: payload ?? this.payload,
      misAJourLe: misAJourLe ?? this.misAJourLe,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (domaine.present) {
      map['domaine'] = Variable<String>(domaine.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (cle.present) {
      map['cle'] = Variable<String>(cle.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (misAJourLe.present) {
      map['mis_a_jour_le'] = Variable<DateTime>(misAJourLe.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('domaine: $domaine, ')
          ..write('type: $type, ')
          ..write('cle: $cle, ')
          ..write('payload: $payload, ')
          ..write('misAJourLe: $misAJourLe, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SyncQueueEntriesTable syncQueueEntries = $SyncQueueEntriesTable(
    this,
  );
  late final $ReferentielCacheEntriesTable referentielCacheEntries =
      $ReferentielCacheEntriesTable(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    syncQueueEntries,
    referentielCacheEntries,
    cacheEntries,
  ];
}

typedef $$SyncQueueEntriesTableCreateCompanionBuilder =
    SyncQueueEntriesCompanion Function({
      required String id,
      required String entite,
      required String operation,
      required String payload,
      Value<int> tentatives,
      Value<String> statut,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SyncQueueEntriesTableUpdateCompanionBuilder =
    SyncQueueEntriesCompanion Function({
      Value<String> id,
      Value<String> entite,
      Value<String> operation,
      Value<String> payload,
      Value<int> tentatives,
      Value<String> statut,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SyncQueueEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueEntriesTable> {
  $$SyncQueueEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entite => $composableBuilder(
    column: $table.entite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tentatives => $composableBuilder(
    column: $table.tentatives,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statut => $composableBuilder(
    column: $table.statut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueEntriesTable> {
  $$SyncQueueEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entite => $composableBuilder(
    column: $table.entite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tentatives => $composableBuilder(
    column: $table.tentatives,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statut => $composableBuilder(
    column: $table.statut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueEntriesTable> {
  $$SyncQueueEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entite =>
      $composableBuilder(column: $table.entite, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get tentatives => $composableBuilder(
    column: $table.tentatives,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statut =>
      $composableBuilder(column: $table.statut, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncQueueEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueEntriesTable,
          SyncQueueEntry,
          $$SyncQueueEntriesTableFilterComposer,
          $$SyncQueueEntriesTableOrderingComposer,
          $$SyncQueueEntriesTableAnnotationComposer,
          $$SyncQueueEntriesTableCreateCompanionBuilder,
          $$SyncQueueEntriesTableUpdateCompanionBuilder,
          (
            SyncQueueEntry,
            BaseReferences<
              _$AppDatabase,
              $SyncQueueEntriesTable,
              SyncQueueEntry
            >,
          ),
          SyncQueueEntry,
          PrefetchHooks Function()
        > {
  $$SyncQueueEntriesTableTableManager(
    _$AppDatabase db,
    $SyncQueueEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entite = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> tentatives = const Value.absent(),
                Value<String> statut = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueEntriesCompanion(
                id: id,
                entite: entite,
                operation: operation,
                payload: payload,
                tentatives: tentatives,
                statut: statut,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entite,
                required String operation,
                required String payload,
                Value<int> tentatives = const Value.absent(),
                Value<String> statut = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueEntriesCompanion.insert(
                id: id,
                entite: entite,
                operation: operation,
                payload: payload,
                tentatives: tentatives,
                statut: statut,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueEntriesTable,
      SyncQueueEntry,
      $$SyncQueueEntriesTableFilterComposer,
      $$SyncQueueEntriesTableOrderingComposer,
      $$SyncQueueEntriesTableAnnotationComposer,
      $$SyncQueueEntriesTableCreateCompanionBuilder,
      $$SyncQueueEntriesTableUpdateCompanionBuilder,
      (
        SyncQueueEntry,
        BaseReferences<_$AppDatabase, $SyncQueueEntriesTable, SyncQueueEntry>,
      ),
      SyncQueueEntry,
      PrefetchHooks Function()
    >;
typedef $$ReferentielCacheEntriesTableCreateCompanionBuilder =
    ReferentielCacheEntriesCompanion Function({
      required String type,
      required String cle,
      required String payload,
      Value<DateTime> misAJourLe,
      Value<int> rowid,
    });
typedef $$ReferentielCacheEntriesTableUpdateCompanionBuilder =
    ReferentielCacheEntriesCompanion Function({
      Value<String> type,
      Value<String> cle,
      Value<String> payload,
      Value<DateTime> misAJourLe,
      Value<int> rowid,
    });

class $$ReferentielCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ReferentielCacheEntriesTable> {
  $$ReferentielCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cle => $composableBuilder(
    column: $table.cle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReferentielCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReferentielCacheEntriesTable> {
  $$ReferentielCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cle => $composableBuilder(
    column: $table.cle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReferentielCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReferentielCacheEntriesTable> {
  $$ReferentielCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get cle =>
      $composableBuilder(column: $table.cle, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => column,
  );
}

class $$ReferentielCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReferentielCacheEntriesTable,
          ReferentielCacheEntry,
          $$ReferentielCacheEntriesTableFilterComposer,
          $$ReferentielCacheEntriesTableOrderingComposer,
          $$ReferentielCacheEntriesTableAnnotationComposer,
          $$ReferentielCacheEntriesTableCreateCompanionBuilder,
          $$ReferentielCacheEntriesTableUpdateCompanionBuilder,
          (
            ReferentielCacheEntry,
            BaseReferences<
              _$AppDatabase,
              $ReferentielCacheEntriesTable,
              ReferentielCacheEntry
            >,
          ),
          ReferentielCacheEntry,
          PrefetchHooks Function()
        > {
  $$ReferentielCacheEntriesTableTableManager(
    _$AppDatabase db,
    $ReferentielCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReferentielCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReferentielCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReferentielCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> type = const Value.absent(),
                Value<String> cle = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> misAJourLe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReferentielCacheEntriesCompanion(
                type: type,
                cle: cle,
                payload: payload,
                misAJourLe: misAJourLe,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String type,
                required String cle,
                required String payload,
                Value<DateTime> misAJourLe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReferentielCacheEntriesCompanion.insert(
                type: type,
                cle: cle,
                payload: payload,
                misAJourLe: misAJourLe,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReferentielCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReferentielCacheEntriesTable,
      ReferentielCacheEntry,
      $$ReferentielCacheEntriesTableFilterComposer,
      $$ReferentielCacheEntriesTableOrderingComposer,
      $$ReferentielCacheEntriesTableAnnotationComposer,
      $$ReferentielCacheEntriesTableCreateCompanionBuilder,
      $$ReferentielCacheEntriesTableUpdateCompanionBuilder,
      (
        ReferentielCacheEntry,
        BaseReferences<
          _$AppDatabase,
          $ReferentielCacheEntriesTable,
          ReferentielCacheEntry
        >,
      ),
      ReferentielCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String domaine,
      required String type,
      required String cle,
      required String payload,
      Value<DateTime> misAJourLe,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> domaine,
      Value<String> type,
      Value<String> cle,
      Value<String> payload,
      Value<DateTime> misAJourLe,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get domaine => $composableBuilder(
    column: $table.domaine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cle => $composableBuilder(
    column: $table.cle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get domaine => $composableBuilder(
    column: $table.domaine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cle => $composableBuilder(
    column: $table.cle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get domaine =>
      $composableBuilder(column: $table.domaine, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get cle =>
      $composableBuilder(column: $table.cle, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get misAJourLe => $composableBuilder(
    column: $table.misAJourLe,
    builder: (column) => column,
  );
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheEntriesTable,
          CacheEntry,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntry,
            BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>,
          ),
          CacheEntry,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> domaine = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> cle = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> misAJourLe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                domaine: domaine,
                type: type,
                cle: cle,
                payload: payload,
                misAJourLe: misAJourLe,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String domaine,
                required String type,
                required String cle,
                required String payload,
                Value<DateTime> misAJourLe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                domaine: domaine,
                type: type,
                cle: cle,
                payload: payload,
                misAJourLe: misAJourLe,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheEntriesTable,
      CacheEntry,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntry,
        BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>,
      ),
      CacheEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SyncQueueEntriesTableTableManager get syncQueueEntries =>
      $$SyncQueueEntriesTableTableManager(_db, _db.syncQueueEntries);
  $$ReferentielCacheEntriesTableTableManager get referentielCacheEntries =>
      $$ReferentielCacheEntriesTableTableManager(
        _db,
        _db.referentielCacheEntries,
      );
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
}
