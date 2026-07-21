// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signer_database.dart';

// ignore_for_file: type=lint
class $SignRecordsTable extends SignRecords
    with TableInfo<$SignRecordsTable, SignRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _reqIdMeta = const VerificationMeta('reqId');
  @override
  late final GeneratedColumn<String> reqId = GeneratedColumn<String>(
    'req_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _walletIdMeta = const VerificationMeta(
    'walletId',
  );
  @override
  late final GeneratedColumn<String> walletId = GeneratedColumn<String>(
    'wallet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coinMeta = const VerificationMeta('coin');
  @override
  late final GeneratedColumn<String> coin = GeneratedColumn<String>(
    'coin',
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
  static const VerificationMeta _toAddressMeta = const VerificationMeta(
    'toAddress',
  );
  @override
  late final GeneratedColumn<String> toAddress = GeneratedColumn<String>(
    'to_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<String> amount = GeneratedColumn<String>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signedAtMeta = const VerificationMeta(
    'signedAt',
  );
  @override
  late final GeneratedColumn<int> signedAt = GeneratedColumn<int>(
    'signed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _txHashMeta = const VerificationMeta('txHash');
  @override
  late final GeneratedColumn<String> txHash = GeneratedColumn<String>(
    'tx_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    reqId,
    walletId,
    coin,
    operation,
    toAddress,
    amount,
    signedAt,
    txHash,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sign_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('req_id')) {
      context.handle(
        _reqIdMeta,
        reqId.isAcceptableOrUnknown(data['req_id']!, _reqIdMeta),
      );
    } else if (isInserting) {
      context.missing(_reqIdMeta);
    }
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('coin')) {
      context.handle(
        _coinMeta,
        coin.isAcceptableOrUnknown(data['coin']!, _coinMeta),
      );
    } else if (isInserting) {
      context.missing(_coinMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('to_address')) {
      context.handle(
        _toAddressMeta,
        toAddress.isAcceptableOrUnknown(data['to_address']!, _toAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_toAddressMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('signed_at')) {
      context.handle(
        _signedAtMeta,
        signedAt.isAcceptableOrUnknown(data['signed_at']!, _signedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_signedAtMeta);
    }
    if (data.containsKey('tx_hash')) {
      context.handle(
        _txHashMeta,
        txHash.isAcceptableOrUnknown(data['tx_hash']!, _txHashMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {reqId};
  @override
  SignRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignRecord(
      reqId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}req_id'],
      )!,
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      toAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_address'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount'],
      )!,
      signedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}signed_at'],
      )!,
      txHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tx_hash'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $SignRecordsTable createAlias(String alias) {
    return $SignRecordsTable(attachedDatabase, alias);
  }
}

class SignRecord extends DataClass implements Insertable<SignRecord> {
  /// The request id, hex-encoded (primary key — one outcome per request,
  /// forever).
  final String reqId;
  final String walletId;
  final String coin;
  final String operation;
  final String toAddress;
  final String amount;

  /// When the outcome was recorded (epoch seconds).
  final int signedAt;

  /// Chain tx hash for signed requests; null for rejected/expired ones.
  final String? txHash;

  /// [RequestStatus].name.
  final String status;
  const SignRecord({
    required this.reqId,
    required this.walletId,
    required this.coin,
    required this.operation,
    required this.toAddress,
    required this.amount,
    required this.signedAt,
    this.txHash,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['req_id'] = Variable<String>(reqId);
    map['wallet_id'] = Variable<String>(walletId);
    map['coin'] = Variable<String>(coin);
    map['operation'] = Variable<String>(operation);
    map['to_address'] = Variable<String>(toAddress);
    map['amount'] = Variable<String>(amount);
    map['signed_at'] = Variable<int>(signedAt);
    if (!nullToAbsent || txHash != null) {
      map['tx_hash'] = Variable<String>(txHash);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  SignRecordsCompanion toCompanion(bool nullToAbsent) {
    return SignRecordsCompanion(
      reqId: Value(reqId),
      walletId: Value(walletId),
      coin: Value(coin),
      operation: Value(operation),
      toAddress: Value(toAddress),
      amount: Value(amount),
      signedAt: Value(signedAt),
      txHash: txHash == null && nullToAbsent
          ? const Value.absent()
          : Value(txHash),
      status: Value(status),
    );
  }

  factory SignRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignRecord(
      reqId: serializer.fromJson<String>(json['reqId']),
      walletId: serializer.fromJson<String>(json['walletId']),
      coin: serializer.fromJson<String>(json['coin']),
      operation: serializer.fromJson<String>(json['operation']),
      toAddress: serializer.fromJson<String>(json['toAddress']),
      amount: serializer.fromJson<String>(json['amount']),
      signedAt: serializer.fromJson<int>(json['signedAt']),
      txHash: serializer.fromJson<String?>(json['txHash']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'reqId': serializer.toJson<String>(reqId),
      'walletId': serializer.toJson<String>(walletId),
      'coin': serializer.toJson<String>(coin),
      'operation': serializer.toJson<String>(operation),
      'toAddress': serializer.toJson<String>(toAddress),
      'amount': serializer.toJson<String>(amount),
      'signedAt': serializer.toJson<int>(signedAt),
      'txHash': serializer.toJson<String?>(txHash),
      'status': serializer.toJson<String>(status),
    };
  }

  SignRecord copyWith({
    String? reqId,
    String? walletId,
    String? coin,
    String? operation,
    String? toAddress,
    String? amount,
    int? signedAt,
    Value<String?> txHash = const Value.absent(),
    String? status,
  }) => SignRecord(
    reqId: reqId ?? this.reqId,
    walletId: walletId ?? this.walletId,
    coin: coin ?? this.coin,
    operation: operation ?? this.operation,
    toAddress: toAddress ?? this.toAddress,
    amount: amount ?? this.amount,
    signedAt: signedAt ?? this.signedAt,
    txHash: txHash.present ? txHash.value : this.txHash,
    status: status ?? this.status,
  );
  SignRecord copyWithCompanion(SignRecordsCompanion data) {
    return SignRecord(
      reqId: data.reqId.present ? data.reqId.value : this.reqId,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      coin: data.coin.present ? data.coin.value : this.coin,
      operation: data.operation.present ? data.operation.value : this.operation,
      toAddress: data.toAddress.present ? data.toAddress.value : this.toAddress,
      amount: data.amount.present ? data.amount.value : this.amount,
      signedAt: data.signedAt.present ? data.signedAt.value : this.signedAt,
      txHash: data.txHash.present ? data.txHash.value : this.txHash,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignRecord(')
          ..write('reqId: $reqId, ')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('operation: $operation, ')
          ..write('toAddress: $toAddress, ')
          ..write('amount: $amount, ')
          ..write('signedAt: $signedAt, ')
          ..write('txHash: $txHash, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    reqId,
    walletId,
    coin,
    operation,
    toAddress,
    amount,
    signedAt,
    txHash,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignRecord &&
          other.reqId == this.reqId &&
          other.walletId == this.walletId &&
          other.coin == this.coin &&
          other.operation == this.operation &&
          other.toAddress == this.toAddress &&
          other.amount == this.amount &&
          other.signedAt == this.signedAt &&
          other.txHash == this.txHash &&
          other.status == this.status);
}

class SignRecordsCompanion extends UpdateCompanion<SignRecord> {
  final Value<String> reqId;
  final Value<String> walletId;
  final Value<String> coin;
  final Value<String> operation;
  final Value<String> toAddress;
  final Value<String> amount;
  final Value<int> signedAt;
  final Value<String?> txHash;
  final Value<String> status;
  final Value<int> rowid;
  const SignRecordsCompanion({
    this.reqId = const Value.absent(),
    this.walletId = const Value.absent(),
    this.coin = const Value.absent(),
    this.operation = const Value.absent(),
    this.toAddress = const Value.absent(),
    this.amount = const Value.absent(),
    this.signedAt = const Value.absent(),
    this.txHash = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignRecordsCompanion.insert({
    required String reqId,
    required String walletId,
    required String coin,
    required String operation,
    required String toAddress,
    required String amount,
    required int signedAt,
    this.txHash = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  }) : reqId = Value(reqId),
       walletId = Value(walletId),
       coin = Value(coin),
       operation = Value(operation),
       toAddress = Value(toAddress),
       amount = Value(amount),
       signedAt = Value(signedAt),
       status = Value(status);
  static Insertable<SignRecord> custom({
    Expression<String>? reqId,
    Expression<String>? walletId,
    Expression<String>? coin,
    Expression<String>? operation,
    Expression<String>? toAddress,
    Expression<String>? amount,
    Expression<int>? signedAt,
    Expression<String>? txHash,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (reqId != null) 'req_id': reqId,
      if (walletId != null) 'wallet_id': walletId,
      if (coin != null) 'coin': coin,
      if (operation != null) 'operation': operation,
      if (toAddress != null) 'to_address': toAddress,
      if (amount != null) 'amount': amount,
      if (signedAt != null) 'signed_at': signedAt,
      if (txHash != null) 'tx_hash': txHash,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignRecordsCompanion copyWith({
    Value<String>? reqId,
    Value<String>? walletId,
    Value<String>? coin,
    Value<String>? operation,
    Value<String>? toAddress,
    Value<String>? amount,
    Value<int>? signedAt,
    Value<String?>? txHash,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return SignRecordsCompanion(
      reqId: reqId ?? this.reqId,
      walletId: walletId ?? this.walletId,
      coin: coin ?? this.coin,
      operation: operation ?? this.operation,
      toAddress: toAddress ?? this.toAddress,
      amount: amount ?? this.amount,
      signedAt: signedAt ?? this.signedAt,
      txHash: txHash ?? this.txHash,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (reqId.present) {
      map['req_id'] = Variable<String>(reqId.value);
    }
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (toAddress.present) {
      map['to_address'] = Variable<String>(toAddress.value);
    }
    if (amount.present) {
      map['amount'] = Variable<String>(amount.value);
    }
    if (signedAt.present) {
      map['signed_at'] = Variable<int>(signedAt.value);
    }
    if (txHash.present) {
      map['tx_hash'] = Variable<String>(txHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignRecordsCompanion(')
          ..write('reqId: $reqId, ')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('operation: $operation, ')
          ..write('toAddress: $toAddress, ')
          ..write('amount: $amount, ')
          ..write('signedAt: $signedAt, ')
          ..write('txHash: $txHash, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SignerDatabase extends GeneratedDatabase {
  _$SignerDatabase(QueryExecutor e) : super(e);
  $SignerDatabaseManager get managers => $SignerDatabaseManager(this);
  late final $SignRecordsTable signRecords = $SignRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [signRecords];
}

typedef $$SignRecordsTableCreateCompanionBuilder =
    SignRecordsCompanion Function({
      required String reqId,
      required String walletId,
      required String coin,
      required String operation,
      required String toAddress,
      required String amount,
      required int signedAt,
      Value<String?> txHash,
      required String status,
      Value<int> rowid,
    });
typedef $$SignRecordsTableUpdateCompanionBuilder =
    SignRecordsCompanion Function({
      Value<String> reqId,
      Value<String> walletId,
      Value<String> coin,
      Value<String> operation,
      Value<String> toAddress,
      Value<String> amount,
      Value<int> signedAt,
      Value<String?> txHash,
      Value<String> status,
      Value<int> rowid,
    });

class $$SignRecordsTableFilterComposer
    extends Composer<_$SignerDatabase, $SignRecordsTable> {
  $$SignRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get reqId => $composableBuilder(
    column: $table.reqId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toAddress => $composableBuilder(
    column: $table.toAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get signedAt => $composableBuilder(
    column: $table.signedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txHash => $composableBuilder(
    column: $table.txHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignRecordsTableOrderingComposer
    extends Composer<_$SignerDatabase, $SignRecordsTable> {
  $$SignRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get reqId => $composableBuilder(
    column: $table.reqId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toAddress => $composableBuilder(
    column: $table.toAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get signedAt => $composableBuilder(
    column: $table.signedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txHash => $composableBuilder(
    column: $table.txHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignRecordsTableAnnotationComposer
    extends Composer<_$SignerDatabase, $SignRecordsTable> {
  $$SignRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get reqId =>
      $composableBuilder(column: $table.reqId, builder: (column) => column);

  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get toAddress =>
      $composableBuilder(column: $table.toAddress, builder: (column) => column);

  GeneratedColumn<String> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get signedAt =>
      $composableBuilder(column: $table.signedAt, builder: (column) => column);

  GeneratedColumn<String> get txHash =>
      $composableBuilder(column: $table.txHash, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$SignRecordsTableTableManager
    extends
        RootTableManager<
          _$SignerDatabase,
          $SignRecordsTable,
          SignRecord,
          $$SignRecordsTableFilterComposer,
          $$SignRecordsTableOrderingComposer,
          $$SignRecordsTableAnnotationComposer,
          $$SignRecordsTableCreateCompanionBuilder,
          $$SignRecordsTableUpdateCompanionBuilder,
          (
            SignRecord,
            BaseReferences<_$SignerDatabase, $SignRecordsTable, SignRecord>,
          ),
          SignRecord,
          PrefetchHooks Function()
        > {
  $$SignRecordsTableTableManager(_$SignerDatabase db, $SignRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> reqId = const Value.absent(),
                Value<String> walletId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> toAddress = const Value.absent(),
                Value<String> amount = const Value.absent(),
                Value<int> signedAt = const Value.absent(),
                Value<String?> txHash = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignRecordsCompanion(
                reqId: reqId,
                walletId: walletId,
                coin: coin,
                operation: operation,
                toAddress: toAddress,
                amount: amount,
                signedAt: signedAt,
                txHash: txHash,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String reqId,
                required String walletId,
                required String coin,
                required String operation,
                required String toAddress,
                required String amount,
                required int signedAt,
                Value<String?> txHash = const Value.absent(),
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => SignRecordsCompanion.insert(
                reqId: reqId,
                walletId: walletId,
                coin: coin,
                operation: operation,
                toAddress: toAddress,
                amount: amount,
                signedAt: signedAt,
                txHash: txHash,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$SignerDatabase,
      $SignRecordsTable,
      SignRecord,
      $$SignRecordsTableFilterComposer,
      $$SignRecordsTableOrderingComposer,
      $$SignRecordsTableAnnotationComposer,
      $$SignRecordsTableCreateCompanionBuilder,
      $$SignRecordsTableUpdateCompanionBuilder,
      (
        SignRecord,
        BaseReferences<_$SignerDatabase, $SignRecordsTable, SignRecord>,
      ),
      SignRecord,
      PrefetchHooks Function()
    >;

class $SignerDatabaseManager {
  final _$SignerDatabase _db;
  $SignerDatabaseManager(this._db);
  $$SignRecordsTableTableManager get signRecords =>
      $$SignRecordsTableTableManager(_db, _db.signRecords);
}
