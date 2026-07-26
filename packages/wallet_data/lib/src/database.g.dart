// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $WalletsTable extends Wallets with TableInfo<$WalletsTable, Wallet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<WalletType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<WalletType>($WalletsTable.$convertertype);
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<int> avatarColor = GeneratedColumn<int>(
    'avatar_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _backedUpMeta = const VerificationMeta(
    'backedUp',
  );
  @override
  late final GeneratedColumn<bool> backedUp = GeneratedColumn<bool>(
    'backed_up',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("backed_up" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _coldWalletIdMeta = const VerificationMeta(
    'coldWalletId',
  );
  @override
  late final GeneratedColumn<String> coldWalletId = GeneratedColumn<String>(
    'cold_wallet_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _protocolVerMeta = const VerificationMeta(
    'protocolVer',
  );
  @override
  late final GeneratedColumn<int> protocolVer = GeneratedColumn<int>(
    'protocol_ver',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    avatarColor,
    sortOrder,
    backedUp,
    coldWalletId,
    protocolVer,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Wallet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_avatarColorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('backed_up')) {
      context.handle(
        _backedUpMeta,
        backedUp.isAcceptableOrUnknown(data['backed_up']!, _backedUpMeta),
      );
    }
    if (data.containsKey('cold_wallet_id')) {
      context.handle(
        _coldWalletIdMeta,
        coldWalletId.isAcceptableOrUnknown(
          data['cold_wallet_id']!,
          _coldWalletIdMeta,
        ),
      );
    }
    if (data.containsKey('protocol_ver')) {
      context.handle(
        _protocolVerMeta,
        protocolVer.isAcceptableOrUnknown(
          data['protocol_ver']!,
          _protocolVerMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Wallet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Wallet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: $WalletsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avatar_color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      backedUp: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}backed_up'],
      )!,
      coldWalletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cold_wallet_id'],
      ),
      protocolVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_ver'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WalletsTable createAlias(String alias) {
    return $WalletsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WalletType, int, int> $convertertype =
      const EnumIndexConverter<WalletType>(WalletType.values);
}

class Wallet extends DataClass implements Insertable<Wallet> {
  final String id;
  final String name;
  final WalletType type;
  final int avatarColor;
  final int sortOrder;
  final bool backedUp;
  final String? coldWalletId;
  final int? protocolVer;
  final int createdAt;
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.avatarColor,
    required this.sortOrder,
    required this.backedUp,
    this.coldWalletId,
    this.protocolVer,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['type'] = Variable<int>($WalletsTable.$convertertype.toSql(type));
    }
    map['avatar_color'] = Variable<int>(avatarColor);
    map['sort_order'] = Variable<int>(sortOrder);
    map['backed_up'] = Variable<bool>(backedUp);
    if (!nullToAbsent || coldWalletId != null) {
      map['cold_wallet_id'] = Variable<String>(coldWalletId);
    }
    if (!nullToAbsent || protocolVer != null) {
      map['protocol_ver'] = Variable<int>(protocolVer);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  WalletsCompanion toCompanion(bool nullToAbsent) {
    return WalletsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      avatarColor: Value(avatarColor),
      sortOrder: Value(sortOrder),
      backedUp: Value(backedUp),
      coldWalletId: coldWalletId == null && nullToAbsent
          ? const Value.absent()
          : Value(coldWalletId),
      protocolVer: protocolVer == null && nullToAbsent
          ? const Value.absent()
          : Value(protocolVer),
      createdAt: Value(createdAt),
    );
  }

  factory Wallet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Wallet(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: $WalletsTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      avatarColor: serializer.fromJson<int>(json['avatarColor']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      backedUp: serializer.fromJson<bool>(json['backedUp']),
      coldWalletId: serializer.fromJson<String?>(json['coldWalletId']),
      protocolVer: serializer.fromJson<int?>(json['protocolVer']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<int>($WalletsTable.$convertertype.toJson(type)),
      'avatarColor': serializer.toJson<int>(avatarColor),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'backedUp': serializer.toJson<bool>(backedUp),
      'coldWalletId': serializer.toJson<String?>(coldWalletId),
      'protocolVer': serializer.toJson<int?>(protocolVer),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Wallet copyWith({
    String? id,
    String? name,
    WalletType? type,
    int? avatarColor,
    int? sortOrder,
    bool? backedUp,
    Value<String?> coldWalletId = const Value.absent(),
    Value<int?> protocolVer = const Value.absent(),
    int? createdAt,
  }) => Wallet(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    avatarColor: avatarColor ?? this.avatarColor,
    sortOrder: sortOrder ?? this.sortOrder,
    backedUp: backedUp ?? this.backedUp,
    coldWalletId: coldWalletId.present ? coldWalletId.value : this.coldWalletId,
    protocolVer: protocolVer.present ? protocolVer.value : this.protocolVer,
    createdAt: createdAt ?? this.createdAt,
  );
  Wallet copyWithCompanion(WalletsCompanion data) {
    return Wallet(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      backedUp: data.backedUp.present ? data.backedUp.value : this.backedUp,
      coldWalletId: data.coldWalletId.present
          ? data.coldWalletId.value
          : this.coldWalletId,
      protocolVer: data.protocolVer.present
          ? data.protocolVer.value
          : this.protocolVer,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Wallet(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('backedUp: $backedUp, ')
          ..write('coldWalletId: $coldWalletId, ')
          ..write('protocolVer: $protocolVer, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    avatarColor,
    sortOrder,
    backedUp,
    coldWalletId,
    protocolVer,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Wallet &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.avatarColor == this.avatarColor &&
          other.sortOrder == this.sortOrder &&
          other.backedUp == this.backedUp &&
          other.coldWalletId == this.coldWalletId &&
          other.protocolVer == this.protocolVer &&
          other.createdAt == this.createdAt);
}

class WalletsCompanion extends UpdateCompanion<Wallet> {
  final Value<String> id;
  final Value<String> name;
  final Value<WalletType> type;
  final Value<int> avatarColor;
  final Value<int> sortOrder;
  final Value<bool> backedUp;
  final Value<String?> coldWalletId;
  final Value<int?> protocolVer;
  final Value<int> createdAt;
  final Value<int> rowid;
  const WalletsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.backedUp = const Value.absent(),
    this.coldWalletId = const Value.absent(),
    this.protocolVer = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WalletsCompanion.insert({
    required String id,
    required String name,
    required WalletType type,
    required int avatarColor,
    this.sortOrder = const Value.absent(),
    this.backedUp = const Value.absent(),
    this.coldWalletId = const Value.absent(),
    this.protocolVer = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       type = Value(type),
       avatarColor = Value(avatarColor),
       createdAt = Value(createdAt);
  static Insertable<Wallet> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? type,
    Expression<int>? avatarColor,
    Expression<int>? sortOrder,
    Expression<bool>? backedUp,
    Expression<String>? coldWalletId,
    Expression<int>? protocolVer,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (backedUp != null) 'backed_up': backedUp,
      if (coldWalletId != null) 'cold_wallet_id': coldWalletId,
      if (protocolVer != null) 'protocol_ver': protocolVer,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WalletsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<WalletType>? type,
    Value<int>? avatarColor,
    Value<int>? sortOrder,
    Value<bool>? backedUp,
    Value<String?>? coldWalletId,
    Value<int?>? protocolVer,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return WalletsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      avatarColor: avatarColor ?? this.avatarColor,
      sortOrder: sortOrder ?? this.sortOrder,
      backedUp: backedUp ?? this.backedUp,
      coldWalletId: coldWalletId ?? this.coldWalletId,
      protocolVer: protocolVer ?? this.protocolVer,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(
        $WalletsTable.$convertertype.toSql(type.value),
      );
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<int>(avatarColor.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (backedUp.present) {
      map['backed_up'] = Variable<bool>(backedUp.value);
    }
    if (coldWalletId.present) {
      map['cold_wallet_id'] = Variable<String>(coldWalletId.value);
    }
    if (protocolVer.present) {
      map['protocol_ver'] = Variable<int>(protocolVer.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('backedUp: $backedUp, ')
          ..write('coldWalletId: $coldWalletId, ')
          ..write('protocolVer: $protocolVer, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _derivationPathMeta = const VerificationMeta(
    'derivationPath',
  );
  @override
  late final GeneratedColumn<String> derivationPath = GeneratedColumn<String>(
    'derivation_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIndexMeta = const VerificationMeta(
    'accountIndex',
  );
  @override
  late final GeneratedColumn<int> accountIndex = GeneratedColumn<int>(
    'account_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    walletId,
    coin,
    address,
    derivationPath,
    accountIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('derivation_path')) {
      context.handle(
        _derivationPathMeta,
        derivationPath.isAcceptableOrUnknown(
          data['derivation_path']!,
          _derivationPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_derivationPathMeta);
    }
    if (data.containsKey('account_index')) {
      context.handle(
        _accountIndexMeta,
        accountIndex.isAcceptableOrUnknown(
          data['account_index']!,
          _accountIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {walletId, coin};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      derivationPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}derivation_path'],
      )!,
      accountIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_index'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final String walletId;
  final String coin;
  final String address;
  final String derivationPath;
  final int accountIndex;
  const Account({
    required this.walletId,
    required this.coin,
    required this.address,
    required this.derivationPath,
    required this.accountIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['wallet_id'] = Variable<String>(walletId);
    map['coin'] = Variable<String>(coin);
    map['address'] = Variable<String>(address);
    map['derivation_path'] = Variable<String>(derivationPath);
    map['account_index'] = Variable<int>(accountIndex);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      walletId: Value(walletId),
      coin: Value(coin),
      address: Value(address),
      derivationPath: Value(derivationPath),
      accountIndex: Value(accountIndex),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      walletId: serializer.fromJson<String>(json['walletId']),
      coin: serializer.fromJson<String>(json['coin']),
      address: serializer.fromJson<String>(json['address']),
      derivationPath: serializer.fromJson<String>(json['derivationPath']),
      accountIndex: serializer.fromJson<int>(json['accountIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'walletId': serializer.toJson<String>(walletId),
      'coin': serializer.toJson<String>(coin),
      'address': serializer.toJson<String>(address),
      'derivationPath': serializer.toJson<String>(derivationPath),
      'accountIndex': serializer.toJson<int>(accountIndex),
    };
  }

  Account copyWith({
    String? walletId,
    String? coin,
    String? address,
    String? derivationPath,
    int? accountIndex,
  }) => Account(
    walletId: walletId ?? this.walletId,
    coin: coin ?? this.coin,
    address: address ?? this.address,
    derivationPath: derivationPath ?? this.derivationPath,
    accountIndex: accountIndex ?? this.accountIndex,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      coin: data.coin.present ? data.coin.value : this.coin,
      address: data.address.present ? data.address.value : this.address,
      derivationPath: data.derivationPath.present
          ? data.derivationPath.value
          : this.derivationPath,
      accountIndex: data.accountIndex.present
          ? data.accountIndex.value
          : this.accountIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('address: $address, ')
          ..write('derivationPath: $derivationPath, ')
          ..write('accountIndex: $accountIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(walletId, coin, address, derivationPath, accountIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.walletId == this.walletId &&
          other.coin == this.coin &&
          other.address == this.address &&
          other.derivationPath == this.derivationPath &&
          other.accountIndex == this.accountIndex);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> walletId;
  final Value<String> coin;
  final Value<String> address;
  final Value<String> derivationPath;
  final Value<int> accountIndex;
  final Value<int> rowid;
  const AccountsCompanion({
    this.walletId = const Value.absent(),
    this.coin = const Value.absent(),
    this.address = const Value.absent(),
    this.derivationPath = const Value.absent(),
    this.accountIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String walletId,
    required String coin,
    required String address,
    required String derivationPath,
    required int accountIndex,
    this.rowid = const Value.absent(),
  }) : walletId = Value(walletId),
       coin = Value(coin),
       address = Value(address),
       derivationPath = Value(derivationPath),
       accountIndex = Value(accountIndex);
  static Insertable<Account> custom({
    Expression<String>? walletId,
    Expression<String>? coin,
    Expression<String>? address,
    Expression<String>? derivationPath,
    Expression<int>? accountIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (walletId != null) 'wallet_id': walletId,
      if (coin != null) 'coin': coin,
      if (address != null) 'address': address,
      if (derivationPath != null) 'derivation_path': derivationPath,
      if (accountIndex != null) 'account_index': accountIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? walletId,
    Value<String>? coin,
    Value<String>? address,
    Value<String>? derivationPath,
    Value<int>? accountIndex,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      walletId: walletId ?? this.walletId,
      coin: coin ?? this.coin,
      address: address ?? this.address,
      derivationPath: derivationPath ?? this.derivationPath,
      accountIndex: accountIndex ?? this.accountIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (derivationPath.present) {
      map['derivation_path'] = Variable<String>(derivationPath.value);
    }
    if (accountIndex.present) {
      map['account_index'] = Variable<int>(accountIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('address: $address, ')
          ..write('derivationPath: $derivationPath, ')
          ..write('accountIndex: $accountIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TokensTable extends Tokens with TableInfo<$TokensTable, Token> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TokensTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _contractMeta = const VerificationMeta(
    'contract',
  );
  @override
  late final GeneratedColumn<String> contract = GeneratedColumn<String>(
    'contract',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decimalsMeta = const VerificationMeta(
    'decimals',
  );
  @override
  late final GeneratedColumn<int> decimals = GeneratedColumn<int>(
    'decimals',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _trustedMeta = const VerificationMeta(
    'trusted',
  );
  @override
  late final GeneratedColumn<bool> trusted = GeneratedColumn<bool>(
    'trusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("trusted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    walletId,
    coin,
    contract,
    symbol,
    decimals,
    name,
    enabled,
    trusted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tokens';
  @override
  VerificationContext validateIntegrity(
    Insertable<Token> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('contract')) {
      context.handle(
        _contractMeta,
        contract.isAcceptableOrUnknown(data['contract']!, _contractMeta),
      );
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('decimals')) {
      context.handle(
        _decimalsMeta,
        decimals.isAcceptableOrUnknown(data['decimals']!, _decimalsMeta),
      );
    } else if (isInserting) {
      context.missing(_decimalsMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('trusted')) {
      context.handle(
        _trustedMeta,
        trusted.isAcceptableOrUnknown(data['trusted']!, _trustedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {walletId, coin, contract};
  @override
  Token map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Token(
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      contract: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      decimals: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decimals'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      trusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}trusted'],
      )!,
    );
  }

  @override
  $TokensTable createAlias(String alias) {
    return $TokensTable(attachedDatabase, alias);
  }
}

class Token extends DataClass implements Insertable<Token> {
  final String walletId;
  final String coin;
  final String contract;
  final String symbol;
  final int decimals;
  final String name;
  final bool enabled;
  final bool trusted;
  const Token({
    required this.walletId,
    required this.coin,
    required this.contract,
    required this.symbol,
    required this.decimals,
    required this.name,
    required this.enabled,
    required this.trusted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['wallet_id'] = Variable<String>(walletId);
    map['coin'] = Variable<String>(coin);
    map['contract'] = Variable<String>(contract);
    map['symbol'] = Variable<String>(symbol);
    map['decimals'] = Variable<int>(decimals);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    map['trusted'] = Variable<bool>(trusted);
    return map;
  }

  TokensCompanion toCompanion(bool nullToAbsent) {
    return TokensCompanion(
      walletId: Value(walletId),
      coin: Value(coin),
      contract: Value(contract),
      symbol: Value(symbol),
      decimals: Value(decimals),
      name: Value(name),
      enabled: Value(enabled),
      trusted: Value(trusted),
    );
  }

  factory Token.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Token(
      walletId: serializer.fromJson<String>(json['walletId']),
      coin: serializer.fromJson<String>(json['coin']),
      contract: serializer.fromJson<String>(json['contract']),
      symbol: serializer.fromJson<String>(json['symbol']),
      decimals: serializer.fromJson<int>(json['decimals']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      trusted: serializer.fromJson<bool>(json['trusted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'walletId': serializer.toJson<String>(walletId),
      'coin': serializer.toJson<String>(coin),
      'contract': serializer.toJson<String>(contract),
      'symbol': serializer.toJson<String>(symbol),
      'decimals': serializer.toJson<int>(decimals),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'trusted': serializer.toJson<bool>(trusted),
    };
  }

  Token copyWith({
    String? walletId,
    String? coin,
    String? contract,
    String? symbol,
    int? decimals,
    String? name,
    bool? enabled,
    bool? trusted,
  }) => Token(
    walletId: walletId ?? this.walletId,
    coin: coin ?? this.coin,
    contract: contract ?? this.contract,
    symbol: symbol ?? this.symbol,
    decimals: decimals ?? this.decimals,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    trusted: trusted ?? this.trusted,
  );
  Token copyWithCompanion(TokensCompanion data) {
    return Token(
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      coin: data.coin.present ? data.coin.value : this.coin,
      contract: data.contract.present ? data.contract.value : this.contract,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      decimals: data.decimals.present ? data.decimals.value : this.decimals,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      trusted: data.trusted.present ? data.trusted.value : this.trusted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Token(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('symbol: $symbol, ')
          ..write('decimals: $decimals, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('trusted: $trusted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    walletId,
    coin,
    contract,
    symbol,
    decimals,
    name,
    enabled,
    trusted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Token &&
          other.walletId == this.walletId &&
          other.coin == this.coin &&
          other.contract == this.contract &&
          other.symbol == this.symbol &&
          other.decimals == this.decimals &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.trusted == this.trusted);
}

class TokensCompanion extends UpdateCompanion<Token> {
  final Value<String> walletId;
  final Value<String> coin;
  final Value<String> contract;
  final Value<String> symbol;
  final Value<int> decimals;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<bool> trusted;
  final Value<int> rowid;
  const TokensCompanion({
    this.walletId = const Value.absent(),
    this.coin = const Value.absent(),
    this.contract = const Value.absent(),
    this.symbol = const Value.absent(),
    this.decimals = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.trusted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TokensCompanion.insert({
    required String walletId,
    required String coin,
    this.contract = const Value.absent(),
    required String symbol,
    required int decimals,
    required String name,
    this.enabled = const Value.absent(),
    this.trusted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : walletId = Value(walletId),
       coin = Value(coin),
       symbol = Value(symbol),
       decimals = Value(decimals),
       name = Value(name);
  static Insertable<Token> custom({
    Expression<String>? walletId,
    Expression<String>? coin,
    Expression<String>? contract,
    Expression<String>? symbol,
    Expression<int>? decimals,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<bool>? trusted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (walletId != null) 'wallet_id': walletId,
      if (coin != null) 'coin': coin,
      if (contract != null) 'contract': contract,
      if (symbol != null) 'symbol': symbol,
      if (decimals != null) 'decimals': decimals,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (trusted != null) 'trusted': trusted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TokensCompanion copyWith({
    Value<String>? walletId,
    Value<String>? coin,
    Value<String>? contract,
    Value<String>? symbol,
    Value<int>? decimals,
    Value<String>? name,
    Value<bool>? enabled,
    Value<bool>? trusted,
    Value<int>? rowid,
  }) {
    return TokensCompanion(
      walletId: walletId ?? this.walletId,
      coin: coin ?? this.coin,
      contract: contract ?? this.contract,
      symbol: symbol ?? this.symbol,
      decimals: decimals ?? this.decimals,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trusted: trusted ?? this.trusted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (contract.present) {
      map['contract'] = Variable<String>(contract.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (decimals.present) {
      map['decimals'] = Variable<int>(decimals.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (trusted.present) {
      map['trusted'] = Variable<bool>(trusted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TokensCompanion(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('symbol: $symbol, ')
          ..write('decimals: $decimals, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('trusted: $trusted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BalancesTable extends Balances with TableInfo<$BalancesTable, Balance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BalancesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _contractMeta = const VerificationMeta(
    'contract',
  );
  @override
  late final GeneratedColumn<String> contract = GeneratedColumn<String>(
    'contract',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
    'raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fiatMeta = const VerificationMeta('fiat');
  @override
  late final GeneratedColumn<double> fiat = GeneratedColumn<double>(
    'fiat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    walletId,
    coin,
    contract,
    raw,
    fiat,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'balances';
  @override
  VerificationContext validateIntegrity(
    Insertable<Balance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('contract')) {
      context.handle(
        _contractMeta,
        contract.isAcceptableOrUnknown(data['contract']!, _contractMeta),
      );
    }
    if (data.containsKey('raw')) {
      context.handle(
        _rawMeta,
        raw.isAcceptableOrUnknown(data['raw']!, _rawMeta),
      );
    } else if (isInserting) {
      context.missing(_rawMeta);
    }
    if (data.containsKey('fiat')) {
      context.handle(
        _fiatMeta,
        fiat.isAcceptableOrUnknown(data['fiat']!, _fiatMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {walletId, coin, contract};
  @override
  Balance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Balance(
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      contract: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract'],
      )!,
      raw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw'],
      )!,
      fiat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fiat'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BalancesTable createAlias(String alias) {
    return $BalancesTable(attachedDatabase, alias);
  }
}

class Balance extends DataClass implements Insertable<Balance> {
  final String walletId;
  final String coin;
  final String contract;

  /// BigInt base units, decimal string.
  final String raw;
  final double? fiat;
  final int updatedAt;
  const Balance({
    required this.walletId,
    required this.coin,
    required this.contract,
    required this.raw,
    this.fiat,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['wallet_id'] = Variable<String>(walletId);
    map['coin'] = Variable<String>(coin);
    map['contract'] = Variable<String>(contract);
    map['raw'] = Variable<String>(raw);
    if (!nullToAbsent || fiat != null) {
      map['fiat'] = Variable<double>(fiat);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BalancesCompanion toCompanion(bool nullToAbsent) {
    return BalancesCompanion(
      walletId: Value(walletId),
      coin: Value(coin),
      contract: Value(contract),
      raw: Value(raw),
      fiat: fiat == null && nullToAbsent ? const Value.absent() : Value(fiat),
      updatedAt: Value(updatedAt),
    );
  }

  factory Balance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Balance(
      walletId: serializer.fromJson<String>(json['walletId']),
      coin: serializer.fromJson<String>(json['coin']),
      contract: serializer.fromJson<String>(json['contract']),
      raw: serializer.fromJson<String>(json['raw']),
      fiat: serializer.fromJson<double?>(json['fiat']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'walletId': serializer.toJson<String>(walletId),
      'coin': serializer.toJson<String>(coin),
      'contract': serializer.toJson<String>(contract),
      'raw': serializer.toJson<String>(raw),
      'fiat': serializer.toJson<double?>(fiat),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Balance copyWith({
    String? walletId,
    String? coin,
    String? contract,
    String? raw,
    Value<double?> fiat = const Value.absent(),
    int? updatedAt,
  }) => Balance(
    walletId: walletId ?? this.walletId,
    coin: coin ?? this.coin,
    contract: contract ?? this.contract,
    raw: raw ?? this.raw,
    fiat: fiat.present ? fiat.value : this.fiat,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Balance copyWithCompanion(BalancesCompanion data) {
    return Balance(
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      coin: data.coin.present ? data.coin.value : this.coin,
      contract: data.contract.present ? data.contract.value : this.contract,
      raw: data.raw.present ? data.raw.value : this.raw,
      fiat: data.fiat.present ? data.fiat.value : this.fiat,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Balance(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('raw: $raw, ')
          ..write('fiat: $fiat, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(walletId, coin, contract, raw, fiat, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Balance &&
          other.walletId == this.walletId &&
          other.coin == this.coin &&
          other.contract == this.contract &&
          other.raw == this.raw &&
          other.fiat == this.fiat &&
          other.updatedAt == this.updatedAt);
}

class BalancesCompanion extends UpdateCompanion<Balance> {
  final Value<String> walletId;
  final Value<String> coin;
  final Value<String> contract;
  final Value<String> raw;
  final Value<double?> fiat;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BalancesCompanion({
    this.walletId = const Value.absent(),
    this.coin = const Value.absent(),
    this.contract = const Value.absent(),
    this.raw = const Value.absent(),
    this.fiat = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BalancesCompanion.insert({
    required String walletId,
    required String coin,
    this.contract = const Value.absent(),
    required String raw,
    this.fiat = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : walletId = Value(walletId),
       coin = Value(coin),
       raw = Value(raw),
       updatedAt = Value(updatedAt);
  static Insertable<Balance> custom({
    Expression<String>? walletId,
    Expression<String>? coin,
    Expression<String>? contract,
    Expression<String>? raw,
    Expression<double>? fiat,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (walletId != null) 'wallet_id': walletId,
      if (coin != null) 'coin': coin,
      if (contract != null) 'contract': contract,
      if (raw != null) 'raw': raw,
      if (fiat != null) 'fiat': fiat,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BalancesCompanion copyWith({
    Value<String>? walletId,
    Value<String>? coin,
    Value<String>? contract,
    Value<String>? raw,
    Value<double?>? fiat,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BalancesCompanion(
      walletId: walletId ?? this.walletId,
      coin: coin ?? this.coin,
      contract: contract ?? this.contract,
      raw: raw ?? this.raw,
      fiat: fiat ?? this.fiat,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (contract.present) {
      map['contract'] = Variable<String>(contract.value);
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    if (fiat.present) {
      map['fiat'] = Variable<double>(fiat.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BalancesCompanion(')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('raw: $raw, ')
          ..write('fiat: $fiat, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _reqIdMeta = const VerificationMeta('reqId');
  @override
  late final GeneratedColumn<String> reqId = GeneratedColumn<String>(
    'req_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _contractMeta = const VerificationMeta(
    'contract',
  );
  @override
  late final GeneratedColumn<String> contract = GeneratedColumn<String>(
    'contract',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxDirection, int> direction =
      GeneratedColumn<int>(
        'direction',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<TxDirection>($TransactionsTable.$converterdirection);
  static const VerificationMeta _fromAddrMeta = const VerificationMeta(
    'fromAddr',
  );
  @override
  late final GeneratedColumn<String> fromAddr = GeneratedColumn<String>(
    'from_addr',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toAddrMeta = const VerificationMeta('toAddr');
  @override
  late final GeneratedColumn<String> toAddr = GeneratedColumn<String>(
    'to_addr',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountRawMeta = const VerificationMeta(
    'amountRaw',
  );
  @override
  late final GeneratedColumn<String> amountRaw = GeneratedColumn<String>(
    'amount_raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feeRawMeta = const VerificationMeta('feeRaw');
  @override
  late final GeneratedColumn<String> feeRaw = GeneratedColumn<String>(
    'fee_raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<TxStatus>($TransactionsTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<SignMode, int> signMode =
      GeneratedColumn<int>(
        'sign_mode',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SignMode>($TransactionsTable.$convertersignMode);
  static const VerificationMeta _memoMeta = const VerificationMeta('memo');
  @override
  late final GeneratedColumn<String> memo = GeneratedColumn<String>(
    'memo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _broadcastAtMeta = const VerificationMeta(
    'broadcastAt',
  );
  @override
  late final GeneratedColumn<int> broadcastAt = GeneratedColumn<int>(
    'broadcast_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<String> nonce = GeneratedColumn<String>(
    'nonce',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxPriorityFeeRawMeta = const VerificationMeta(
    'maxPriorityFeeRaw',
  );
  @override
  late final GeneratedColumn<String> maxPriorityFeeRaw =
      GeneratedColumn<String>(
        'max_priority_fee_raw',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _maxFeeRawMeta = const VerificationMeta(
    'maxFeeRaw',
  );
  @override
  late final GeneratedColumn<String> maxFeeRaw = GeneratedColumn<String>(
    'max_fee_raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gasLimitRawMeta = const VerificationMeta(
    'gasLimitRaw',
  );
  @override
  late final GeneratedColumn<String> gasLimitRaw = GeneratedColumn<String>(
    'gas_limit_raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replacesIdMeta = const VerificationMeta(
    'replacesId',
  );
  @override
  late final GeneratedColumn<String> replacesId = GeneratedColumn<String>(
    'replaces_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replacedByIdMeta = const VerificationMeta(
    'replacedById',
  );
  @override
  late final GeneratedColumn<String> replacedById = GeneratedColumn<String>(
    'replaced_by_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TxReplacementKind?, int>
  replacementKind =
      GeneratedColumn<int>(
        'replacement_kind',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<TxReplacementKind?>(
        $TransactionsTable.$converterreplacementKindn,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    walletId,
    reqId,
    coin,
    contract,
    direction,
    fromAddr,
    toAddr,
    amountRaw,
    feeRaw,
    hash,
    status,
    signMode,
    memo,
    createdAt,
    broadcastAt,
    nonce,
    maxPriorityFeeRaw,
    maxFeeRaw,
    gasLimitRaw,
    replacesId,
    replacedById,
    replacementKind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Transaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('req_id')) {
      context.handle(
        _reqIdMeta,
        reqId.isAcceptableOrUnknown(data['req_id']!, _reqIdMeta),
      );
    }
    if (data.containsKey('coin')) {
      context.handle(
        _coinMeta,
        coin.isAcceptableOrUnknown(data['coin']!, _coinMeta),
      );
    } else if (isInserting) {
      context.missing(_coinMeta);
    }
    if (data.containsKey('contract')) {
      context.handle(
        _contractMeta,
        contract.isAcceptableOrUnknown(data['contract']!, _contractMeta),
      );
    }
    if (data.containsKey('from_addr')) {
      context.handle(
        _fromAddrMeta,
        fromAddr.isAcceptableOrUnknown(data['from_addr']!, _fromAddrMeta),
      );
    } else if (isInserting) {
      context.missing(_fromAddrMeta);
    }
    if (data.containsKey('to_addr')) {
      context.handle(
        _toAddrMeta,
        toAddr.isAcceptableOrUnknown(data['to_addr']!, _toAddrMeta),
      );
    } else if (isInserting) {
      context.missing(_toAddrMeta);
    }
    if (data.containsKey('amount_raw')) {
      context.handle(
        _amountRawMeta,
        amountRaw.isAcceptableOrUnknown(data['amount_raw']!, _amountRawMeta),
      );
    } else if (isInserting) {
      context.missing(_amountRawMeta);
    }
    if (data.containsKey('fee_raw')) {
      context.handle(
        _feeRawMeta,
        feeRaw.isAcceptableOrUnknown(data['fee_raw']!, _feeRawMeta),
      );
    }
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    }
    if (data.containsKey('memo')) {
      context.handle(
        _memoMeta,
        memo.isAcceptableOrUnknown(data['memo']!, _memoMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('broadcast_at')) {
      context.handle(
        _broadcastAtMeta,
        broadcastAt.isAcceptableOrUnknown(
          data['broadcast_at']!,
          _broadcastAtMeta,
        ),
      );
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    }
    if (data.containsKey('max_priority_fee_raw')) {
      context.handle(
        _maxPriorityFeeRawMeta,
        maxPriorityFeeRaw.isAcceptableOrUnknown(
          data['max_priority_fee_raw']!,
          _maxPriorityFeeRawMeta,
        ),
      );
    }
    if (data.containsKey('max_fee_raw')) {
      context.handle(
        _maxFeeRawMeta,
        maxFeeRaw.isAcceptableOrUnknown(data['max_fee_raw']!, _maxFeeRawMeta),
      );
    }
    if (data.containsKey('gas_limit_raw')) {
      context.handle(
        _gasLimitRawMeta,
        gasLimitRaw.isAcceptableOrUnknown(
          data['gas_limit_raw']!,
          _gasLimitRawMeta,
        ),
      );
    }
    if (data.containsKey('replaces_id')) {
      context.handle(
        _replacesIdMeta,
        replacesId.isAcceptableOrUnknown(data['replaces_id']!, _replacesIdMeta),
      );
    }
    if (data.containsKey('replaced_by_id')) {
      context.handle(
        _replacedByIdMeta,
        replacedById.isAcceptableOrUnknown(
          data['replaced_by_id']!,
          _replacedByIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      reqId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}req_id'],
      ),
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      contract: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract'],
      ),
      direction: $TransactionsTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}direction'],
        )!,
      ),
      fromAddr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_addr'],
      )!,
      toAddr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_addr'],
      )!,
      amountRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_raw'],
      )!,
      feeRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fee_raw'],
      ),
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      ),
      status: $TransactionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      signMode: $TransactionsTable.$convertersignMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sign_mode'],
        )!,
      ),
      memo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}memo'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      broadcastAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}broadcast_at'],
      ),
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nonce'],
      ),
      maxPriorityFeeRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}max_priority_fee_raw'],
      ),
      maxFeeRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}max_fee_raw'],
      ),
      gasLimitRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gas_limit_raw'],
      ),
      replacesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replaces_id'],
      ),
      replacedById: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replaced_by_id'],
      ),
      replacementKind: $TransactionsTable.$converterreplacementKindn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}replacement_kind'],
        ),
      ),
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TxDirection, int, int> $converterdirection =
      const EnumIndexConverter<TxDirection>(TxDirection.values);
  static JsonTypeConverter2<TxStatus, int, int> $converterstatus =
      const EnumIndexConverter<TxStatus>(TxStatus.values);
  static JsonTypeConverter2<SignMode, int, int> $convertersignMode =
      const EnumIndexConverter<SignMode>(SignMode.values);
  static JsonTypeConverter2<TxReplacementKind, int, int>
  $converterreplacementKind = const EnumIndexConverter<TxReplacementKind>(
    TxReplacementKind.values,
  );
  static JsonTypeConverter2<TxReplacementKind?, int?, int?>
  $converterreplacementKindn = JsonTypeConverter2.asNullable(
    $converterreplacementKind,
  );
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final String id;
  final String walletId;
  final String? reqId;
  final String coin;
  final String? contract;
  final TxDirection direction;
  final String fromAddr;
  final String toAddr;
  final String amountRaw;
  final String? feeRaw;
  final String? hash;
  final TxStatus status;
  final SignMode signMode;
  final String? memo;
  final int createdAt;
  final int? broadcastAt;

  /// EVM replacement metadata. Quantities remain decimal strings so nonce and
  /// fees never lose precision. They are null for TRON, Solana and legacy rows.
  final String? nonce;
  final String? maxPriorityFeeRaw;
  final String? maxFeeRaw;
  final String? gasLimitRaw;

  /// Replacement lineage. A successfully accepted replacement sets the
  /// original row's [replacedById]; the new row points back with [replacesId].
  final String? replacesId;
  final String? replacedById;
  final TxReplacementKind? replacementKind;
  const Transaction({
    required this.id,
    required this.walletId,
    this.reqId,
    required this.coin,
    this.contract,
    required this.direction,
    required this.fromAddr,
    required this.toAddr,
    required this.amountRaw,
    this.feeRaw,
    this.hash,
    required this.status,
    required this.signMode,
    this.memo,
    required this.createdAt,
    this.broadcastAt,
    this.nonce,
    this.maxPriorityFeeRaw,
    this.maxFeeRaw,
    this.gasLimitRaw,
    this.replacesId,
    this.replacedById,
    this.replacementKind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['wallet_id'] = Variable<String>(walletId);
    if (!nullToAbsent || reqId != null) {
      map['req_id'] = Variable<String>(reqId);
    }
    map['coin'] = Variable<String>(coin);
    if (!nullToAbsent || contract != null) {
      map['contract'] = Variable<String>(contract);
    }
    {
      map['direction'] = Variable<int>(
        $TransactionsTable.$converterdirection.toSql(direction),
      );
    }
    map['from_addr'] = Variable<String>(fromAddr);
    map['to_addr'] = Variable<String>(toAddr);
    map['amount_raw'] = Variable<String>(amountRaw);
    if (!nullToAbsent || feeRaw != null) {
      map['fee_raw'] = Variable<String>(feeRaw);
    }
    if (!nullToAbsent || hash != null) {
      map['hash'] = Variable<String>(hash);
    }
    {
      map['status'] = Variable<int>(
        $TransactionsTable.$converterstatus.toSql(status),
      );
    }
    {
      map['sign_mode'] = Variable<int>(
        $TransactionsTable.$convertersignMode.toSql(signMode),
      );
    }
    if (!nullToAbsent || memo != null) {
      map['memo'] = Variable<String>(memo);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || broadcastAt != null) {
      map['broadcast_at'] = Variable<int>(broadcastAt);
    }
    if (!nullToAbsent || nonce != null) {
      map['nonce'] = Variable<String>(nonce);
    }
    if (!nullToAbsent || maxPriorityFeeRaw != null) {
      map['max_priority_fee_raw'] = Variable<String>(maxPriorityFeeRaw);
    }
    if (!nullToAbsent || maxFeeRaw != null) {
      map['max_fee_raw'] = Variable<String>(maxFeeRaw);
    }
    if (!nullToAbsent || gasLimitRaw != null) {
      map['gas_limit_raw'] = Variable<String>(gasLimitRaw);
    }
    if (!nullToAbsent || replacesId != null) {
      map['replaces_id'] = Variable<String>(replacesId);
    }
    if (!nullToAbsent || replacedById != null) {
      map['replaced_by_id'] = Variable<String>(replacedById);
    }
    if (!nullToAbsent || replacementKind != null) {
      map['replacement_kind'] = Variable<int>(
        $TransactionsTable.$converterreplacementKindn.toSql(replacementKind),
      );
    }
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      walletId: Value(walletId),
      reqId: reqId == null && nullToAbsent
          ? const Value.absent()
          : Value(reqId),
      coin: Value(coin),
      contract: contract == null && nullToAbsent
          ? const Value.absent()
          : Value(contract),
      direction: Value(direction),
      fromAddr: Value(fromAddr),
      toAddr: Value(toAddr),
      amountRaw: Value(amountRaw),
      feeRaw: feeRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(feeRaw),
      hash: hash == null && nullToAbsent ? const Value.absent() : Value(hash),
      status: Value(status),
      signMode: Value(signMode),
      memo: memo == null && nullToAbsent ? const Value.absent() : Value(memo),
      createdAt: Value(createdAt),
      broadcastAt: broadcastAt == null && nullToAbsent
          ? const Value.absent()
          : Value(broadcastAt),
      nonce: nonce == null && nullToAbsent
          ? const Value.absent()
          : Value(nonce),
      maxPriorityFeeRaw: maxPriorityFeeRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(maxPriorityFeeRaw),
      maxFeeRaw: maxFeeRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(maxFeeRaw),
      gasLimitRaw: gasLimitRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(gasLimitRaw),
      replacesId: replacesId == null && nullToAbsent
          ? const Value.absent()
          : Value(replacesId),
      replacedById: replacedById == null && nullToAbsent
          ? const Value.absent()
          : Value(replacedById),
      replacementKind: replacementKind == null && nullToAbsent
          ? const Value.absent()
          : Value(replacementKind),
    );
  }

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<String>(json['id']),
      walletId: serializer.fromJson<String>(json['walletId']),
      reqId: serializer.fromJson<String?>(json['reqId']),
      coin: serializer.fromJson<String>(json['coin']),
      contract: serializer.fromJson<String?>(json['contract']),
      direction: $TransactionsTable.$converterdirection.fromJson(
        serializer.fromJson<int>(json['direction']),
      ),
      fromAddr: serializer.fromJson<String>(json['fromAddr']),
      toAddr: serializer.fromJson<String>(json['toAddr']),
      amountRaw: serializer.fromJson<String>(json['amountRaw']),
      feeRaw: serializer.fromJson<String?>(json['feeRaw']),
      hash: serializer.fromJson<String?>(json['hash']),
      status: $TransactionsTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      signMode: $TransactionsTable.$convertersignMode.fromJson(
        serializer.fromJson<int>(json['signMode']),
      ),
      memo: serializer.fromJson<String?>(json['memo']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      broadcastAt: serializer.fromJson<int?>(json['broadcastAt']),
      nonce: serializer.fromJson<String?>(json['nonce']),
      maxPriorityFeeRaw: serializer.fromJson<String?>(
        json['maxPriorityFeeRaw'],
      ),
      maxFeeRaw: serializer.fromJson<String?>(json['maxFeeRaw']),
      gasLimitRaw: serializer.fromJson<String?>(json['gasLimitRaw']),
      replacesId: serializer.fromJson<String?>(json['replacesId']),
      replacedById: serializer.fromJson<String?>(json['replacedById']),
      replacementKind: $TransactionsTable.$converterreplacementKindn.fromJson(
        serializer.fromJson<int?>(json['replacementKind']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'walletId': serializer.toJson<String>(walletId),
      'reqId': serializer.toJson<String?>(reqId),
      'coin': serializer.toJson<String>(coin),
      'contract': serializer.toJson<String?>(contract),
      'direction': serializer.toJson<int>(
        $TransactionsTable.$converterdirection.toJson(direction),
      ),
      'fromAddr': serializer.toJson<String>(fromAddr),
      'toAddr': serializer.toJson<String>(toAddr),
      'amountRaw': serializer.toJson<String>(amountRaw),
      'feeRaw': serializer.toJson<String?>(feeRaw),
      'hash': serializer.toJson<String?>(hash),
      'status': serializer.toJson<int>(
        $TransactionsTable.$converterstatus.toJson(status),
      ),
      'signMode': serializer.toJson<int>(
        $TransactionsTable.$convertersignMode.toJson(signMode),
      ),
      'memo': serializer.toJson<String?>(memo),
      'createdAt': serializer.toJson<int>(createdAt),
      'broadcastAt': serializer.toJson<int?>(broadcastAt),
      'nonce': serializer.toJson<String?>(nonce),
      'maxPriorityFeeRaw': serializer.toJson<String?>(maxPriorityFeeRaw),
      'maxFeeRaw': serializer.toJson<String?>(maxFeeRaw),
      'gasLimitRaw': serializer.toJson<String?>(gasLimitRaw),
      'replacesId': serializer.toJson<String?>(replacesId),
      'replacedById': serializer.toJson<String?>(replacedById),
      'replacementKind': serializer.toJson<int?>(
        $TransactionsTable.$converterreplacementKindn.toJson(replacementKind),
      ),
    };
  }

  Transaction copyWith({
    String? id,
    String? walletId,
    Value<String?> reqId = const Value.absent(),
    String? coin,
    Value<String?> contract = const Value.absent(),
    TxDirection? direction,
    String? fromAddr,
    String? toAddr,
    String? amountRaw,
    Value<String?> feeRaw = const Value.absent(),
    Value<String?> hash = const Value.absent(),
    TxStatus? status,
    SignMode? signMode,
    Value<String?> memo = const Value.absent(),
    int? createdAt,
    Value<int?> broadcastAt = const Value.absent(),
    Value<String?> nonce = const Value.absent(),
    Value<String?> maxPriorityFeeRaw = const Value.absent(),
    Value<String?> maxFeeRaw = const Value.absent(),
    Value<String?> gasLimitRaw = const Value.absent(),
    Value<String?> replacesId = const Value.absent(),
    Value<String?> replacedById = const Value.absent(),
    Value<TxReplacementKind?> replacementKind = const Value.absent(),
  }) => Transaction(
    id: id ?? this.id,
    walletId: walletId ?? this.walletId,
    reqId: reqId.present ? reqId.value : this.reqId,
    coin: coin ?? this.coin,
    contract: contract.present ? contract.value : this.contract,
    direction: direction ?? this.direction,
    fromAddr: fromAddr ?? this.fromAddr,
    toAddr: toAddr ?? this.toAddr,
    amountRaw: amountRaw ?? this.amountRaw,
    feeRaw: feeRaw.present ? feeRaw.value : this.feeRaw,
    hash: hash.present ? hash.value : this.hash,
    status: status ?? this.status,
    signMode: signMode ?? this.signMode,
    memo: memo.present ? memo.value : this.memo,
    createdAt: createdAt ?? this.createdAt,
    broadcastAt: broadcastAt.present ? broadcastAt.value : this.broadcastAt,
    nonce: nonce.present ? nonce.value : this.nonce,
    maxPriorityFeeRaw: maxPriorityFeeRaw.present
        ? maxPriorityFeeRaw.value
        : this.maxPriorityFeeRaw,
    maxFeeRaw: maxFeeRaw.present ? maxFeeRaw.value : this.maxFeeRaw,
    gasLimitRaw: gasLimitRaw.present ? gasLimitRaw.value : this.gasLimitRaw,
    replacesId: replacesId.present ? replacesId.value : this.replacesId,
    replacedById: replacedById.present ? replacedById.value : this.replacedById,
    replacementKind: replacementKind.present
        ? replacementKind.value
        : this.replacementKind,
  );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      reqId: data.reqId.present ? data.reqId.value : this.reqId,
      coin: data.coin.present ? data.coin.value : this.coin,
      contract: data.contract.present ? data.contract.value : this.contract,
      direction: data.direction.present ? data.direction.value : this.direction,
      fromAddr: data.fromAddr.present ? data.fromAddr.value : this.fromAddr,
      toAddr: data.toAddr.present ? data.toAddr.value : this.toAddr,
      amountRaw: data.amountRaw.present ? data.amountRaw.value : this.amountRaw,
      feeRaw: data.feeRaw.present ? data.feeRaw.value : this.feeRaw,
      hash: data.hash.present ? data.hash.value : this.hash,
      status: data.status.present ? data.status.value : this.status,
      signMode: data.signMode.present ? data.signMode.value : this.signMode,
      memo: data.memo.present ? data.memo.value : this.memo,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      broadcastAt: data.broadcastAt.present
          ? data.broadcastAt.value
          : this.broadcastAt,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      maxPriorityFeeRaw: data.maxPriorityFeeRaw.present
          ? data.maxPriorityFeeRaw.value
          : this.maxPriorityFeeRaw,
      maxFeeRaw: data.maxFeeRaw.present ? data.maxFeeRaw.value : this.maxFeeRaw,
      gasLimitRaw: data.gasLimitRaw.present
          ? data.gasLimitRaw.value
          : this.gasLimitRaw,
      replacesId: data.replacesId.present
          ? data.replacesId.value
          : this.replacesId,
      replacedById: data.replacedById.present
          ? data.replacedById.value
          : this.replacedById,
      replacementKind: data.replacementKind.present
          ? data.replacementKind.value
          : this.replacementKind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('reqId: $reqId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('direction: $direction, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddr: $toAddr, ')
          ..write('amountRaw: $amountRaw, ')
          ..write('feeRaw: $feeRaw, ')
          ..write('hash: $hash, ')
          ..write('status: $status, ')
          ..write('signMode: $signMode, ')
          ..write('memo: $memo, ')
          ..write('createdAt: $createdAt, ')
          ..write('broadcastAt: $broadcastAt, ')
          ..write('nonce: $nonce, ')
          ..write('maxPriorityFeeRaw: $maxPriorityFeeRaw, ')
          ..write('maxFeeRaw: $maxFeeRaw, ')
          ..write('gasLimitRaw: $gasLimitRaw, ')
          ..write('replacesId: $replacesId, ')
          ..write('replacedById: $replacedById, ')
          ..write('replacementKind: $replacementKind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    walletId,
    reqId,
    coin,
    contract,
    direction,
    fromAddr,
    toAddr,
    amountRaw,
    feeRaw,
    hash,
    status,
    signMode,
    memo,
    createdAt,
    broadcastAt,
    nonce,
    maxPriorityFeeRaw,
    maxFeeRaw,
    gasLimitRaw,
    replacesId,
    replacedById,
    replacementKind,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.walletId == this.walletId &&
          other.reqId == this.reqId &&
          other.coin == this.coin &&
          other.contract == this.contract &&
          other.direction == this.direction &&
          other.fromAddr == this.fromAddr &&
          other.toAddr == this.toAddr &&
          other.amountRaw == this.amountRaw &&
          other.feeRaw == this.feeRaw &&
          other.hash == this.hash &&
          other.status == this.status &&
          other.signMode == this.signMode &&
          other.memo == this.memo &&
          other.createdAt == this.createdAt &&
          other.broadcastAt == this.broadcastAt &&
          other.nonce == this.nonce &&
          other.maxPriorityFeeRaw == this.maxPriorityFeeRaw &&
          other.maxFeeRaw == this.maxFeeRaw &&
          other.gasLimitRaw == this.gasLimitRaw &&
          other.replacesId == this.replacesId &&
          other.replacedById == this.replacedById &&
          other.replacementKind == this.replacementKind);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<String> id;
  final Value<String> walletId;
  final Value<String?> reqId;
  final Value<String> coin;
  final Value<String?> contract;
  final Value<TxDirection> direction;
  final Value<String> fromAddr;
  final Value<String> toAddr;
  final Value<String> amountRaw;
  final Value<String?> feeRaw;
  final Value<String?> hash;
  final Value<TxStatus> status;
  final Value<SignMode> signMode;
  final Value<String?> memo;
  final Value<int> createdAt;
  final Value<int?> broadcastAt;
  final Value<String?> nonce;
  final Value<String?> maxPriorityFeeRaw;
  final Value<String?> maxFeeRaw;
  final Value<String?> gasLimitRaw;
  final Value<String?> replacesId;
  final Value<String?> replacedById;
  final Value<TxReplacementKind?> replacementKind;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.walletId = const Value.absent(),
    this.reqId = const Value.absent(),
    this.coin = const Value.absent(),
    this.contract = const Value.absent(),
    this.direction = const Value.absent(),
    this.fromAddr = const Value.absent(),
    this.toAddr = const Value.absent(),
    this.amountRaw = const Value.absent(),
    this.feeRaw = const Value.absent(),
    this.hash = const Value.absent(),
    this.status = const Value.absent(),
    this.signMode = const Value.absent(),
    this.memo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.broadcastAt = const Value.absent(),
    this.nonce = const Value.absent(),
    this.maxPriorityFeeRaw = const Value.absent(),
    this.maxFeeRaw = const Value.absent(),
    this.gasLimitRaw = const Value.absent(),
    this.replacesId = const Value.absent(),
    this.replacedById = const Value.absent(),
    this.replacementKind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required String walletId,
    this.reqId = const Value.absent(),
    required String coin,
    this.contract = const Value.absent(),
    required TxDirection direction,
    required String fromAddr,
    required String toAddr,
    required String amountRaw,
    this.feeRaw = const Value.absent(),
    this.hash = const Value.absent(),
    required TxStatus status,
    required SignMode signMode,
    this.memo = const Value.absent(),
    required int createdAt,
    this.broadcastAt = const Value.absent(),
    this.nonce = const Value.absent(),
    this.maxPriorityFeeRaw = const Value.absent(),
    this.maxFeeRaw = const Value.absent(),
    this.gasLimitRaw = const Value.absent(),
    this.replacesId = const Value.absent(),
    this.replacedById = const Value.absent(),
    this.replacementKind = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       walletId = Value(walletId),
       coin = Value(coin),
       direction = Value(direction),
       fromAddr = Value(fromAddr),
       toAddr = Value(toAddr),
       amountRaw = Value(amountRaw),
       status = Value(status),
       signMode = Value(signMode),
       createdAt = Value(createdAt);
  static Insertable<Transaction> custom({
    Expression<String>? id,
    Expression<String>? walletId,
    Expression<String>? reqId,
    Expression<String>? coin,
    Expression<String>? contract,
    Expression<int>? direction,
    Expression<String>? fromAddr,
    Expression<String>? toAddr,
    Expression<String>? amountRaw,
    Expression<String>? feeRaw,
    Expression<String>? hash,
    Expression<int>? status,
    Expression<int>? signMode,
    Expression<String>? memo,
    Expression<int>? createdAt,
    Expression<int>? broadcastAt,
    Expression<String>? nonce,
    Expression<String>? maxPriorityFeeRaw,
    Expression<String>? maxFeeRaw,
    Expression<String>? gasLimitRaw,
    Expression<String>? replacesId,
    Expression<String>? replacedById,
    Expression<int>? replacementKind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (walletId != null) 'wallet_id': walletId,
      if (reqId != null) 'req_id': reqId,
      if (coin != null) 'coin': coin,
      if (contract != null) 'contract': contract,
      if (direction != null) 'direction': direction,
      if (fromAddr != null) 'from_addr': fromAddr,
      if (toAddr != null) 'to_addr': toAddr,
      if (amountRaw != null) 'amount_raw': amountRaw,
      if (feeRaw != null) 'fee_raw': feeRaw,
      if (hash != null) 'hash': hash,
      if (status != null) 'status': status,
      if (signMode != null) 'sign_mode': signMode,
      if (memo != null) 'memo': memo,
      if (createdAt != null) 'created_at': createdAt,
      if (broadcastAt != null) 'broadcast_at': broadcastAt,
      if (nonce != null) 'nonce': nonce,
      if (maxPriorityFeeRaw != null) 'max_priority_fee_raw': maxPriorityFeeRaw,
      if (maxFeeRaw != null) 'max_fee_raw': maxFeeRaw,
      if (gasLimitRaw != null) 'gas_limit_raw': gasLimitRaw,
      if (replacesId != null) 'replaces_id': replacesId,
      if (replacedById != null) 'replaced_by_id': replacedById,
      if (replacementKind != null) 'replacement_kind': replacementKind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? walletId,
    Value<String?>? reqId,
    Value<String>? coin,
    Value<String?>? contract,
    Value<TxDirection>? direction,
    Value<String>? fromAddr,
    Value<String>? toAddr,
    Value<String>? amountRaw,
    Value<String?>? feeRaw,
    Value<String?>? hash,
    Value<TxStatus>? status,
    Value<SignMode>? signMode,
    Value<String?>? memo,
    Value<int>? createdAt,
    Value<int?>? broadcastAt,
    Value<String?>? nonce,
    Value<String?>? maxPriorityFeeRaw,
    Value<String?>? maxFeeRaw,
    Value<String?>? gasLimitRaw,
    Value<String?>? replacesId,
    Value<String?>? replacedById,
    Value<TxReplacementKind?>? replacementKind,
    Value<int>? rowid,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      reqId: reqId ?? this.reqId,
      coin: coin ?? this.coin,
      contract: contract ?? this.contract,
      direction: direction ?? this.direction,
      fromAddr: fromAddr ?? this.fromAddr,
      toAddr: toAddr ?? this.toAddr,
      amountRaw: amountRaw ?? this.amountRaw,
      feeRaw: feeRaw ?? this.feeRaw,
      hash: hash ?? this.hash,
      status: status ?? this.status,
      signMode: signMode ?? this.signMode,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      broadcastAt: broadcastAt ?? this.broadcastAt,
      nonce: nonce ?? this.nonce,
      maxPriorityFeeRaw: maxPriorityFeeRaw ?? this.maxPriorityFeeRaw,
      maxFeeRaw: maxFeeRaw ?? this.maxFeeRaw,
      gasLimitRaw: gasLimitRaw ?? this.gasLimitRaw,
      replacesId: replacesId ?? this.replacesId,
      replacedById: replacedById ?? this.replacedById,
      replacementKind: replacementKind ?? this.replacementKind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (reqId.present) {
      map['req_id'] = Variable<String>(reqId.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (contract.present) {
      map['contract'] = Variable<String>(contract.value);
    }
    if (direction.present) {
      map['direction'] = Variable<int>(
        $TransactionsTable.$converterdirection.toSql(direction.value),
      );
    }
    if (fromAddr.present) {
      map['from_addr'] = Variable<String>(fromAddr.value);
    }
    if (toAddr.present) {
      map['to_addr'] = Variable<String>(toAddr.value);
    }
    if (amountRaw.present) {
      map['amount_raw'] = Variable<String>(amountRaw.value);
    }
    if (feeRaw.present) {
      map['fee_raw'] = Variable<String>(feeRaw.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $TransactionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (signMode.present) {
      map['sign_mode'] = Variable<int>(
        $TransactionsTable.$convertersignMode.toSql(signMode.value),
      );
    }
    if (memo.present) {
      map['memo'] = Variable<String>(memo.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (broadcastAt.present) {
      map['broadcast_at'] = Variable<int>(broadcastAt.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<String>(nonce.value);
    }
    if (maxPriorityFeeRaw.present) {
      map['max_priority_fee_raw'] = Variable<String>(maxPriorityFeeRaw.value);
    }
    if (maxFeeRaw.present) {
      map['max_fee_raw'] = Variable<String>(maxFeeRaw.value);
    }
    if (gasLimitRaw.present) {
      map['gas_limit_raw'] = Variable<String>(gasLimitRaw.value);
    }
    if (replacesId.present) {
      map['replaces_id'] = Variable<String>(replacesId.value);
    }
    if (replacedById.present) {
      map['replaced_by_id'] = Variable<String>(replacedById.value);
    }
    if (replacementKind.present) {
      map['replacement_kind'] = Variable<int>(
        $TransactionsTable.$converterreplacementKindn.toSql(
          replacementKind.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('reqId: $reqId, ')
          ..write('coin: $coin, ')
          ..write('contract: $contract, ')
          ..write('direction: $direction, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddr: $toAddr, ')
          ..write('amountRaw: $amountRaw, ')
          ..write('feeRaw: $feeRaw, ')
          ..write('hash: $hash, ')
          ..write('status: $status, ')
          ..write('signMode: $signMode, ')
          ..write('memo: $memo, ')
          ..write('createdAt: $createdAt, ')
          ..write('broadcastAt: $broadcastAt, ')
          ..write('nonce: $nonce, ')
          ..write('maxPriorityFeeRaw: $maxPriorityFeeRaw, ')
          ..write('maxFeeRaw: $maxFeeRaw, ')
          ..write('gasLimitRaw: $gasLimitRaw, ')
          ..write('replacesId: $replacesId, ')
          ..write('replacedById: $replacedById, ')
          ..write('replacementKind: $replacementKind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AddressBookTable extends AddressBook
    with TableInfo<$AddressBookTable, AddressBookData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddressBookTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    walletId,
    name,
    address,
    coin,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'address_book';
  @override
  VerificationContext validateIntegrity(
    Insertable<AddressBookData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('coin')) {
      context.handle(
        _coinMeta,
        coin.isAcceptableOrUnknown(data['coin']!, _coinMeta),
      );
    } else if (isInserting) {
      context.missing(_coinMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AddressBookData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AddressBookData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      coin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coin'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AddressBookTable createAlias(String alias) {
    return $AddressBookTable(attachedDatabase, alias);
  }
}

class AddressBookData extends DataClass implements Insertable<AddressBookData> {
  final String id;
  final String walletId;
  final String name;
  final String address;
  final String coin;
  final int createdAt;
  const AddressBookData({
    required this.id,
    required this.walletId,
    required this.name,
    required this.address,
    required this.coin,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['wallet_id'] = Variable<String>(walletId);
    map['name'] = Variable<String>(name);
    map['address'] = Variable<String>(address);
    map['coin'] = Variable<String>(coin);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AddressBookCompanion toCompanion(bool nullToAbsent) {
    return AddressBookCompanion(
      id: Value(id),
      walletId: Value(walletId),
      name: Value(name),
      address: Value(address),
      coin: Value(coin),
      createdAt: Value(createdAt),
    );
  }

  factory AddressBookData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AddressBookData(
      id: serializer.fromJson<String>(json['id']),
      walletId: serializer.fromJson<String>(json['walletId']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String>(json['address']),
      coin: serializer.fromJson<String>(json['coin']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'walletId': serializer.toJson<String>(walletId),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String>(address),
      'coin': serializer.toJson<String>(coin),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AddressBookData copyWith({
    String? id,
    String? walletId,
    String? name,
    String? address,
    String? coin,
    int? createdAt,
  }) => AddressBookData(
    id: id ?? this.id,
    walletId: walletId ?? this.walletId,
    name: name ?? this.name,
    address: address ?? this.address,
    coin: coin ?? this.coin,
    createdAt: createdAt ?? this.createdAt,
  );
  AddressBookData copyWithCompanion(AddressBookCompanion data) {
    return AddressBookData(
      id: data.id.present ? data.id.value : this.id,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      coin: data.coin.present ? data.coin.value : this.coin,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AddressBookData(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('coin: $coin, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, walletId, name, address, coin, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddressBookData &&
          other.id == this.id &&
          other.walletId == this.walletId &&
          other.name == this.name &&
          other.address == this.address &&
          other.coin == this.coin &&
          other.createdAt == this.createdAt);
}

class AddressBookCompanion extends UpdateCompanion<AddressBookData> {
  final Value<String> id;
  final Value<String> walletId;
  final Value<String> name;
  final Value<String> address;
  final Value<String> coin;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AddressBookCompanion({
    this.id = const Value.absent(),
    this.walletId = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.coin = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AddressBookCompanion.insert({
    required String id,
    required String walletId,
    required String name,
    required String address,
    required String coin,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       walletId = Value(walletId),
       name = Value(name),
       address = Value(address),
       coin = Value(coin),
       createdAt = Value(createdAt);
  static Insertable<AddressBookData> custom({
    Expression<String>? id,
    Expression<String>? walletId,
    Expression<String>? name,
    Expression<String>? address,
    Expression<String>? coin,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (walletId != null) 'wallet_id': walletId,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (coin != null) 'coin': coin,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AddressBookCompanion copyWith({
    Value<String>? id,
    Value<String>? walletId,
    Value<String>? name,
    Value<String>? address,
    Value<String>? coin,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AddressBookCompanion(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      name: name ?? this.name,
      address: address ?? this.address,
      coin: coin ?? this.coin,
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
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (coin.present) {
      map['coin'] = Variable<String>(coin.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddressBookCompanion(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('coin: $coin, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignRequestsTable extends SignRequests
    with TableInfo<$SignRequestsTable, SignRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignRequestsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _rawTxMeta = const VerificationMeta('rawTx');
  @override
  late final GeneratedColumn<Uint8List> rawTx = GeneratedColumn<Uint8List>(
    'raw_tx',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
    rawTx,
    expiresAt,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sign_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignRequest> instance, {
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
    if (data.containsKey('raw_tx')) {
      context.handle(
        _rawTxMeta,
        rawTx.isAcceptableOrUnknown(data['raw_tx']!, _rawTxMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTxMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
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
  SignRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignRequest(
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
      rawTx: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}raw_tx'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $SignRequestsTable createAlias(String alias) {
    return $SignRequestsTable(attachedDatabase, alias);
  }
}

class SignRequest extends DataClass implements Insertable<SignRequest> {
  final String reqId;
  final String walletId;
  final String coin;
  final Uint8List rawTx;
  final int expiresAt;
  final String status;
  const SignRequest({
    required this.reqId,
    required this.walletId,
    required this.coin,
    required this.rawTx,
    required this.expiresAt,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['req_id'] = Variable<String>(reqId);
    map['wallet_id'] = Variable<String>(walletId);
    map['coin'] = Variable<String>(coin);
    map['raw_tx'] = Variable<Uint8List>(rawTx);
    map['expires_at'] = Variable<int>(expiresAt);
    map['status'] = Variable<String>(status);
    return map;
  }

  SignRequestsCompanion toCompanion(bool nullToAbsent) {
    return SignRequestsCompanion(
      reqId: Value(reqId),
      walletId: Value(walletId),
      coin: Value(coin),
      rawTx: Value(rawTx),
      expiresAt: Value(expiresAt),
      status: Value(status),
    );
  }

  factory SignRequest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignRequest(
      reqId: serializer.fromJson<String>(json['reqId']),
      walletId: serializer.fromJson<String>(json['walletId']),
      coin: serializer.fromJson<String>(json['coin']),
      rawTx: serializer.fromJson<Uint8List>(json['rawTx']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
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
      'rawTx': serializer.toJson<Uint8List>(rawTx),
      'expiresAt': serializer.toJson<int>(expiresAt),
      'status': serializer.toJson<String>(status),
    };
  }

  SignRequest copyWith({
    String? reqId,
    String? walletId,
    String? coin,
    Uint8List? rawTx,
    int? expiresAt,
    String? status,
  }) => SignRequest(
    reqId: reqId ?? this.reqId,
    walletId: walletId ?? this.walletId,
    coin: coin ?? this.coin,
    rawTx: rawTx ?? this.rawTx,
    expiresAt: expiresAt ?? this.expiresAt,
    status: status ?? this.status,
  );
  SignRequest copyWithCompanion(SignRequestsCompanion data) {
    return SignRequest(
      reqId: data.reqId.present ? data.reqId.value : this.reqId,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      coin: data.coin.present ? data.coin.value : this.coin,
      rawTx: data.rawTx.present ? data.rawTx.value : this.rawTx,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignRequest(')
          ..write('reqId: $reqId, ')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('rawTx: $rawTx, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    reqId,
    walletId,
    coin,
    $driftBlobEquality.hash(rawTx),
    expiresAt,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignRequest &&
          other.reqId == this.reqId &&
          other.walletId == this.walletId &&
          other.coin == this.coin &&
          $driftBlobEquality.equals(other.rawTx, this.rawTx) &&
          other.expiresAt == this.expiresAt &&
          other.status == this.status);
}

class SignRequestsCompanion extends UpdateCompanion<SignRequest> {
  final Value<String> reqId;
  final Value<String> walletId;
  final Value<String> coin;
  final Value<Uint8List> rawTx;
  final Value<int> expiresAt;
  final Value<String> status;
  final Value<int> rowid;
  const SignRequestsCompanion({
    this.reqId = const Value.absent(),
    this.walletId = const Value.absent(),
    this.coin = const Value.absent(),
    this.rawTx = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignRequestsCompanion.insert({
    required String reqId,
    required String walletId,
    required String coin,
    required Uint8List rawTx,
    required int expiresAt,
    required String status,
    this.rowid = const Value.absent(),
  }) : reqId = Value(reqId),
       walletId = Value(walletId),
       coin = Value(coin),
       rawTx = Value(rawTx),
       expiresAt = Value(expiresAt),
       status = Value(status);
  static Insertable<SignRequest> custom({
    Expression<String>? reqId,
    Expression<String>? walletId,
    Expression<String>? coin,
    Expression<Uint8List>? rawTx,
    Expression<int>? expiresAt,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (reqId != null) 'req_id': reqId,
      if (walletId != null) 'wallet_id': walletId,
      if (coin != null) 'coin': coin,
      if (rawTx != null) 'raw_tx': rawTx,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignRequestsCompanion copyWith({
    Value<String>? reqId,
    Value<String>? walletId,
    Value<String>? coin,
    Value<Uint8List>? rawTx,
    Value<int>? expiresAt,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return SignRequestsCompanion(
      reqId: reqId ?? this.reqId,
      walletId: walletId ?? this.walletId,
      coin: coin ?? this.coin,
      rawTx: rawTx ?? this.rawTx,
      expiresAt: expiresAt ?? this.expiresAt,
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
    if (rawTx.present) {
      map['raw_tx'] = Variable<Uint8List>(rawTx.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
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
    return (StringBuffer('SignRequestsCompanion(')
          ..write('reqId: $reqId, ')
          ..write('walletId: $walletId, ')
          ..write('coin: $coin, ')
          ..write('rawTx: $rawTx, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WalletSettingsTable extends WalletSettings
    with TableInfo<$WalletSettingsTable, WalletSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletSettingsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [walletId, key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallet_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<WalletSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {walletId, key};
  @override
  WalletSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WalletSetting(
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $WalletSettingsTable createAlias(String alias) {
    return $WalletSettingsTable(attachedDatabase, alias);
  }
}

class WalletSetting extends DataClass implements Insertable<WalletSetting> {
  final String walletId;
  final String key;
  final String value;
  const WalletSetting({
    required this.walletId,
    required this.key,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['wallet_id'] = Variable<String>(walletId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  WalletSettingsCompanion toCompanion(bool nullToAbsent) {
    return WalletSettingsCompanion(
      walletId: Value(walletId),
      key: Value(key),
      value: Value(value),
    );
  }

  factory WalletSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WalletSetting(
      walletId: serializer.fromJson<String>(json['walletId']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'walletId': serializer.toJson<String>(walletId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  WalletSetting copyWith({String? walletId, String? key, String? value}) =>
      WalletSetting(
        walletId: walletId ?? this.walletId,
        key: key ?? this.key,
        value: value ?? this.value,
      );
  WalletSetting copyWithCompanion(WalletSettingsCompanion data) {
    return WalletSetting(
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WalletSetting(')
          ..write('walletId: $walletId, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(walletId, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletSetting &&
          other.walletId == this.walletId &&
          other.key == this.key &&
          other.value == this.value);
}

class WalletSettingsCompanion extends UpdateCompanion<WalletSetting> {
  final Value<String> walletId;
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const WalletSettingsCompanion({
    this.walletId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WalletSettingsCompanion.insert({
    required String walletId,
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : walletId = Value(walletId),
       key = Value(key),
       value = Value(value);
  static Insertable<WalletSetting> custom({
    Expression<String>? walletId,
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (walletId != null) 'wallet_id': walletId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WalletSettingsCompanion copyWith({
    Value<String>? walletId,
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return WalletSettingsCompanion(
      walletId: walletId ?? this.walletId,
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletSettingsCompanion(')
          ..write('walletId: $walletId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainMeta = const VerificationMeta('chain');
  @override
  late final GeneratedColumn<String> chain = GeneratedColumn<String>(
    'chain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, address, chain, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Contact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('chain')) {
      context.handle(
        _chainMeta,
        chain.isAcceptableOrUnknown(data['chain']!, _chainMeta),
      );
    } else if (isInserting) {
      context.missing(_chainMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      chain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chain'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }
}

class Contact extends DataClass implements Insertable<Contact> {
  final String id;
  final String name;
  final String address;

  /// Canonical chain tag (e.g. 'ethereum', 'tron'). Stored as text because
  /// wallet_data has no dependency on the chains package's enum.
  final String chain;
  final int createdAt;
  const Contact({
    required this.id,
    required this.name,
    required this.address,
    required this.chain,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['address'] = Variable<String>(address);
    map['chain'] = Variable<String>(chain);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      id: Value(id),
      name: Value(name),
      address: Value(address),
      chain: Value(chain),
      createdAt: Value(createdAt),
    );
  }

  factory Contact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Contact(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String>(json['address']),
      chain: serializer.fromJson<String>(json['chain']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String>(address),
      'chain': serializer.toJson<String>(chain),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Contact copyWith({
    String? id,
    String? name,
    String? address,
    String? chain,
    int? createdAt,
  }) => Contact(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address ?? this.address,
    chain: chain ?? this.chain,
    createdAt: createdAt ?? this.createdAt,
  );
  Contact copyWithCompanion(ContactsCompanion data) {
    return Contact(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      chain: data.chain.present ? data.chain.value : this.chain,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Contact(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('chain: $chain, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, address, chain, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Contact &&
          other.id == this.id &&
          other.name == this.name &&
          other.address == this.address &&
          other.chain == this.chain &&
          other.createdAt == this.createdAt);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> address;
  final Value<String> chain;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ContactsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.chain = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContactsCompanion.insert({
    required String id,
    required String name,
    required String address,
    required String chain,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       address = Value(address),
       chain = Value(chain),
       createdAt = Value(createdAt);
  static Insertable<Contact> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? address,
    Expression<String>? chain,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (chain != null) 'chain': chain,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContactsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? address,
    Value<String>? chain,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ContactsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      chain: chain ?? this.chain,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (chain.present) {
      map['chain'] = Variable<String>(chain.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('chain: $chain, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomTokensTable extends CustomTokens
    with TableInfo<$CustomTokensTable, CustomToken> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomTokensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contractMeta = const VerificationMeta(
    'contract',
  );
  @override
  late final GeneratedColumn<String> contract = GeneratedColumn<String>(
    'contract',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    symbol,
    name,
    contract,
    network,
    enabled,
    sortOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_tokens';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomToken> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('contract')) {
      context.handle(
        _contractMeta,
        contract.isAcceptableOrUnknown(data['contract']!, _contractMeta),
      );
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomToken map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomToken(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      contract: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract'],
      ),
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CustomTokensTable createAlias(String alias) {
    return $CustomTokensTable(attachedDatabase, alias);
  }
}

class CustomToken extends DataClass implements Insertable<CustomToken> {
  final String id;
  final String symbol;
  final String name;
  final String? contract;

  /// Display label for where the token lives (e.g. 'TRON · TRC-20').
  final String network;
  final bool enabled;
  final int sortOrder;
  final int createdAt;
  const CustomToken({
    required this.id,
    required this.symbol,
    required this.name,
    this.contract,
    required this.network,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['symbol'] = Variable<String>(symbol);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || contract != null) {
      map['contract'] = Variable<String>(contract);
    }
    map['network'] = Variable<String>(network);
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CustomTokensCompanion toCompanion(bool nullToAbsent) {
    return CustomTokensCompanion(
      id: Value(id),
      symbol: Value(symbol),
      name: Value(name),
      contract: contract == null && nullToAbsent
          ? const Value.absent()
          : Value(contract),
      network: Value(network),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }

  factory CustomToken.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomToken(
      id: serializer.fromJson<String>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      name: serializer.fromJson<String>(json['name']),
      contract: serializer.fromJson<String?>(json['contract']),
      network: serializer.fromJson<String>(json['network']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'symbol': serializer.toJson<String>(symbol),
      'name': serializer.toJson<String>(name),
      'contract': serializer.toJson<String?>(contract),
      'network': serializer.toJson<String>(network),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CustomToken copyWith({
    String? id,
    String? symbol,
    String? name,
    Value<String?> contract = const Value.absent(),
    String? network,
    bool? enabled,
    int? sortOrder,
    int? createdAt,
  }) => CustomToken(
    id: id ?? this.id,
    symbol: symbol ?? this.symbol,
    name: name ?? this.name,
    contract: contract.present ? contract.value : this.contract,
    network: network ?? this.network,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  CustomToken copyWithCompanion(CustomTokensCompanion data) {
    return CustomToken(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      name: data.name.present ? data.name.value : this.name,
      contract: data.contract.present ? data.contract.value : this.contract,
      network: data.network.present ? data.network.value : this.network,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomToken(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('contract: $contract, ')
          ..write('network: $network, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    symbol,
    name,
    contract,
    network,
    enabled,
    sortOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomToken &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.contract == this.contract &&
          other.network == this.network &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class CustomTokensCompanion extends UpdateCompanion<CustomToken> {
  final Value<String> id;
  final Value<String> symbol;
  final Value<String> name;
  final Value<String?> contract;
  final Value<String> network;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> rowid;
  const CustomTokensCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
    this.name = const Value.absent(),
    this.contract = const Value.absent(),
    this.network = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomTokensCompanion.insert({
    required String id,
    required String symbol,
    required String name,
    this.contract = const Value.absent(),
    required String network,
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       symbol = Value(symbol),
       name = Value(name),
       network = Value(network),
       createdAt = Value(createdAt);
  static Insertable<CustomToken> custom({
    Expression<String>? id,
    Expression<String>? symbol,
    Expression<String>? name,
    Expression<String>? contract,
    Expression<String>? network,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (name != null) 'name': name,
      if (contract != null) 'contract': contract,
      if (network != null) 'network': network,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomTokensCompanion copyWith({
    Value<String>? id,
    Value<String>? symbol,
    Value<String>? name,
    Value<String?>? contract,
    Value<String>? network,
    Value<bool>? enabled,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return CustomTokensCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      contract: contract ?? this.contract,
      network: network ?? this.network,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (contract.present) {
      map['contract'] = Variable<String>(contract.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomTokensCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('contract: $contract, ')
          ..write('network: $network, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$WalletDatabase extends GeneratedDatabase {
  _$WalletDatabase(QueryExecutor e) : super(e);
  $WalletDatabaseManager get managers => $WalletDatabaseManager(this);
  late final $WalletsTable wallets = $WalletsTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $TokensTable tokens = $TokensTable(this);
  late final $BalancesTable balances = $BalancesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $AddressBookTable addressBook = $AddressBookTable(this);
  late final $SignRequestsTable signRequests = $SignRequestsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $WalletSettingsTable walletSettings = $WalletSettingsTable(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $CustomTokensTable customTokens = $CustomTokensTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    wallets,
    accounts,
    tokens,
    balances,
    transactions,
    addressBook,
    signRequests,
    settings,
    walletSettings,
    contacts,
    customTokens,
  ];
}

typedef $$WalletsTableCreateCompanionBuilder =
    WalletsCompanion Function({
      required String id,
      required String name,
      required WalletType type,
      required int avatarColor,
      Value<int> sortOrder,
      Value<bool> backedUp,
      Value<String?> coldWalletId,
      Value<int?> protocolVer,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$WalletsTableUpdateCompanionBuilder =
    WalletsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<WalletType> type,
      Value<int> avatarColor,
      Value<int> sortOrder,
      Value<bool> backedUp,
      Value<String?> coldWalletId,
      Value<int?> protocolVer,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$WalletsTableFilterComposer
    extends Composer<_$WalletDatabase, $WalletsTable> {
  $$WalletsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WalletType, WalletType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get backedUp => $composableBuilder(
    column: $table.backedUp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coldWalletId => $composableBuilder(
    column: $table.coldWalletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVer => $composableBuilder(
    column: $table.protocolVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletsTableOrderingComposer
    extends Composer<_$WalletDatabase, $WalletsTable> {
  $$WalletsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get backedUp => $composableBuilder(
    column: $table.backedUp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coldWalletId => $composableBuilder(
    column: $table.coldWalletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVer => $composableBuilder(
    column: $table.protocolVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $WalletsTable> {
  $$WalletsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<WalletType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get backedUp =>
      $composableBuilder(column: $table.backedUp, builder: (column) => column);

  GeneratedColumn<String> get coldWalletId => $composableBuilder(
    column: $table.coldWalletId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get protocolVer => $composableBuilder(
    column: $table.protocolVer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$WalletsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $WalletsTable,
          Wallet,
          $$WalletsTableFilterComposer,
          $$WalletsTableOrderingComposer,
          $$WalletsTableAnnotationComposer,
          $$WalletsTableCreateCompanionBuilder,
          $$WalletsTableUpdateCompanionBuilder,
          (Wallet, BaseReferences<_$WalletDatabase, $WalletsTable, Wallet>),
          Wallet,
          PrefetchHooks Function()
        > {
  $$WalletsTableTableManager(_$WalletDatabase db, $WalletsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<WalletType> type = const Value.absent(),
                Value<int> avatarColor = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> backedUp = const Value.absent(),
                Value<String?> coldWalletId = const Value.absent(),
                Value<int?> protocolVer = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WalletsCompanion(
                id: id,
                name: name,
                type: type,
                avatarColor: avatarColor,
                sortOrder: sortOrder,
                backedUp: backedUp,
                coldWalletId: coldWalletId,
                protocolVer: protocolVer,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required WalletType type,
                required int avatarColor,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> backedUp = const Value.absent(),
                Value<String?> coldWalletId = const Value.absent(),
                Value<int?> protocolVer = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => WalletsCompanion.insert(
                id: id,
                name: name,
                type: type,
                avatarColor: avatarColor,
                sortOrder: sortOrder,
                backedUp: backedUp,
                coldWalletId: coldWalletId,
                protocolVer: protocolVer,
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

typedef $$WalletsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $WalletsTable,
      Wallet,
      $$WalletsTableFilterComposer,
      $$WalletsTableOrderingComposer,
      $$WalletsTableAnnotationComposer,
      $$WalletsTableCreateCompanionBuilder,
      $$WalletsTableUpdateCompanionBuilder,
      (Wallet, BaseReferences<_$WalletDatabase, $WalletsTable, Wallet>),
      Wallet,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String walletId,
      required String coin,
      required String address,
      required String derivationPath,
      required int accountIndex,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> walletId,
      Value<String> coin,
      Value<String> address,
      Value<String> derivationPath,
      Value<int> accountIndex,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$WalletDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accountIndex => $composableBuilder(
    column: $table.accountIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$WalletDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accountIndex => $composableBuilder(
    column: $table.accountIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accountIndex => $composableBuilder(
    column: $table.accountIndex,
    builder: (column) => column,
  );
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, BaseReferences<_$WalletDatabase, $AccountsTable, Account>),
          Account,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$WalletDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> walletId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> derivationPath = const Value.absent(),
                Value<int> accountIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                walletId: walletId,
                coin: coin,
                address: address,
                derivationPath: derivationPath,
                accountIndex: accountIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String walletId,
                required String coin,
                required String address,
                required String derivationPath,
                required int accountIndex,
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                walletId: walletId,
                coin: coin,
                address: address,
                derivationPath: derivationPath,
                accountIndex: accountIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, BaseReferences<_$WalletDatabase, $AccountsTable, Account>),
      Account,
      PrefetchHooks Function()
    >;
typedef $$TokensTableCreateCompanionBuilder =
    TokensCompanion Function({
      required String walletId,
      required String coin,
      Value<String> contract,
      required String symbol,
      required int decimals,
      required String name,
      Value<bool> enabled,
      Value<bool> trusted,
      Value<int> rowid,
    });
typedef $$TokensTableUpdateCompanionBuilder =
    TokensCompanion Function({
      Value<String> walletId,
      Value<String> coin,
      Value<String> contract,
      Value<String> symbol,
      Value<int> decimals,
      Value<String> name,
      Value<bool> enabled,
      Value<bool> trusted,
      Value<int> rowid,
    });

class $$TokensTableFilterComposer
    extends Composer<_$WalletDatabase, $TokensTable> {
  $$TokensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TokensTableOrderingComposer
    extends Composer<_$WalletDatabase, $TokensTable> {
  $$TokensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decimals => $composableBuilder(
    column: $table.decimals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TokensTableAnnotationComposer
    extends Composer<_$WalletDatabase, $TokensTable> {
  $$TokensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<String> get contract =>
      $composableBuilder(column: $table.contract, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<int> get decimals =>
      $composableBuilder(column: $table.decimals, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get trusted =>
      $composableBuilder(column: $table.trusted, builder: (column) => column);
}

class $$TokensTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $TokensTable,
          Token,
          $$TokensTableFilterComposer,
          $$TokensTableOrderingComposer,
          $$TokensTableAnnotationComposer,
          $$TokensTableCreateCompanionBuilder,
          $$TokensTableUpdateCompanionBuilder,
          (Token, BaseReferences<_$WalletDatabase, $TokensTable, Token>),
          Token,
          PrefetchHooks Function()
        > {
  $$TokensTableTableManager(_$WalletDatabase db, $TokensTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TokensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TokensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TokensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> walletId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<String> contract = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<int> decimals = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TokensCompanion(
                walletId: walletId,
                coin: coin,
                contract: contract,
                symbol: symbol,
                decimals: decimals,
                name: name,
                enabled: enabled,
                trusted: trusted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String walletId,
                required String coin,
                Value<String> contract = const Value.absent(),
                required String symbol,
                required int decimals,
                required String name,
                Value<bool> enabled = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TokensCompanion.insert(
                walletId: walletId,
                coin: coin,
                contract: contract,
                symbol: symbol,
                decimals: decimals,
                name: name,
                enabled: enabled,
                trusted: trusted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TokensTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $TokensTable,
      Token,
      $$TokensTableFilterComposer,
      $$TokensTableOrderingComposer,
      $$TokensTableAnnotationComposer,
      $$TokensTableCreateCompanionBuilder,
      $$TokensTableUpdateCompanionBuilder,
      (Token, BaseReferences<_$WalletDatabase, $TokensTable, Token>),
      Token,
      PrefetchHooks Function()
    >;
typedef $$BalancesTableCreateCompanionBuilder =
    BalancesCompanion Function({
      required String walletId,
      required String coin,
      Value<String> contract,
      required String raw,
      Value<double?> fiat,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$BalancesTableUpdateCompanionBuilder =
    BalancesCompanion Function({
      Value<String> walletId,
      Value<String> coin,
      Value<String> contract,
      Value<String> raw,
      Value<double?> fiat,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$BalancesTableFilterComposer
    extends Composer<_$WalletDatabase, $BalancesTable> {
  $$BalancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fiat => $composableBuilder(
    column: $table.fiat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BalancesTableOrderingComposer
    extends Composer<_$WalletDatabase, $BalancesTable> {
  $$BalancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fiat => $composableBuilder(
    column: $table.fiat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BalancesTableAnnotationComposer
    extends Composer<_$WalletDatabase, $BalancesTable> {
  $$BalancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<String> get contract =>
      $composableBuilder(column: $table.contract, builder: (column) => column);

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);

  GeneratedColumn<double> get fiat =>
      $composableBuilder(column: $table.fiat, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BalancesTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $BalancesTable,
          Balance,
          $$BalancesTableFilterComposer,
          $$BalancesTableOrderingComposer,
          $$BalancesTableAnnotationComposer,
          $$BalancesTableCreateCompanionBuilder,
          $$BalancesTableUpdateCompanionBuilder,
          (Balance, BaseReferences<_$WalletDatabase, $BalancesTable, Balance>),
          Balance,
          PrefetchHooks Function()
        > {
  $$BalancesTableTableManager(_$WalletDatabase db, $BalancesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BalancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BalancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BalancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> walletId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<String> contract = const Value.absent(),
                Value<String> raw = const Value.absent(),
                Value<double?> fiat = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BalancesCompanion(
                walletId: walletId,
                coin: coin,
                contract: contract,
                raw: raw,
                fiat: fiat,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String walletId,
                required String coin,
                Value<String> contract = const Value.absent(),
                required String raw,
                Value<double?> fiat = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BalancesCompanion.insert(
                walletId: walletId,
                coin: coin,
                contract: contract,
                raw: raw,
                fiat: fiat,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BalancesTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $BalancesTable,
      Balance,
      $$BalancesTableFilterComposer,
      $$BalancesTableOrderingComposer,
      $$BalancesTableAnnotationComposer,
      $$BalancesTableCreateCompanionBuilder,
      $$BalancesTableUpdateCompanionBuilder,
      (Balance, BaseReferences<_$WalletDatabase, $BalancesTable, Balance>),
      Balance,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      required String id,
      required String walletId,
      Value<String?> reqId,
      required String coin,
      Value<String?> contract,
      required TxDirection direction,
      required String fromAddr,
      required String toAddr,
      required String amountRaw,
      Value<String?> feeRaw,
      Value<String?> hash,
      required TxStatus status,
      required SignMode signMode,
      Value<String?> memo,
      required int createdAt,
      Value<int?> broadcastAt,
      Value<String?> nonce,
      Value<String?> maxPriorityFeeRaw,
      Value<String?> maxFeeRaw,
      Value<String?> gasLimitRaw,
      Value<String?> replacesId,
      Value<String?> replacedById,
      Value<TxReplacementKind?> replacementKind,
      Value<int> rowid,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<String> id,
      Value<String> walletId,
      Value<String?> reqId,
      Value<String> coin,
      Value<String?> contract,
      Value<TxDirection> direction,
      Value<String> fromAddr,
      Value<String> toAddr,
      Value<String> amountRaw,
      Value<String?> feeRaw,
      Value<String?> hash,
      Value<TxStatus> status,
      Value<SignMode> signMode,
      Value<String?> memo,
      Value<int> createdAt,
      Value<int?> broadcastAt,
      Value<String?> nonce,
      Value<String?> maxPriorityFeeRaw,
      Value<String?> maxFeeRaw,
      Value<String?> gasLimitRaw,
      Value<String?> replacesId,
      Value<String?> replacedById,
      Value<TxReplacementKind?> replacementKind,
      Value<int> rowid,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$WalletDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
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

  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reqId => $composableBuilder(
    column: $table.reqId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TxDirection, TxDirection, int> get direction =>
      $composableBuilder(
        column: $table.direction,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get fromAddr => $composableBuilder(
    column: $table.fromAddr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toAddr => $composableBuilder(
    column: $table.toAddr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountRaw => $composableBuilder(
    column: $table.amountRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feeRaw => $composableBuilder(
    column: $table.feeRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TxStatus, TxStatus, int> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<SignMode, SignMode, int> get signMode =>
      $composableBuilder(
        column: $table.signMode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get broadcastAt => $composableBuilder(
    column: $table.broadcastAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get maxPriorityFeeRaw => $composableBuilder(
    column: $table.maxPriorityFeeRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get maxFeeRaw => $composableBuilder(
    column: $table.maxFeeRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gasLimitRaw => $composableBuilder(
    column: $table.gasLimitRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacesId => $composableBuilder(
    column: $table.replacesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacedById => $composableBuilder(
    column: $table.replacedById,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TxReplacementKind?, TxReplacementKind, int>
  get replacementKind => $composableBuilder(
    column: $table.replacementKind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$WalletDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
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

  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reqId => $composableBuilder(
    column: $table.reqId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromAddr => $composableBuilder(
    column: $table.fromAddr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toAddr => $composableBuilder(
    column: $table.toAddr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountRaw => $composableBuilder(
    column: $table.amountRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feeRaw => $composableBuilder(
    column: $table.feeRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get signMode => $composableBuilder(
    column: $table.signMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get broadcastAt => $composableBuilder(
    column: $table.broadcastAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get maxPriorityFeeRaw => $composableBuilder(
    column: $table.maxPriorityFeeRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get maxFeeRaw => $composableBuilder(
    column: $table.maxFeeRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gasLimitRaw => $composableBuilder(
    column: $table.gasLimitRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacesId => $composableBuilder(
    column: $table.replacesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacedById => $composableBuilder(
    column: $table.replacedById,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get replacementKind => $composableBuilder(
    column: $table.replacementKind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get reqId =>
      $composableBuilder(column: $table.reqId, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<String> get contract =>
      $composableBuilder(column: $table.contract, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TxDirection, int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get fromAddr =>
      $composableBuilder(column: $table.fromAddr, builder: (column) => column);

  GeneratedColumn<String> get toAddr =>
      $composableBuilder(column: $table.toAddr, builder: (column) => column);

  GeneratedColumn<String> get amountRaw =>
      $composableBuilder(column: $table.amountRaw, builder: (column) => column);

  GeneratedColumn<String> get feeRaw =>
      $composableBuilder(column: $table.feeRaw, builder: (column) => column);

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TxStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SignMode, int> get signMode =>
      $composableBuilder(column: $table.signMode, builder: (column) => column);

  GeneratedColumn<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get broadcastAt => $composableBuilder(
    column: $table.broadcastAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<String> get maxPriorityFeeRaw => $composableBuilder(
    column: $table.maxPriorityFeeRaw,
    builder: (column) => column,
  );

  GeneratedColumn<String> get maxFeeRaw =>
      $composableBuilder(column: $table.maxFeeRaw, builder: (column) => column);

  GeneratedColumn<String> get gasLimitRaw => $composableBuilder(
    column: $table.gasLimitRaw,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replacesId => $composableBuilder(
    column: $table.replacesId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replacedById => $composableBuilder(
    column: $table.replacedById,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TxReplacementKind?, int>
  get replacementKind => $composableBuilder(
    column: $table.replacementKind,
    builder: (column) => column,
  );
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $TransactionsTable,
          Transaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            Transaction,
            BaseReferences<_$WalletDatabase, $TransactionsTable, Transaction>,
          ),
          Transaction,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$WalletDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> walletId = const Value.absent(),
                Value<String?> reqId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<String?> contract = const Value.absent(),
                Value<TxDirection> direction = const Value.absent(),
                Value<String> fromAddr = const Value.absent(),
                Value<String> toAddr = const Value.absent(),
                Value<String> amountRaw = const Value.absent(),
                Value<String?> feeRaw = const Value.absent(),
                Value<String?> hash = const Value.absent(),
                Value<TxStatus> status = const Value.absent(),
                Value<SignMode> signMode = const Value.absent(),
                Value<String?> memo = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> broadcastAt = const Value.absent(),
                Value<String?> nonce = const Value.absent(),
                Value<String?> maxPriorityFeeRaw = const Value.absent(),
                Value<String?> maxFeeRaw = const Value.absent(),
                Value<String?> gasLimitRaw = const Value.absent(),
                Value<String?> replacesId = const Value.absent(),
                Value<String?> replacedById = const Value.absent(),
                Value<TxReplacementKind?> replacementKind =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                walletId: walletId,
                reqId: reqId,
                coin: coin,
                contract: contract,
                direction: direction,
                fromAddr: fromAddr,
                toAddr: toAddr,
                amountRaw: amountRaw,
                feeRaw: feeRaw,
                hash: hash,
                status: status,
                signMode: signMode,
                memo: memo,
                createdAt: createdAt,
                broadcastAt: broadcastAt,
                nonce: nonce,
                maxPriorityFeeRaw: maxPriorityFeeRaw,
                maxFeeRaw: maxFeeRaw,
                gasLimitRaw: gasLimitRaw,
                replacesId: replacesId,
                replacedById: replacedById,
                replacementKind: replacementKind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String walletId,
                Value<String?> reqId = const Value.absent(),
                required String coin,
                Value<String?> contract = const Value.absent(),
                required TxDirection direction,
                required String fromAddr,
                required String toAddr,
                required String amountRaw,
                Value<String?> feeRaw = const Value.absent(),
                Value<String?> hash = const Value.absent(),
                required TxStatus status,
                required SignMode signMode,
                Value<String?> memo = const Value.absent(),
                required int createdAt,
                Value<int?> broadcastAt = const Value.absent(),
                Value<String?> nonce = const Value.absent(),
                Value<String?> maxPriorityFeeRaw = const Value.absent(),
                Value<String?> maxFeeRaw = const Value.absent(),
                Value<String?> gasLimitRaw = const Value.absent(),
                Value<String?> replacesId = const Value.absent(),
                Value<String?> replacedById = const Value.absent(),
                Value<TxReplacementKind?> replacementKind =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                walletId: walletId,
                reqId: reqId,
                coin: coin,
                contract: contract,
                direction: direction,
                fromAddr: fromAddr,
                toAddr: toAddr,
                amountRaw: amountRaw,
                feeRaw: feeRaw,
                hash: hash,
                status: status,
                signMode: signMode,
                memo: memo,
                createdAt: createdAt,
                broadcastAt: broadcastAt,
                nonce: nonce,
                maxPriorityFeeRaw: maxPriorityFeeRaw,
                maxFeeRaw: maxFeeRaw,
                gasLimitRaw: gasLimitRaw,
                replacesId: replacesId,
                replacedById: replacedById,
                replacementKind: replacementKind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $TransactionsTable,
      Transaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        Transaction,
        BaseReferences<_$WalletDatabase, $TransactionsTable, Transaction>,
      ),
      Transaction,
      PrefetchHooks Function()
    >;
typedef $$AddressBookTableCreateCompanionBuilder =
    AddressBookCompanion Function({
      required String id,
      required String walletId,
      required String name,
      required String address,
      required String coin,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$AddressBookTableUpdateCompanionBuilder =
    AddressBookCompanion Function({
      Value<String> id,
      Value<String> walletId,
      Value<String> name,
      Value<String> address,
      Value<String> coin,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$AddressBookTableFilterComposer
    extends Composer<_$WalletDatabase, $AddressBookTable> {
  $$AddressBookTableFilterComposer({
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

  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddressBookTableOrderingComposer
    extends Composer<_$WalletDatabase, $AddressBookTable> {
  $$AddressBookTableOrderingComposer({
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

  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coin => $composableBuilder(
    column: $table.coin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddressBookTableAnnotationComposer
    extends Composer<_$WalletDatabase, $AddressBookTable> {
  $$AddressBookTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get coin =>
      $composableBuilder(column: $table.coin, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AddressBookTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $AddressBookTable,
          AddressBookData,
          $$AddressBookTableFilterComposer,
          $$AddressBookTableOrderingComposer,
          $$AddressBookTableAnnotationComposer,
          $$AddressBookTableCreateCompanionBuilder,
          $$AddressBookTableUpdateCompanionBuilder,
          (
            AddressBookData,
            BaseReferences<
              _$WalletDatabase,
              $AddressBookTable,
              AddressBookData
            >,
          ),
          AddressBookData,
          PrefetchHooks Function()
        > {
  $$AddressBookTableTableManager(_$WalletDatabase db, $AddressBookTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddressBookTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddressBookTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddressBookTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> walletId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AddressBookCompanion(
                id: id,
                walletId: walletId,
                name: name,
                address: address,
                coin: coin,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String walletId,
                required String name,
                required String address,
                required String coin,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AddressBookCompanion.insert(
                id: id,
                walletId: walletId,
                name: name,
                address: address,
                coin: coin,
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

typedef $$AddressBookTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $AddressBookTable,
      AddressBookData,
      $$AddressBookTableFilterComposer,
      $$AddressBookTableOrderingComposer,
      $$AddressBookTableAnnotationComposer,
      $$AddressBookTableCreateCompanionBuilder,
      $$AddressBookTableUpdateCompanionBuilder,
      (
        AddressBookData,
        BaseReferences<_$WalletDatabase, $AddressBookTable, AddressBookData>,
      ),
      AddressBookData,
      PrefetchHooks Function()
    >;
typedef $$SignRequestsTableCreateCompanionBuilder =
    SignRequestsCompanion Function({
      required String reqId,
      required String walletId,
      required String coin,
      required Uint8List rawTx,
      required int expiresAt,
      required String status,
      Value<int> rowid,
    });
typedef $$SignRequestsTableUpdateCompanionBuilder =
    SignRequestsCompanion Function({
      Value<String> reqId,
      Value<String> walletId,
      Value<String> coin,
      Value<Uint8List> rawTx,
      Value<int> expiresAt,
      Value<String> status,
      Value<int> rowid,
    });

class $$SignRequestsTableFilterComposer
    extends Composer<_$WalletDatabase, $SignRequestsTable> {
  $$SignRequestsTableFilterComposer({
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

  ColumnFilters<Uint8List> get rawTx => $composableBuilder(
    column: $table.rawTx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignRequestsTableOrderingComposer
    extends Composer<_$WalletDatabase, $SignRequestsTable> {
  $$SignRequestsTableOrderingComposer({
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

  ColumnOrderings<Uint8List> get rawTx => $composableBuilder(
    column: $table.rawTx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignRequestsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $SignRequestsTable> {
  $$SignRequestsTableAnnotationComposer({
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

  GeneratedColumn<Uint8List> get rawTx =>
      $composableBuilder(column: $table.rawTx, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$SignRequestsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $SignRequestsTable,
          SignRequest,
          $$SignRequestsTableFilterComposer,
          $$SignRequestsTableOrderingComposer,
          $$SignRequestsTableAnnotationComposer,
          $$SignRequestsTableCreateCompanionBuilder,
          $$SignRequestsTableUpdateCompanionBuilder,
          (
            SignRequest,
            BaseReferences<_$WalletDatabase, $SignRequestsTable, SignRequest>,
          ),
          SignRequest,
          PrefetchHooks Function()
        > {
  $$SignRequestsTableTableManager(_$WalletDatabase db, $SignRequestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignRequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignRequestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> reqId = const Value.absent(),
                Value<String> walletId = const Value.absent(),
                Value<String> coin = const Value.absent(),
                Value<Uint8List> rawTx = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignRequestsCompanion(
                reqId: reqId,
                walletId: walletId,
                coin: coin,
                rawTx: rawTx,
                expiresAt: expiresAt,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String reqId,
                required String walletId,
                required String coin,
                required Uint8List rawTx,
                required int expiresAt,
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => SignRequestsCompanion.insert(
                reqId: reqId,
                walletId: walletId,
                coin: coin,
                rawTx: rawTx,
                expiresAt: expiresAt,
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

typedef $$SignRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $SignRequestsTable,
      SignRequest,
      $$SignRequestsTableFilterComposer,
      $$SignRequestsTableOrderingComposer,
      $$SignRequestsTableAnnotationComposer,
      $$SignRequestsTableCreateCompanionBuilder,
      $$SignRequestsTableUpdateCompanionBuilder,
      (
        SignRequest,
        BaseReferences<_$WalletDatabase, $SignRequestsTable, SignRequest>,
      ),
      SignRequest,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$WalletDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$WalletDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$WalletDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$WalletDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$WalletDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$WalletSettingsTableCreateCompanionBuilder =
    WalletSettingsCompanion Function({
      required String walletId,
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$WalletSettingsTableUpdateCompanionBuilder =
    WalletSettingsCompanion Function({
      Value<String> walletId,
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$WalletSettingsTableFilterComposer
    extends Composer<_$WalletDatabase, $WalletSettingsTable> {
  $$WalletSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletSettingsTableOrderingComposer
    extends Composer<_$WalletDatabase, $WalletSettingsTable> {
  $$WalletSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletSettingsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $WalletSettingsTable> {
  $$WalletSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$WalletSettingsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $WalletSettingsTable,
          WalletSetting,
          $$WalletSettingsTableFilterComposer,
          $$WalletSettingsTableOrderingComposer,
          $$WalletSettingsTableAnnotationComposer,
          $$WalletSettingsTableCreateCompanionBuilder,
          $$WalletSettingsTableUpdateCompanionBuilder,
          (
            WalletSetting,
            BaseReferences<
              _$WalletDatabase,
              $WalletSettingsTable,
              WalletSetting
            >,
          ),
          WalletSetting,
          PrefetchHooks Function()
        > {
  $$WalletSettingsTableTableManager(
    _$WalletDatabase db,
    $WalletSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> walletId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WalletSettingsCompanion(
                walletId: walletId,
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String walletId,
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => WalletSettingsCompanion.insert(
                walletId: walletId,
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $WalletSettingsTable,
      WalletSetting,
      $$WalletSettingsTableFilterComposer,
      $$WalletSettingsTableOrderingComposer,
      $$WalletSettingsTableAnnotationComposer,
      $$WalletSettingsTableCreateCompanionBuilder,
      $$WalletSettingsTableUpdateCompanionBuilder,
      (
        WalletSetting,
        BaseReferences<_$WalletDatabase, $WalletSettingsTable, WalletSetting>,
      ),
      WalletSetting,
      PrefetchHooks Function()
    >;
typedef $$ContactsTableCreateCompanionBuilder =
    ContactsCompanion Function({
      required String id,
      required String name,
      required String address,
      required String chain,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ContactsTableUpdateCompanionBuilder =
    ContactsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> address,
      Value<String> chain,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$ContactsTableFilterComposer
    extends Composer<_$WalletDatabase, $ContactsTable> {
  $$ContactsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContactsTableOrderingComposer
    extends Composer<_$WalletDatabase, $ContactsTable> {
  $$ContactsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$WalletDatabase, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get chain =>
      $composableBuilder(column: $table.chain, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ContactsTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $ContactsTable,
          Contact,
          $$ContactsTableFilterComposer,
          $$ContactsTableOrderingComposer,
          $$ContactsTableAnnotationComposer,
          $$ContactsTableCreateCompanionBuilder,
          $$ContactsTableUpdateCompanionBuilder,
          (Contact, BaseReferences<_$WalletDatabase, $ContactsTable, Contact>),
          Contact,
          PrefetchHooks Function()
        > {
  $$ContactsTableTableManager(_$WalletDatabase db, $ContactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> chain = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion(
                id: id,
                name: name,
                address: address,
                chain: chain,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String address,
                required String chain,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ContactsCompanion.insert(
                id: id,
                name: name,
                address: address,
                chain: chain,
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

typedef $$ContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $ContactsTable,
      Contact,
      $$ContactsTableFilterComposer,
      $$ContactsTableOrderingComposer,
      $$ContactsTableAnnotationComposer,
      $$ContactsTableCreateCompanionBuilder,
      $$ContactsTableUpdateCompanionBuilder,
      (Contact, BaseReferences<_$WalletDatabase, $ContactsTable, Contact>),
      Contact,
      PrefetchHooks Function()
    >;
typedef $$CustomTokensTableCreateCompanionBuilder =
    CustomTokensCompanion Function({
      required String id,
      required String symbol,
      required String name,
      Value<String?> contract,
      required String network,
      Value<bool> enabled,
      Value<int> sortOrder,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$CustomTokensTableUpdateCompanionBuilder =
    CustomTokensCompanion Function({
      Value<String> id,
      Value<String> symbol,
      Value<String> name,
      Value<String?> contract,
      Value<String> network,
      Value<bool> enabled,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$CustomTokensTableFilterComposer
    extends Composer<_$WalletDatabase, $CustomTokensTable> {
  $$CustomTokensTableFilterComposer({
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

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomTokensTableOrderingComposer
    extends Composer<_$WalletDatabase, $CustomTokensTable> {
  $$CustomTokensTableOrderingComposer({
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

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomTokensTableAnnotationComposer
    extends Composer<_$WalletDatabase, $CustomTokensTable> {
  $$CustomTokensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get contract =>
      $composableBuilder(column: $table.contract, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CustomTokensTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $CustomTokensTable,
          CustomToken,
          $$CustomTokensTableFilterComposer,
          $$CustomTokensTableOrderingComposer,
          $$CustomTokensTableAnnotationComposer,
          $$CustomTokensTableCreateCompanionBuilder,
          $$CustomTokensTableUpdateCompanionBuilder,
          (
            CustomToken,
            BaseReferences<_$WalletDatabase, $CustomTokensTable, CustomToken>,
          ),
          CustomToken,
          PrefetchHooks Function()
        > {
  $$CustomTokensTableTableManager(_$WalletDatabase db, $CustomTokensTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomTokensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomTokensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomTokensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> contract = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomTokensCompanion(
                id: id,
                symbol: symbol,
                name: name,
                contract: contract,
                network: network,
                enabled: enabled,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String symbol,
                required String name,
                Value<String?> contract = const Value.absent(),
                required String network,
                Value<bool> enabled = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CustomTokensCompanion.insert(
                id: id,
                symbol: symbol,
                name: name,
                contract: contract,
                network: network,
                enabled: enabled,
                sortOrder: sortOrder,
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

typedef $$CustomTokensTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $CustomTokensTable,
      CustomToken,
      $$CustomTokensTableFilterComposer,
      $$CustomTokensTableOrderingComposer,
      $$CustomTokensTableAnnotationComposer,
      $$CustomTokensTableCreateCompanionBuilder,
      $$CustomTokensTableUpdateCompanionBuilder,
      (
        CustomToken,
        BaseReferences<_$WalletDatabase, $CustomTokensTable, CustomToken>,
      ),
      CustomToken,
      PrefetchHooks Function()
    >;

class $WalletDatabaseManager {
  final _$WalletDatabase _db;
  $WalletDatabaseManager(this._db);
  $$WalletsTableTableManager get wallets =>
      $$WalletsTableTableManager(_db, _db.wallets);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$TokensTableTableManager get tokens =>
      $$TokensTableTableManager(_db, _db.tokens);
  $$BalancesTableTableManager get balances =>
      $$BalancesTableTableManager(_db, _db.balances);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$AddressBookTableTableManager get addressBook =>
      $$AddressBookTableTableManager(_db, _db.addressBook);
  $$SignRequestsTableTableManager get signRequests =>
      $$SignRequestsTableTableManager(_db, _db.signRequests);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$WalletSettingsTableTableManager get walletSettings =>
      $$WalletSettingsTableTableManager(_db, _db.walletSettings);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$CustomTokensTableTableManager get customTokens =>
      $$CustomTokensTableTableManager(_db, _db.customTokens);
}
