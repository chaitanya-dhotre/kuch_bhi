// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTableTable extends UsersTable
    with TableInfo<$UsersTableTable, UsersTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aboutMeta = const VerificationMeta('about');
  @override
  late final GeneratedColumn<String> about = GeneratedColumn<String>(
    'about',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _friendCodeMeta = const VerificationMeta(
    'friendCode',
  );
  @override
  late final GeneratedColumn<String> friendCode = GeneratedColumn<String>(
    'friend_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOnlineMeta = const VerificationMeta(
    'isOnline',
  );
  @override
  late final GeneratedColumn<bool> isOnline = GeneratedColumn<bool>(
    'is_online',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_online" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    username,
    email,
    avatarUrl,
    about,
    friendCode,
    isOnline,
    lastSeen,
    publicKey,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<UsersTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('about')) {
      context.handle(
        _aboutMeta,
        about.isAcceptableOrUnknown(data['about']!, _aboutMeta),
      );
    }
    if (data.containsKey('friend_code')) {
      context.handle(
        _friendCodeMeta,
        friendCode.isAcceptableOrUnknown(data['friend_code']!, _friendCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_friendCodeMeta);
    }
    if (data.containsKey('is_online')) {
      context.handle(
        _isOnlineMeta,
        isOnline.isAcceptableOrUnknown(data['is_online']!, _isOnlineMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsersTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsersTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      about: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}about'],
      ),
      friendCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friend_code'],
      )!,
      isOnline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_online'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UsersTableTable createAlias(String alias) {
    return $UsersTableTable(attachedDatabase, alias);
  }
}

class UsersTableData extends DataClass implements Insertable<UsersTableData> {
  final String id;
  final String displayName;
  final String username;
  final String? email;
  final String? avatarUrl;
  final String? about;
  final String friendCode;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? publicKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  const UsersTableData({
    required this.id,
    required this.displayName,
    required this.username,
    this.email,
    this.avatarUrl,
    this.about,
    required this.friendCode,
    required this.isOnline,
    this.lastSeen,
    this.publicKey,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || about != null) {
      map['about'] = Variable<String>(about);
    }
    map['friend_code'] = Variable<String>(friendCode);
    map['is_online'] = Variable<bool>(isOnline);
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    if (!nullToAbsent || publicKey != null) {
      map['public_key'] = Variable<String>(publicKey);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UsersTableCompanion toCompanion(bool nullToAbsent) {
    return UsersTableCompanion(
      id: Value(id),
      displayName: Value(displayName),
      username: Value(username),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      about: about == null && nullToAbsent
          ? const Value.absent()
          : Value(about),
      friendCode: Value(friendCode),
      isOnline: Value(isOnline),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      publicKey: publicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKey),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory UsersTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsersTableData(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      username: serializer.fromJson<String>(json['username']),
      email: serializer.fromJson<String?>(json['email']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      about: serializer.fromJson<String?>(json['about']),
      friendCode: serializer.fromJson<String>(json['friendCode']),
      isOnline: serializer.fromJson<bool>(json['isOnline']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
      publicKey: serializer.fromJson<String?>(json['publicKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'username': serializer.toJson<String>(username),
      'email': serializer.toJson<String?>(email),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'about': serializer.toJson<String?>(about),
      'friendCode': serializer.toJson<String>(friendCode),
      'isOnline': serializer.toJson<bool>(isOnline),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
      'publicKey': serializer.toJson<String?>(publicKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UsersTableData copyWith({
    String? id,
    String? displayName,
    String? username,
    Value<String?> email = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> about = const Value.absent(),
    String? friendCode,
    bool? isOnline,
    Value<DateTime?> lastSeen = const Value.absent(),
    Value<String?> publicKey = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => UsersTableData(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    email: email.present ? email.value : this.email,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    about: about.present ? about.value : this.about,
    friendCode: friendCode ?? this.friendCode,
    isOnline: isOnline ?? this.isOnline,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
    publicKey: publicKey.present ? publicKey.value : this.publicKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  UsersTableData copyWithCompanion(UsersTableCompanion data) {
    return UsersTableData(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      username: data.username.present ? data.username.value : this.username,
      email: data.email.present ? data.email.value : this.email,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      about: data.about.present ? data.about.value : this.about,
      friendCode: data.friendCode.present
          ? data.friendCode.value
          : this.friendCode,
      isOnline: data.isOnline.present ? data.isOnline.value : this.isOnline,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsersTableData(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('email: $email, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('about: $about, ')
          ..write('friendCode: $friendCode, ')
          ..write('isOnline: $isOnline, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('publicKey: $publicKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    username,
    email,
    avatarUrl,
    about,
    friendCode,
    isOnline,
    lastSeen,
    publicKey,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsersTableData &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.username == this.username &&
          other.email == this.email &&
          other.avatarUrl == this.avatarUrl &&
          other.about == this.about &&
          other.friendCode == this.friendCode &&
          other.isOnline == this.isOnline &&
          other.lastSeen == this.lastSeen &&
          other.publicKey == this.publicKey &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UsersTableCompanion extends UpdateCompanion<UsersTableData> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> username;
  final Value<String?> email;
  final Value<String?> avatarUrl;
  final Value<String?> about;
  final Value<String> friendCode;
  final Value<bool> isOnline;
  final Value<DateTime?> lastSeen;
  final Value<String?> publicKey;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UsersTableCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.username = const Value.absent(),
    this.email = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.about = const Value.absent(),
    this.friendCode = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersTableCompanion.insert({
    required String id,
    required String displayName,
    required String username,
    this.email = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.about = const Value.absent(),
    required String friendCode,
    this.isOnline = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.publicKey = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       username = Value(username),
       friendCode = Value(friendCode),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<UsersTableData> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? username,
    Expression<String>? email,
    Expression<String>? avatarUrl,
    Expression<String>? about,
    Expression<String>? friendCode,
    Expression<bool>? isOnline,
    Expression<DateTime>? lastSeen,
    Expression<String>? publicKey,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (about != null) 'about': about,
      if (friendCode != null) 'friend_code': friendCode,
      if (isOnline != null) 'is_online': isOnline,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (publicKey != null) 'public_key': publicKey,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersTableCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? username,
    Value<String?>? email,
    Value<String?>? avatarUrl,
    Value<String?>? about,
    Value<String>? friendCode,
    Value<bool>? isOnline,
    Value<DateTime?>? lastSeen,
    Value<String?>? publicKey,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UsersTableCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
      friendCode: friendCode ?? this.friendCode,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (about.present) {
      map['about'] = Variable<String>(about.value);
    }
    if (friendCode.present) {
      map['friend_code'] = Variable<String>(friendCode.value);
    }
    if (isOnline.present) {
      map['is_online'] = Variable<bool>(isOnline.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersTableCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('email: $email, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('about: $about, ')
          ..write('friendCode: $friendCode, ')
          ..write('isOnline: $isOnline, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('publicKey: $publicKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTableTable extends ConversationsTable
    with TableInfo<$ConversationsTableTable, ConversationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconUrlMeta = const VerificationMeta(
    'iconUrl',
  );
  @override
  late final GeneratedColumn<String> iconUrl = GeneratedColumn<String>(
    'icon_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByIdMeta = const VerificationMeta(
    'createdById',
  );
  @override
  late final GeneratedColumn<String> createdById = GeneratedColumn<String>(
    'created_by_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessagePreviewMeta =
      const VerificationMeta('lastMessagePreview');
  @override
  late final GeneratedColumn<String> lastMessagePreview =
      GeneratedColumn<String>(
        'last_message_preview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt =
      GeneratedColumn<DateTime>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _disappearingDurationMeta =
      const VerificationMeta('disappearingDuration');
  @override
  late final GeneratedColumn<int> disappearingDuration = GeneratedColumn<int>(
    'disappearing_duration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _muteUntilMeta = const VerificationMeta(
    'muteUntil',
  );
  @override
  late final GeneratedColumn<DateTime> muteUntil = GeneratedColumn<DateTime>(
    'mute_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wallpaperPathMeta = const VerificationMeta(
    'wallpaperPath',
  );
  @override
  late final GeneratedColumn<String> wallpaperPath = GeneratedColumn<String>(
    'wallpaper_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    name,
    iconUrl,
    createdById,
    lastMessagePreview,
    lastMessageAt,
    disappearingDuration,
    isPinned,
    muteUntil,
    wallpaperPath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('icon_url')) {
      context.handle(
        _iconUrlMeta,
        iconUrl.isAcceptableOrUnknown(data['icon_url']!, _iconUrlMeta),
      );
    }
    if (data.containsKey('created_by_id')) {
      context.handle(
        _createdByIdMeta,
        createdById.isAcceptableOrUnknown(
          data['created_by_id']!,
          _createdByIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByIdMeta);
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('disappearing_duration')) {
      context.handle(
        _disappearingDurationMeta,
        disappearingDuration.isAcceptableOrUnknown(
          data['disappearing_duration']!,
          _disappearingDurationMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('mute_until')) {
      context.handle(
        _muteUntilMeta,
        muteUntil.isAcceptableOrUnknown(data['mute_until']!, _muteUntilMeta),
      );
    }
    if (data.containsKey('wallpaper_path')) {
      context.handle(
        _wallpaperPathMeta,
        wallpaperPath.isAcceptableOrUnknown(
          data['wallpaper_path']!,
          _wallpaperPathMeta,
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      iconUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_url'],
      ),
      createdById: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_id'],
      )!,
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      ),
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      disappearingDuration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disappearing_duration'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      muteUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}mute_until'],
      ),
      wallpaperPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallpaper_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTableTable createAlias(String alias) {
    return $ConversationsTableTable(attachedDatabase, alias);
  }
}

class ConversationsTableData extends DataClass
    implements Insertable<ConversationsTableData> {
  final String id;
  final String type;
  final String? name;
  final String? iconUrl;
  final String createdById;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int disappearingDuration;
  final bool isPinned;
  final DateTime? muteUntil;
  final String? wallpaperPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ConversationsTableData({
    required this.id,
    required this.type,
    this.name,
    this.iconUrl,
    required this.createdById,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.disappearingDuration,
    required this.isPinned,
    this.muteUntil,
    this.wallpaperPath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || iconUrl != null) {
      map['icon_url'] = Variable<String>(iconUrl);
    }
    map['created_by_id'] = Variable<String>(createdById);
    if (!nullToAbsent || lastMessagePreview != null) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['disappearing_duration'] = Variable<int>(disappearingDuration);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || muteUntil != null) {
      map['mute_until'] = Variable<DateTime>(muteUntil);
    }
    if (!nullToAbsent || wallpaperPath != null) {
      map['wallpaper_path'] = Variable<String>(wallpaperPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationsTableCompanion(
      id: Value(id),
      type: Value(type),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      iconUrl: iconUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(iconUrl),
      createdById: Value(createdById),
      lastMessagePreview: lastMessagePreview == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessagePreview),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      disappearingDuration: Value(disappearingDuration),
      isPinned: Value(isPinned),
      muteUntil: muteUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(muteUntil),
      wallpaperPath: wallpaperPath == null && nullToAbsent
          ? const Value.absent()
          : Value(wallpaperPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConversationsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationsTableData(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String?>(json['name']),
      iconUrl: serializer.fromJson<String?>(json['iconUrl']),
      createdById: serializer.fromJson<String>(json['createdById']),
      lastMessagePreview: serializer.fromJson<String?>(
        json['lastMessagePreview'],
      ),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      disappearingDuration: serializer.fromJson<int>(
        json['disappearingDuration'],
      ),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      muteUntil: serializer.fromJson<DateTime?>(json['muteUntil']),
      wallpaperPath: serializer.fromJson<String?>(json['wallpaperPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String?>(name),
      'iconUrl': serializer.toJson<String?>(iconUrl),
      'createdById': serializer.toJson<String>(createdById),
      'lastMessagePreview': serializer.toJson<String?>(lastMessagePreview),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'disappearingDuration': serializer.toJson<int>(disappearingDuration),
      'isPinned': serializer.toJson<bool>(isPinned),
      'muteUntil': serializer.toJson<DateTime?>(muteUntil),
      'wallpaperPath': serializer.toJson<String?>(wallpaperPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ConversationsTableData copyWith({
    String? id,
    String? type,
    Value<String?> name = const Value.absent(),
    Value<String?> iconUrl = const Value.absent(),
    String? createdById,
    Value<String?> lastMessagePreview = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    int? disappearingDuration,
    bool? isPinned,
    Value<DateTime?> muteUntil = const Value.absent(),
    Value<String?> wallpaperPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ConversationsTableData(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name.present ? name.value : this.name,
    iconUrl: iconUrl.present ? iconUrl.value : this.iconUrl,
    createdById: createdById ?? this.createdById,
    lastMessagePreview: lastMessagePreview.present
        ? lastMessagePreview.value
        : this.lastMessagePreview,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    disappearingDuration: disappearingDuration ?? this.disappearingDuration,
    isPinned: isPinned ?? this.isPinned,
    muteUntil: muteUntil.present ? muteUntil.value : this.muteUntil,
    wallpaperPath: wallpaperPath.present
        ? wallpaperPath.value
        : this.wallpaperPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ConversationsTableData copyWithCompanion(ConversationsTableCompanion data) {
    return ConversationsTableData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      iconUrl: data.iconUrl.present ? data.iconUrl.value : this.iconUrl,
      createdById: data.createdById.present
          ? data.createdById.value
          : this.createdById,
      lastMessagePreview: data.lastMessagePreview.present
          ? data.lastMessagePreview.value
          : this.lastMessagePreview,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      disappearingDuration: data.disappearingDuration.present
          ? data.disappearingDuration.value
          : this.disappearingDuration,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      muteUntil: data.muteUntil.present ? data.muteUntil.value : this.muteUntil,
      wallpaperPath: data.wallpaperPath.present
          ? data.wallpaperPath.value
          : this.wallpaperPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('iconUrl: $iconUrl, ')
          ..write('createdById: $createdById, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('disappearingDuration: $disappearingDuration, ')
          ..write('isPinned: $isPinned, ')
          ..write('muteUntil: $muteUntil, ')
          ..write('wallpaperPath: $wallpaperPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    name,
    iconUrl,
    createdById,
    lastMessagePreview,
    lastMessageAt,
    disappearingDuration,
    isPinned,
    muteUntil,
    wallpaperPath,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationsTableData &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.iconUrl == this.iconUrl &&
          other.createdById == this.createdById &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.lastMessageAt == this.lastMessageAt &&
          other.disappearingDuration == this.disappearingDuration &&
          other.isPinned == this.isPinned &&
          other.muteUntil == this.muteUntil &&
          other.wallpaperPath == this.wallpaperPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsTableCompanion
    extends UpdateCompanion<ConversationsTableData> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> name;
  final Value<String?> iconUrl;
  final Value<String> createdById;
  final Value<String?> lastMessagePreview;
  final Value<DateTime?> lastMessageAt;
  final Value<int> disappearingDuration;
  final Value<bool> isPinned;
  final Value<DateTime?> muteUntil;
  final Value<String?> wallpaperPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConversationsTableCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.iconUrl = const Value.absent(),
    this.createdById = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.disappearingDuration = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.muteUntil = const Value.absent(),
    this.wallpaperPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsTableCompanion.insert({
    required String id,
    required String type,
    this.name = const Value.absent(),
    this.iconUrl = const Value.absent(),
    required String createdById,
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.disappearingDuration = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.muteUntil = const Value.absent(),
    this.wallpaperPath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       createdById = Value(createdById),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ConversationsTableData> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? iconUrl,
    Expression<String>? createdById,
    Expression<String>? lastMessagePreview,
    Expression<DateTime>? lastMessageAt,
    Expression<int>? disappearingDuration,
    Expression<bool>? isPinned,
    Expression<DateTime>? muteUntil,
    Expression<String>? wallpaperPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (iconUrl != null) 'icon_url': iconUrl,
      if (createdById != null) 'created_by_id': createdById,
      if (lastMessagePreview != null)
        'last_message_preview': lastMessagePreview,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (disappearingDuration != null)
        'disappearing_duration': disappearingDuration,
      if (isPinned != null) 'is_pinned': isPinned,
      if (muteUntil != null) 'mute_until': muteUntil,
      if (wallpaperPath != null) 'wallpaper_path': wallpaperPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String?>? name,
    Value<String?>? iconUrl,
    Value<String>? createdById,
    Value<String?>? lastMessagePreview,
    Value<DateTime?>? lastMessageAt,
    Value<int>? disappearingDuration,
    Value<bool>? isPinned,
    Value<DateTime?>? muteUntil,
    Value<String?>? wallpaperPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationsTableCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      createdById: createdById ?? this.createdById,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      disappearingDuration: disappearingDuration ?? this.disappearingDuration,
      isPinned: isPinned ?? this.isPinned,
      muteUntil: muteUntil ?? this.muteUntil,
      wallpaperPath: wallpaperPath ?? this.wallpaperPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (iconUrl.present) {
      map['icon_url'] = Variable<String>(iconUrl.value);
    }
    if (createdById.present) {
      map['created_by_id'] = Variable<String>(createdById.value);
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (disappearingDuration.present) {
      map['disappearing_duration'] = Variable<int>(disappearingDuration.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (muteUntil.present) {
      map['mute_until'] = Variable<DateTime>(muteUntil.value);
    }
    if (wallpaperPath.present) {
      map['wallpaper_path'] = Variable<String>(wallpaperPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('iconUrl: $iconUrl, ')
          ..write('createdById: $createdById, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('disappearingDuration: $disappearingDuration, ')
          ..write('isPinned: $isPinned, ')
          ..write('muteUntil: $muteUntil, ')
          ..write('wallpaperPath: $wallpaperPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationMembersTableTable extends ConversationMembersTable
    with
        TableInfo<
          $ConversationMembersTableTable,
          ConversationMembersTableData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationMembersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('member'),
  );
  static const VerificationMeta _joinedAtMeta = const VerificationMeta(
    'joinedAt',
  );
  @override
  late final GeneratedColumn<DateTime> joinedAt = GeneratedColumn<DateTime>(
    'joined_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadMessageIdMeta = const VerificationMeta(
    'lastReadMessageId',
  );
  @override
  late final GeneratedColumn<String> lastReadMessageId =
      GeneratedColumn<String>(
        'last_read_message_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    userId,
    role,
    joinedAt,
    lastReadMessageId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_members_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationMembersTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('joined_at')) {
      context.handle(
        _joinedAtMeta,
        joinedAt.isAcceptableOrUnknown(data['joined_at']!, _joinedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMeta);
    }
    if (data.containsKey('last_read_message_id')) {
      context.handle(
        _lastReadMessageIdMeta,
        lastReadMessageId.isAcceptableOrUnknown(
          data['last_read_message_id']!,
          _lastReadMessageIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationMembersTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationMembersTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      joinedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}joined_at'],
      )!,
      lastReadMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_message_id'],
      ),
    );
  }

  @override
  $ConversationMembersTableTable createAlias(String alias) {
    return $ConversationMembersTableTable(attachedDatabase, alias);
  }
}

class ConversationMembersTableData extends DataClass
    implements Insertable<ConversationMembersTableData> {
  final String id;
  final String conversationId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final String? lastReadMessageId;
  const ConversationMembersTableData({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.lastReadMessageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['user_id'] = Variable<String>(userId);
    map['role'] = Variable<String>(role);
    map['joined_at'] = Variable<DateTime>(joinedAt);
    if (!nullToAbsent || lastReadMessageId != null) {
      map['last_read_message_id'] = Variable<String>(lastReadMessageId);
    }
    return map;
  }

  ConversationMembersTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationMembersTableCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      userId: Value(userId),
      role: Value(role),
      joinedAt: Value(joinedAt),
      lastReadMessageId: lastReadMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadMessageId),
    );
  }

  factory ConversationMembersTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationMembersTableData(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      userId: serializer.fromJson<String>(json['userId']),
      role: serializer.fromJson<String>(json['role']),
      joinedAt: serializer.fromJson<DateTime>(json['joinedAt']),
      lastReadMessageId: serializer.fromJson<String?>(
        json['lastReadMessageId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'userId': serializer.toJson<String>(userId),
      'role': serializer.toJson<String>(role),
      'joinedAt': serializer.toJson<DateTime>(joinedAt),
      'lastReadMessageId': serializer.toJson<String?>(lastReadMessageId),
    };
  }

  ConversationMembersTableData copyWith({
    String? id,
    String? conversationId,
    String? userId,
    String? role,
    DateTime? joinedAt,
    Value<String?> lastReadMessageId = const Value.absent(),
  }) => ConversationMembersTableData(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    userId: userId ?? this.userId,
    role: role ?? this.role,
    joinedAt: joinedAt ?? this.joinedAt,
    lastReadMessageId: lastReadMessageId.present
        ? lastReadMessageId.value
        : this.lastReadMessageId,
  );
  ConversationMembersTableData copyWithCompanion(
    ConversationMembersTableCompanion data,
  ) {
    return ConversationMembersTableData(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      userId: data.userId.present ? data.userId.value : this.userId,
      role: data.role.present ? data.role.value : this.role,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
      lastReadMessageId: data.lastReadMessageId.present
          ? data.lastReadMessageId.value
          : this.lastReadMessageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationMembersTableData(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('lastReadMessageId: $lastReadMessageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    userId,
    role,
    joinedAt,
    lastReadMessageId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationMembersTableData &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.userId == this.userId &&
          other.role == this.role &&
          other.joinedAt == this.joinedAt &&
          other.lastReadMessageId == this.lastReadMessageId);
}

class ConversationMembersTableCompanion
    extends UpdateCompanion<ConversationMembersTableData> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> userId;
  final Value<String> role;
  final Value<DateTime> joinedAt;
  final Value<String?> lastReadMessageId;
  final Value<int> rowid;
  const ConversationMembersTableCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.userId = const Value.absent(),
    this.role = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.lastReadMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationMembersTableCompanion.insert({
    required String id,
    required String conversationId,
    required String userId,
    this.role = const Value.absent(),
    required DateTime joinedAt,
    this.lastReadMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       userId = Value(userId),
       joinedAt = Value(joinedAt);
  static Insertable<ConversationMembersTableData> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? userId,
    Expression<String>? role,
    Expression<DateTime>? joinedAt,
    Expression<String>? lastReadMessageId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (lastReadMessageId != null) 'last_read_message_id': lastReadMessageId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationMembersTableCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? userId,
    Value<String>? role,
    Value<DateTime>? joinedAt,
    Value<String?>? lastReadMessageId,
    Value<int>? rowid,
  }) {
    return ConversationMembersTableCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<DateTime>(joinedAt.value);
    }
    if (lastReadMessageId.present) {
      map['last_read_message_id'] = Variable<String>(lastReadMessageId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationMembersTableCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('lastReadMessageId: $lastReadMessageId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTableTable extends MessagesTable
    with TableInfo<$MessagesTableTable, MessagesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
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
  static const VerificationMeta _encryptedBodyMeta = const VerificationMeta(
    'encryptedBody',
  );
  @override
  late final GeneratedColumn<String> encryptedBody = GeneratedColumn<String>(
    'encrypted_body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ivMeta = const VerificationMeta('iv');
  @override
  late final GeneratedColumn<String> iv = GeneratedColumn<String>(
    'iv',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decryptedBodyMeta = const VerificationMeta(
    'decryptedBody',
  );
  @override
  late final GeneratedColumn<String> decryptedBody = GeneratedColumn<String>(
    'decrypted_body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyPreviewMeta = const VerificationMeta(
    'replyPreview',
  );
  @override
  late final GeneratedColumn<String> replyPreview = GeneratedColumn<String>(
    'reply_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedForEveryoneMeta =
      const VerificationMeta('isDeletedForEveryone');
  @override
  late final GeneratedColumn<bool> isDeletedForEveryone = GeneratedColumn<bool>(
    'is_deleted_for_everyone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted_for_everyone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDeletedForMeMeta = const VerificationMeta(
    'isDeletedForMe',
  );
  @override
  late final GeneratedColumn<bool> isDeletedForMe = GeneratedColumn<bool>(
    'is_deleted_for_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted_for_me" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isStarredMeta = const VerificationMeta(
    'isStarred',
  );
  @override
  late final GeneratedColumn<bool> isStarred = GeneratedColumn<bool>(
    'is_starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    serverId,
    conversationId,
    senderId,
    type,
    encryptedBody,
    iv,
    decryptedBody,
    replyToId,
    replyPreview,
    isDeletedForEveryone,
    isDeletedForMe,
    isPinned,
    isStarred,
    expiresAt,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessagesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('encrypted_body')) {
      context.handle(
        _encryptedBodyMeta,
        encryptedBody.isAcceptableOrUnknown(
          data['encrypted_body']!,
          _encryptedBodyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedBodyMeta);
    }
    if (data.containsKey('iv')) {
      context.handle(_ivMeta, iv.isAcceptableOrUnknown(data['iv']!, _ivMeta));
    } else if (isInserting) {
      context.missing(_ivMeta);
    }
    if (data.containsKey('decrypted_body')) {
      context.handle(
        _decryptedBodyMeta,
        decryptedBody.isAcceptableOrUnknown(
          data['decrypted_body']!,
          _decryptedBodyMeta,
        ),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('reply_preview')) {
      context.handle(
        _replyPreviewMeta,
        replyPreview.isAcceptableOrUnknown(
          data['reply_preview']!,
          _replyPreviewMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted_for_everyone')) {
      context.handle(
        _isDeletedForEveryoneMeta,
        isDeletedForEveryone.isAcceptableOrUnknown(
          data['is_deleted_for_everyone']!,
          _isDeletedForEveryoneMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted_for_me')) {
      context.handle(
        _isDeletedForMeMeta,
        isDeletedForMe.isAcceptableOrUnknown(
          data['is_deleted_for_me']!,
          _isDeletedForMeMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('is_starred')) {
      context.handle(
        _isStarredMeta,
        isStarred.isAcceptableOrUnknown(data['is_starred']!, _isStarredMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
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
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  MessagesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesTableData(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      encryptedBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_body'],
      )!,
      iv: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}iv'],
      )!,
      decryptedBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decrypted_body'],
      ),
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      replyPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_preview'],
      ),
      isDeletedForEveryone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted_for_everyone'],
      )!,
      isDeletedForMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted_for_me'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      isStarred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_starred'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MessagesTableTable createAlias(String alias) {
    return $MessagesTableTable(attachedDatabase, alias);
  }
}

class MessagesTableData extends DataClass
    implements Insertable<MessagesTableData> {
  /// Local UUID — always set immediately on message creation.
  final String localId;

  /// PocketBase record ID — null until server confirms receipt.
  final String? serverId;
  final String conversationId;
  final String senderId;

  /// 'text' | 'image' | 'video' | 'voice' | 'poll' | 'system'
  final String type;

  /// AES-256-GCM ciphertext, base64 encoded.
  final String encryptedBody;

  /// AES IV, base64 encoded.
  final String iv;

  /// Decrypted plaintext — cached after first decryption to avoid
  /// re-decrypting on every rebuild. Never sent to server.
  final String? decryptedBody;
  final String? replyToId;
  final String? replyPreview;
  final bool isDeletedForEveryone;
  final bool isDeletedForMe;
  final bool isPinned;
  final bool isStarred;
  final DateTime? expiresAt;

  /// 'pending' | 'sent' | 'delivered' | 'read' | 'failed'
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const MessagesTableData({
    required this.localId,
    this.serverId,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.encryptedBody,
    required this.iv,
    this.decryptedBody,
    this.replyToId,
    this.replyPreview,
    required this.isDeletedForEveryone,
    required this.isDeletedForMe,
    required this.isPinned,
    required this.isStarred,
    this.expiresAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    map['type'] = Variable<String>(type);
    map['encrypted_body'] = Variable<String>(encryptedBody);
    map['iv'] = Variable<String>(iv);
    if (!nullToAbsent || decryptedBody != null) {
      map['decrypted_body'] = Variable<String>(decryptedBody);
    }
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    if (!nullToAbsent || replyPreview != null) {
      map['reply_preview'] = Variable<String>(replyPreview);
    }
    map['is_deleted_for_everyone'] = Variable<bool>(isDeletedForEveryone);
    map['is_deleted_for_me'] = Variable<bool>(isDeletedForMe);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_starred'] = Variable<bool>(isStarred);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MessagesTableCompanion toCompanion(bool nullToAbsent) {
    return MessagesTableCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      type: Value(type),
      encryptedBody: Value(encryptedBody),
      iv: Value(iv),
      decryptedBody: decryptedBody == null && nullToAbsent
          ? const Value.absent()
          : Value(decryptedBody),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      replyPreview: replyPreview == null && nullToAbsent
          ? const Value.absent()
          : Value(replyPreview),
      isDeletedForEveryone: Value(isDeletedForEveryone),
      isDeletedForMe: Value(isDeletedForMe),
      isPinned: Value(isPinned),
      isStarred: Value(isStarred),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MessagesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesTableData(
      localId: serializer.fromJson<String>(json['localId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      type: serializer.fromJson<String>(json['type']),
      encryptedBody: serializer.fromJson<String>(json['encryptedBody']),
      iv: serializer.fromJson<String>(json['iv']),
      decryptedBody: serializer.fromJson<String?>(json['decryptedBody']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      replyPreview: serializer.fromJson<String?>(json['replyPreview']),
      isDeletedForEveryone: serializer.fromJson<bool>(
        json['isDeletedForEveryone'],
      ),
      isDeletedForMe: serializer.fromJson<bool>(json['isDeletedForMe']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isStarred: serializer.fromJson<bool>(json['isStarred']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'serverId': serializer.toJson<String?>(serverId),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'type': serializer.toJson<String>(type),
      'encryptedBody': serializer.toJson<String>(encryptedBody),
      'iv': serializer.toJson<String>(iv),
      'decryptedBody': serializer.toJson<String?>(decryptedBody),
      'replyToId': serializer.toJson<String?>(replyToId),
      'replyPreview': serializer.toJson<String?>(replyPreview),
      'isDeletedForEveryone': serializer.toJson<bool>(isDeletedForEveryone),
      'isDeletedForMe': serializer.toJson<bool>(isDeletedForMe),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isStarred': serializer.toJson<bool>(isStarred),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MessagesTableData copyWith({
    String? localId,
    Value<String?> serverId = const Value.absent(),
    String? conversationId,
    String? senderId,
    String? type,
    String? encryptedBody,
    String? iv,
    Value<String?> decryptedBody = const Value.absent(),
    Value<String?> replyToId = const Value.absent(),
    Value<String?> replyPreview = const Value.absent(),
    bool? isDeletedForEveryone,
    bool? isDeletedForMe,
    bool? isPinned,
    bool? isStarred,
    Value<DateTime?> expiresAt = const Value.absent(),
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MessagesTableData(
    localId: localId ?? this.localId,
    serverId: serverId.present ? serverId.value : this.serverId,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    type: type ?? this.type,
    encryptedBody: encryptedBody ?? this.encryptedBody,
    iv: iv ?? this.iv,
    decryptedBody: decryptedBody.present
        ? decryptedBody.value
        : this.decryptedBody,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    replyPreview: replyPreview.present ? replyPreview.value : this.replyPreview,
    isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
    isDeletedForMe: isDeletedForMe ?? this.isDeletedForMe,
    isPinned: isPinned ?? this.isPinned,
    isStarred: isStarred ?? this.isStarred,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MessagesTableData copyWithCompanion(MessagesTableCompanion data) {
    return MessagesTableData(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      type: data.type.present ? data.type.value : this.type,
      encryptedBody: data.encryptedBody.present
          ? data.encryptedBody.value
          : this.encryptedBody,
      iv: data.iv.present ? data.iv.value : this.iv,
      decryptedBody: data.decryptedBody.present
          ? data.decryptedBody.value
          : this.decryptedBody,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      replyPreview: data.replyPreview.present
          ? data.replyPreview.value
          : this.replyPreview,
      isDeletedForEveryone: data.isDeletedForEveryone.present
          ? data.isDeletedForEveryone.value
          : this.isDeletedForEveryone,
      isDeletedForMe: data.isDeletedForMe.present
          ? data.isDeletedForMe.value
          : this.isDeletedForMe,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isStarred: data.isStarred.present ? data.isStarred.value : this.isStarred,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableData(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('type: $type, ')
          ..write('encryptedBody: $encryptedBody, ')
          ..write('iv: $iv, ')
          ..write('decryptedBody: $decryptedBody, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyPreview: $replyPreview, ')
          ..write('isDeletedForEveryone: $isDeletedForEveryone, ')
          ..write('isDeletedForMe: $isDeletedForMe, ')
          ..write('isPinned: $isPinned, ')
          ..write('isStarred: $isStarred, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    serverId,
    conversationId,
    senderId,
    type,
    encryptedBody,
    iv,
    decryptedBody,
    replyToId,
    replyPreview,
    isDeletedForEveryone,
    isDeletedForMe,
    isPinned,
    isStarred,
    expiresAt,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesTableData &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.type == this.type &&
          other.encryptedBody == this.encryptedBody &&
          other.iv == this.iv &&
          other.decryptedBody == this.decryptedBody &&
          other.replyToId == this.replyToId &&
          other.replyPreview == this.replyPreview &&
          other.isDeletedForEveryone == this.isDeletedForEveryone &&
          other.isDeletedForMe == this.isDeletedForMe &&
          other.isPinned == this.isPinned &&
          other.isStarred == this.isStarred &&
          other.expiresAt == this.expiresAt &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MessagesTableCompanion extends UpdateCompanion<MessagesTableData> {
  final Value<String> localId;
  final Value<String?> serverId;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<String> type;
  final Value<String> encryptedBody;
  final Value<String> iv;
  final Value<String?> decryptedBody;
  final Value<String?> replyToId;
  final Value<String?> replyPreview;
  final Value<bool> isDeletedForEveryone;
  final Value<bool> isDeletedForMe;
  final Value<bool> isPinned;
  final Value<bool> isStarred;
  final Value<DateTime?> expiresAt;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MessagesTableCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.type = const Value.absent(),
    this.encryptedBody = const Value.absent(),
    this.iv = const Value.absent(),
    this.decryptedBody = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyPreview = const Value.absent(),
    this.isDeletedForEveryone = const Value.absent(),
    this.isDeletedForMe = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesTableCompanion.insert({
    required String localId,
    this.serverId = const Value.absent(),
    required String conversationId,
    required String senderId,
    required String type,
    required String encryptedBody,
    required String iv,
    this.decryptedBody = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyPreview = const Value.absent(),
    this.isDeletedForEveryone = const Value.absent(),
    this.isDeletedForMe = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       conversationId = Value(conversationId),
       senderId = Value(senderId),
       type = Value(type),
       encryptedBody = Value(encryptedBody),
       iv = Value(iv),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<MessagesTableData> custom({
    Expression<String>? localId,
    Expression<String>? serverId,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<String>? type,
    Expression<String>? encryptedBody,
    Expression<String>? iv,
    Expression<String>? decryptedBody,
    Expression<String>? replyToId,
    Expression<String>? replyPreview,
    Expression<bool>? isDeletedForEveryone,
    Expression<bool>? isDeletedForMe,
    Expression<bool>? isPinned,
    Expression<bool>? isStarred,
    Expression<DateTime>? expiresAt,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (type != null) 'type': type,
      if (encryptedBody != null) 'encrypted_body': encryptedBody,
      if (iv != null) 'iv': iv,
      if (decryptedBody != null) 'decrypted_body': decryptedBody,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyPreview != null) 'reply_preview': replyPreview,
      if (isDeletedForEveryone != null)
        'is_deleted_for_everyone': isDeletedForEveryone,
      if (isDeletedForMe != null) 'is_deleted_for_me': isDeletedForMe,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isStarred != null) 'is_starred': isStarred,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesTableCompanion copyWith({
    Value<String>? localId,
    Value<String?>? serverId,
    Value<String>? conversationId,
    Value<String>? senderId,
    Value<String>? type,
    Value<String>? encryptedBody,
    Value<String>? iv,
    Value<String?>? decryptedBody,
    Value<String?>? replyToId,
    Value<String?>? replyPreview,
    Value<bool>? isDeletedForEveryone,
    Value<bool>? isDeletedForMe,
    Value<bool>? isPinned,
    Value<bool>? isStarred,
    Value<DateTime?>? expiresAt,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MessagesTableCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      encryptedBody: encryptedBody ?? this.encryptedBody,
      iv: iv ?? this.iv,
      decryptedBody: decryptedBody ?? this.decryptedBody,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      isDeletedForMe: isDeletedForMe ?? this.isDeletedForMe,
      isPinned: isPinned ?? this.isPinned,
      isStarred: isStarred ?? this.isStarred,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (encryptedBody.present) {
      map['encrypted_body'] = Variable<String>(encryptedBody.value);
    }
    if (iv.present) {
      map['iv'] = Variable<String>(iv.value);
    }
    if (decryptedBody.present) {
      map['decrypted_body'] = Variable<String>(decryptedBody.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (replyPreview.present) {
      map['reply_preview'] = Variable<String>(replyPreview.value);
    }
    if (isDeletedForEveryone.present) {
      map['is_deleted_for_everyone'] = Variable<bool>(
        isDeletedForEveryone.value,
      );
    }
    if (isDeletedForMe.present) {
      map['is_deleted_for_me'] = Variable<bool>(isDeletedForMe.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isStarred.present) {
      map['is_starred'] = Variable<bool>(isStarred.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('type: $type, ')
          ..write('encryptedBody: $encryptedBody, ')
          ..write('iv: $iv, ')
          ..write('decryptedBody: $decryptedBody, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyPreview: $replyPreview, ')
          ..write('isDeletedForEveryone: $isDeletedForEveryone, ')
          ..write('isDeletedForMe: $isDeletedForMe, ')
          ..write('isPinned: $isPinned, ')
          ..write('isStarred: $isStarred, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageReceiptsTableTable extends MessageReceiptsTable
    with TableInfo<$MessageReceiptsTableTable, MessageReceiptsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReceiptsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageLocalIdMeta = const VerificationMeta(
    'messageLocalId',
  );
  @override
  late final GeneratedColumn<String> messageLocalId = GeneratedColumn<String>(
    'message_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipientIdMeta = const VerificationMeta(
    'recipientId',
  );
  @override
  late final GeneratedColumn<String> recipientId = GeneratedColumn<String>(
    'recipient_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageLocalId,
    conversationId,
    recipientId,
    deliveredAt,
    readAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_receipts_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageReceiptsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_local_id')) {
      context.handle(
        _messageLocalIdMeta,
        messageLocalId.isAcceptableOrUnknown(
          data['message_local_id']!,
          _messageLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageLocalIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('recipient_id')) {
      context.handle(
        _recipientIdMeta,
        recipientId.isAcceptableOrUnknown(
          data['recipient_id']!,
          _recipientIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientIdMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageReceiptsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageReceiptsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_local_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      recipientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_id'],
      )!,
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
    );
  }

  @override
  $MessageReceiptsTableTable createAlias(String alias) {
    return $MessageReceiptsTableTable(attachedDatabase, alias);
  }
}

class MessageReceiptsTableData extends DataClass
    implements Insertable<MessageReceiptsTableData> {
  final String id;
  final String messageLocalId;
  final String conversationId;
  final String recipientId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  const MessageReceiptsTableData({
    required this.id,
    required this.messageLocalId,
    required this.conversationId,
    required this.recipientId,
    this.deliveredAt,
    this.readAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_local_id'] = Variable<String>(messageLocalId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['recipient_id'] = Variable<String>(recipientId);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    return map;
  }

  MessageReceiptsTableCompanion toCompanion(bool nullToAbsent) {
    return MessageReceiptsTableCompanion(
      id: Value(id),
      messageLocalId: Value(messageLocalId),
      conversationId: Value(conversationId),
      recipientId: Value(recipientId),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
    );
  }

  factory MessageReceiptsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageReceiptsTableData(
      id: serializer.fromJson<String>(json['id']),
      messageLocalId: serializer.fromJson<String>(json['messageLocalId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      recipientId: serializer.fromJson<String>(json['recipientId']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageLocalId': serializer.toJson<String>(messageLocalId),
      'conversationId': serializer.toJson<String>(conversationId),
      'recipientId': serializer.toJson<String>(recipientId),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
    };
  }

  MessageReceiptsTableData copyWith({
    String? id,
    String? messageLocalId,
    String? conversationId,
    String? recipientId,
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
  }) => MessageReceiptsTableData(
    id: id ?? this.id,
    messageLocalId: messageLocalId ?? this.messageLocalId,
    conversationId: conversationId ?? this.conversationId,
    recipientId: recipientId ?? this.recipientId,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
  );
  MessageReceiptsTableData copyWithCompanion(
    MessageReceiptsTableCompanion data,
  ) {
    return MessageReceiptsTableData(
      id: data.id.present ? data.id.value : this.id,
      messageLocalId: data.messageLocalId.present
          ? data.messageLocalId.value
          : this.messageLocalId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      recipientId: data.recipientId.present
          ? data.recipientId.value
          : this.recipientId,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageReceiptsTableData(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('recipientId: $recipientId, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageLocalId,
    conversationId,
    recipientId,
    deliveredAt,
    readAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageReceiptsTableData &&
          other.id == this.id &&
          other.messageLocalId == this.messageLocalId &&
          other.conversationId == this.conversationId &&
          other.recipientId == this.recipientId &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt);
}

class MessageReceiptsTableCompanion
    extends UpdateCompanion<MessageReceiptsTableData> {
  final Value<String> id;
  final Value<String> messageLocalId;
  final Value<String> conversationId;
  final Value<String> recipientId;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  final Value<int> rowid;
  const MessageReceiptsTableCompanion({
    this.id = const Value.absent(),
    this.messageLocalId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.recipientId = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageReceiptsTableCompanion.insert({
    required String id,
    required String messageLocalId,
    required String conversationId,
    required String recipientId,
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageLocalId = Value(messageLocalId),
       conversationId = Value(conversationId),
       recipientId = Value(recipientId);
  static Insertable<MessageReceiptsTableData> custom({
    Expression<String>? id,
    Expression<String>? messageLocalId,
    Expression<String>? conversationId,
    Expression<String>? recipientId,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? readAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageLocalId != null) 'message_local_id': messageLocalId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (recipientId != null) 'recipient_id': recipientId,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageReceiptsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? messageLocalId,
    Value<String>? conversationId,
    Value<String>? recipientId,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
    Value<int>? rowid,
  }) {
    return MessageReceiptsTableCompanion(
      id: id ?? this.id,
      messageLocalId: messageLocalId ?? this.messageLocalId,
      conversationId: conversationId ?? this.conversationId,
      recipientId: recipientId ?? this.recipientId,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageLocalId.present) {
      map['message_local_id'] = Variable<String>(messageLocalId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (recipientId.present) {
      map['recipient_id'] = Variable<String>(recipientId.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReceiptsTableCompanion(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('recipientId: $recipientId, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageMediaTableTable extends MessageMediaTable
    with TableInfo<$MessageMediaTableTable, MessageMediaTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageMediaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageLocalIdMeta = const VerificationMeta(
    'messageLocalId',
  );
  @override
  late final GeneratedColumn<String> messageLocalId = GeneratedColumn<String>(
    'message_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileUrlMeta = const VerificationMeta(
    'fileUrl',
  );
  @override
  late final GeneratedColumn<String> fileUrl = GeneratedColumn<String>(
    'file_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailUrlMeta = const VerificationMeta(
    'thumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
    'thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailLocalPathMeta =
      const VerificationMeta('thumbnailLocalPath');
  @override
  late final GeneratedColumn<String> thumbnailLocalPath =
      GeneratedColumn<String>(
        'thumbnail_local_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('normal'),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageLocalId,
    conversationId,
    fileUrl,
    localPath,
    mediaType,
    fileName,
    fileSize,
    durationSeconds,
    thumbnailUrl,
    thumbnailLocalPath,
    quality,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_media_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageMediaTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_local_id')) {
      context.handle(
        _messageLocalIdMeta,
        messageLocalId.isAcceptableOrUnknown(
          data['message_local_id']!,
          _messageLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageLocalIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('file_url')) {
      context.handle(
        _fileUrlMeta,
        fileUrl.isAcceptableOrUnknown(data['file_url']!, _fileUrlMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
        _thumbnailUrlMeta,
        thumbnailUrl.isAcceptableOrUnknown(
          data['thumbnail_url']!,
          _thumbnailUrlMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_local_path')) {
      context.handle(
        _thumbnailLocalPathMeta,
        thumbnailLocalPath.isAcceptableOrUnknown(
          data['thumbnail_local_path']!,
          _thumbnailLocalPathMeta,
        ),
      );
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageMediaTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageMediaTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_local_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      fileUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_url'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      thumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_url'],
      ),
      thumbnailLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_local_path'],
      ),
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
    );
  }

  @override
  $MessageMediaTableTable createAlias(String alias) {
    return $MessageMediaTableTable(attachedDatabase, alias);
  }
}

class MessageMediaTableData extends DataClass
    implements Insertable<MessageMediaTableData> {
  final String id;
  final String messageLocalId;
  final String conversationId;
  final String? fileUrl;
  final String? localPath;

  /// 'image' | 'video' | 'voice' | 'document'
  final String mediaType;
  final String fileName;
  final int fileSize;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String? thumbnailLocalPath;

  /// 'normal' | 'high'
  final String quality;
  final DateTime? expiresAt;
  const MessageMediaTableData({
    required this.id,
    required this.messageLocalId,
    required this.conversationId,
    this.fileUrl,
    this.localPath,
    required this.mediaType,
    required this.fileName,
    required this.fileSize,
    this.durationSeconds,
    this.thumbnailUrl,
    this.thumbnailLocalPath,
    required this.quality,
    this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_local_id'] = Variable<String>(messageLocalId);
    map['conversation_id'] = Variable<String>(conversationId);
    if (!nullToAbsent || fileUrl != null) {
      map['file_url'] = Variable<String>(fileUrl);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['media_type'] = Variable<String>(mediaType);
    map['file_name'] = Variable<String>(fileName);
    map['file_size'] = Variable<int>(fileSize);
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    if (!nullToAbsent || thumbnailLocalPath != null) {
      map['thumbnail_local_path'] = Variable<String>(thumbnailLocalPath);
    }
    map['quality'] = Variable<String>(quality);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    return map;
  }

  MessageMediaTableCompanion toCompanion(bool nullToAbsent) {
    return MessageMediaTableCompanion(
      id: Value(id),
      messageLocalId: Value(messageLocalId),
      conversationId: Value(conversationId),
      fileUrl: fileUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(fileUrl),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      mediaType: Value(mediaType),
      fileName: Value(fileName),
      fileSize: Value(fileSize),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      thumbnailLocalPath: thumbnailLocalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailLocalPath),
      quality: Value(quality),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory MessageMediaTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageMediaTableData(
      id: serializer.fromJson<String>(json['id']),
      messageLocalId: serializer.fromJson<String>(json['messageLocalId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      fileUrl: serializer.fromJson<String?>(json['fileUrl']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      thumbnailLocalPath: serializer.fromJson<String?>(
        json['thumbnailLocalPath'],
      ),
      quality: serializer.fromJson<String>(json['quality']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageLocalId': serializer.toJson<String>(messageLocalId),
      'conversationId': serializer.toJson<String>(conversationId),
      'fileUrl': serializer.toJson<String?>(fileUrl),
      'localPath': serializer.toJson<String?>(localPath),
      'mediaType': serializer.toJson<String>(mediaType),
      'fileName': serializer.toJson<String>(fileName),
      'fileSize': serializer.toJson<int>(fileSize),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'thumbnailLocalPath': serializer.toJson<String?>(thumbnailLocalPath),
      'quality': serializer.toJson<String>(quality),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
    };
  }

  MessageMediaTableData copyWith({
    String? id,
    String? messageLocalId,
    String? conversationId,
    Value<String?> fileUrl = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    String? mediaType,
    String? fileName,
    int? fileSize,
    Value<int?> durationSeconds = const Value.absent(),
    Value<String?> thumbnailUrl = const Value.absent(),
    Value<String?> thumbnailLocalPath = const Value.absent(),
    String? quality,
    Value<DateTime?> expiresAt = const Value.absent(),
  }) => MessageMediaTableData(
    id: id ?? this.id,
    messageLocalId: messageLocalId ?? this.messageLocalId,
    conversationId: conversationId ?? this.conversationId,
    fileUrl: fileUrl.present ? fileUrl.value : this.fileUrl,
    localPath: localPath.present ? localPath.value : this.localPath,
    mediaType: mediaType ?? this.mediaType,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
    thumbnailUrl: thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
    thumbnailLocalPath: thumbnailLocalPath.present
        ? thumbnailLocalPath.value
        : this.thumbnailLocalPath,
    quality: quality ?? this.quality,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
  );
  MessageMediaTableData copyWithCompanion(MessageMediaTableCompanion data) {
    return MessageMediaTableData(
      id: data.id.present ? data.id.value : this.id,
      messageLocalId: data.messageLocalId.present
          ? data.messageLocalId.value
          : this.messageLocalId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      fileUrl: data.fileUrl.present ? data.fileUrl.value : this.fileUrl,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      thumbnailLocalPath: data.thumbnailLocalPath.present
          ? data.thumbnailLocalPath.value
          : this.thumbnailLocalPath,
      quality: data.quality.present ? data.quality.value : this.quality,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageMediaTableData(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('localPath: $localPath, ')
          ..write('mediaType: $mediaType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('thumbnailLocalPath: $thumbnailLocalPath, ')
          ..write('quality: $quality, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageLocalId,
    conversationId,
    fileUrl,
    localPath,
    mediaType,
    fileName,
    fileSize,
    durationSeconds,
    thumbnailUrl,
    thumbnailLocalPath,
    quality,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageMediaTableData &&
          other.id == this.id &&
          other.messageLocalId == this.messageLocalId &&
          other.conversationId == this.conversationId &&
          other.fileUrl == this.fileUrl &&
          other.localPath == this.localPath &&
          other.mediaType == this.mediaType &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.durationSeconds == this.durationSeconds &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.thumbnailLocalPath == this.thumbnailLocalPath &&
          other.quality == this.quality &&
          other.expiresAt == this.expiresAt);
}

class MessageMediaTableCompanion
    extends UpdateCompanion<MessageMediaTableData> {
  final Value<String> id;
  final Value<String> messageLocalId;
  final Value<String> conversationId;
  final Value<String?> fileUrl;
  final Value<String?> localPath;
  final Value<String> mediaType;
  final Value<String> fileName;
  final Value<int> fileSize;
  final Value<int?> durationSeconds;
  final Value<String?> thumbnailUrl;
  final Value<String?> thumbnailLocalPath;
  final Value<String> quality;
  final Value<DateTime?> expiresAt;
  final Value<int> rowid;
  const MessageMediaTableCompanion({
    this.id = const Value.absent(),
    this.messageLocalId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.fileUrl = const Value.absent(),
    this.localPath = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.thumbnailLocalPath = const Value.absent(),
    this.quality = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageMediaTableCompanion.insert({
    required String id,
    required String messageLocalId,
    required String conversationId,
    this.fileUrl = const Value.absent(),
    this.localPath = const Value.absent(),
    required String mediaType,
    required String fileName,
    this.fileSize = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.thumbnailLocalPath = const Value.absent(),
    this.quality = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageLocalId = Value(messageLocalId),
       conversationId = Value(conversationId),
       mediaType = Value(mediaType),
       fileName = Value(fileName);
  static Insertable<MessageMediaTableData> custom({
    Expression<String>? id,
    Expression<String>? messageLocalId,
    Expression<String>? conversationId,
    Expression<String>? fileUrl,
    Expression<String>? localPath,
    Expression<String>? mediaType,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<int>? durationSeconds,
    Expression<String>? thumbnailUrl,
    Expression<String>? thumbnailLocalPath,
    Expression<String>? quality,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageLocalId != null) 'message_local_id': messageLocalId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (fileUrl != null) 'file_url': fileUrl,
      if (localPath != null) 'local_path': localPath,
      if (mediaType != null) 'media_type': mediaType,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (thumbnailLocalPath != null)
        'thumbnail_local_path': thumbnailLocalPath,
      if (quality != null) 'quality': quality,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageMediaTableCompanion copyWith({
    Value<String>? id,
    Value<String>? messageLocalId,
    Value<String>? conversationId,
    Value<String?>? fileUrl,
    Value<String?>? localPath,
    Value<String>? mediaType,
    Value<String>? fileName,
    Value<int>? fileSize,
    Value<int?>? durationSeconds,
    Value<String?>? thumbnailUrl,
    Value<String?>? thumbnailLocalPath,
    Value<String>? quality,
    Value<DateTime?>? expiresAt,
    Value<int>? rowid,
  }) {
    return MessageMediaTableCompanion(
      id: id ?? this.id,
      messageLocalId: messageLocalId ?? this.messageLocalId,
      conversationId: conversationId ?? this.conversationId,
      fileUrl: fileUrl ?? this.fileUrl,
      localPath: localPath ?? this.localPath,
      mediaType: mediaType ?? this.mediaType,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailLocalPath: thumbnailLocalPath ?? this.thumbnailLocalPath,
      quality: quality ?? this.quality,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageLocalId.present) {
      map['message_local_id'] = Variable<String>(messageLocalId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (fileUrl.present) {
      map['file_url'] = Variable<String>(fileUrl.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (thumbnailLocalPath.present) {
      map['thumbnail_local_path'] = Variable<String>(thumbnailLocalPath.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageMediaTableCompanion(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('localPath: $localPath, ')
          ..write('mediaType: $mediaType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('thumbnailLocalPath: $thumbnailLocalPath, ')
          ..write('quality: $quality, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FriendshipsTableTable extends FriendshipsTable
    with TableInfo<$FriendshipsTableTable, FriendshipsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FriendshipsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userAIdMeta = const VerificationMeta(
    'userAId',
  );
  @override
  late final GeneratedColumn<String> userAId = GeneratedColumn<String>(
    'user_a_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userBIdMeta = const VerificationMeta(
    'userBId',
  );
  @override
  late final GeneratedColumn<String> userBId = GeneratedColumn<String>(
    'user_b_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customNicknameMeta = const VerificationMeta(
    'customNickname',
  );
  @override
  late final GeneratedColumn<String> customNickname = GeneratedColumn<String>(
    'custom_nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userAId,
    userBId,
    customNickname,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friendships_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<FriendshipsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_a_id')) {
      context.handle(
        _userAIdMeta,
        userAId.isAcceptableOrUnknown(data['user_a_id']!, _userAIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userAIdMeta);
    }
    if (data.containsKey('user_b_id')) {
      context.handle(
        _userBIdMeta,
        userBId.isAcceptableOrUnknown(data['user_b_id']!, _userBIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userBIdMeta);
    }
    if (data.containsKey('custom_nickname')) {
      context.handle(
        _customNicknameMeta,
        customNickname.isAcceptableOrUnknown(
          data['custom_nickname']!,
          _customNicknameMeta,
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
  FriendshipsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FriendshipsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userAId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_a_id'],
      )!,
      userBId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_b_id'],
      )!,
      customNickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_nickname'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FriendshipsTableTable createAlias(String alias) {
    return $FriendshipsTableTable(attachedDatabase, alias);
  }
}

class FriendshipsTableData extends DataClass
    implements Insertable<FriendshipsTableData> {
  final String id;
  final String userAId;
  final String userBId;

  /// Local-only nickname for the other user. Never synced to server.
  final String? customNickname;
  final DateTime createdAt;
  const FriendshipsTableData({
    required this.id,
    required this.userAId,
    required this.userBId,
    this.customNickname,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_a_id'] = Variable<String>(userAId);
    map['user_b_id'] = Variable<String>(userBId);
    if (!nullToAbsent || customNickname != null) {
      map['custom_nickname'] = Variable<String>(customNickname);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FriendshipsTableCompanion toCompanion(bool nullToAbsent) {
    return FriendshipsTableCompanion(
      id: Value(id),
      userAId: Value(userAId),
      userBId: Value(userBId),
      customNickname: customNickname == null && nullToAbsent
          ? const Value.absent()
          : Value(customNickname),
      createdAt: Value(createdAt),
    );
  }

  factory FriendshipsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FriendshipsTableData(
      id: serializer.fromJson<String>(json['id']),
      userAId: serializer.fromJson<String>(json['userAId']),
      userBId: serializer.fromJson<String>(json['userBId']),
      customNickname: serializer.fromJson<String?>(json['customNickname']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userAId': serializer.toJson<String>(userAId),
      'userBId': serializer.toJson<String>(userBId),
      'customNickname': serializer.toJson<String?>(customNickname),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FriendshipsTableData copyWith({
    String? id,
    String? userAId,
    String? userBId,
    Value<String?> customNickname = const Value.absent(),
    DateTime? createdAt,
  }) => FriendshipsTableData(
    id: id ?? this.id,
    userAId: userAId ?? this.userAId,
    userBId: userBId ?? this.userBId,
    customNickname: customNickname.present
        ? customNickname.value
        : this.customNickname,
    createdAt: createdAt ?? this.createdAt,
  );
  FriendshipsTableData copyWithCompanion(FriendshipsTableCompanion data) {
    return FriendshipsTableData(
      id: data.id.present ? data.id.value : this.id,
      userAId: data.userAId.present ? data.userAId.value : this.userAId,
      userBId: data.userBId.present ? data.userBId.value : this.userBId,
      customNickname: data.customNickname.present
          ? data.customNickname.value
          : this.customNickname,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FriendshipsTableData(')
          ..write('id: $id, ')
          ..write('userAId: $userAId, ')
          ..write('userBId: $userBId, ')
          ..write('customNickname: $customNickname, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userAId, userBId, customNickname, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FriendshipsTableData &&
          other.id == this.id &&
          other.userAId == this.userAId &&
          other.userBId == this.userBId &&
          other.customNickname == this.customNickname &&
          other.createdAt == this.createdAt);
}

class FriendshipsTableCompanion extends UpdateCompanion<FriendshipsTableData> {
  final Value<String> id;
  final Value<String> userAId;
  final Value<String> userBId;
  final Value<String?> customNickname;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FriendshipsTableCompanion({
    this.id = const Value.absent(),
    this.userAId = const Value.absent(),
    this.userBId = const Value.absent(),
    this.customNickname = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FriendshipsTableCompanion.insert({
    required String id,
    required String userAId,
    required String userBId,
    this.customNickname = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userAId = Value(userAId),
       userBId = Value(userBId),
       createdAt = Value(createdAt);
  static Insertable<FriendshipsTableData> custom({
    Expression<String>? id,
    Expression<String>? userAId,
    Expression<String>? userBId,
    Expression<String>? customNickname,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userAId != null) 'user_a_id': userAId,
      if (userBId != null) 'user_b_id': userBId,
      if (customNickname != null) 'custom_nickname': customNickname,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FriendshipsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? userAId,
    Value<String>? userBId,
    Value<String?>? customNickname,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return FriendshipsTableCompanion(
      id: id ?? this.id,
      userAId: userAId ?? this.userAId,
      userBId: userBId ?? this.userBId,
      customNickname: customNickname ?? this.customNickname,
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
    if (userAId.present) {
      map['user_a_id'] = Variable<String>(userAId.value);
    }
    if (userBId.present) {
      map['user_b_id'] = Variable<String>(userBId.value);
    }
    if (customNickname.present) {
      map['custom_nickname'] = Variable<String>(customNickname.value);
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
    return (StringBuffer('FriendshipsTableCompanion(')
          ..write('id: $id, ')
          ..write('userAId: $userAId, ')
          ..write('userBId: $userBId, ')
          ..write('customNickname: $customNickname, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FriendRequestsTableTable extends FriendRequestsTable
    with TableInfo<$FriendRequestsTableTable, FriendRequestsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FriendRequestsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromUserIdMeta = const VerificationMeta(
    'fromUserId',
  );
  @override
  late final GeneratedColumn<String> fromUserId = GeneratedColumn<String>(
    'from_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toUserIdMeta = const VerificationMeta(
    'toUserId',
  );
  @override
  late final GeneratedColumn<String> toUserId = GeneratedColumn<String>(
    'to_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromUserId,
    toUserId,
    status,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friend_requests_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<FriendRequestsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_user_id')) {
      context.handle(
        _fromUserIdMeta,
        fromUserId.isAcceptableOrUnknown(
          data['from_user_id']!,
          _fromUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromUserIdMeta);
    }
    if (data.containsKey('to_user_id')) {
      context.handle(
        _toUserIdMeta,
        toUserId.isAcceptableOrUnknown(data['to_user_id']!, _toUserIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toUserIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
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
  FriendRequestsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FriendRequestsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_user_id'],
      )!,
      toUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_user_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FriendRequestsTableTable createAlias(String alias) {
    return $FriendRequestsTableTable(attachedDatabase, alias);
  }
}

class FriendRequestsTableData extends DataClass
    implements Insertable<FriendRequestsTableData> {
  final String id;
  final String fromUserId;
  final String toUserId;

  /// 'pending' | 'accepted' | 'declined'
  final String status;
  final DateTime createdAt;
  const FriendRequestsTableData({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.status,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_user_id'] = Variable<String>(fromUserId);
    map['to_user_id'] = Variable<String>(toUserId);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FriendRequestsTableCompanion toCompanion(bool nullToAbsent) {
    return FriendRequestsTableCompanion(
      id: Value(id),
      fromUserId: Value(fromUserId),
      toUserId: Value(toUserId),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory FriendRequestsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FriendRequestsTableData(
      id: serializer.fromJson<String>(json['id']),
      fromUserId: serializer.fromJson<String>(json['fromUserId']),
      toUserId: serializer.fromJson<String>(json['toUserId']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromUserId': serializer.toJson<String>(fromUserId),
      'toUserId': serializer.toJson<String>(toUserId),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FriendRequestsTableData copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    String? status,
    DateTime? createdAt,
  }) => FriendRequestsTableData(
    id: id ?? this.id,
    fromUserId: fromUserId ?? this.fromUserId,
    toUserId: toUserId ?? this.toUserId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  FriendRequestsTableData copyWithCompanion(FriendRequestsTableCompanion data) {
    return FriendRequestsTableData(
      id: data.id.present ? data.id.value : this.id,
      fromUserId: data.fromUserId.present
          ? data.fromUserId.value
          : this.fromUserId,
      toUserId: data.toUserId.present ? data.toUserId.value : this.toUserId,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FriendRequestsTableData(')
          ..write('id: $id, ')
          ..write('fromUserId: $fromUserId, ')
          ..write('toUserId: $toUserId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fromUserId, toUserId, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FriendRequestsTableData &&
          other.id == this.id &&
          other.fromUserId == this.fromUserId &&
          other.toUserId == this.toUserId &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class FriendRequestsTableCompanion
    extends UpdateCompanion<FriendRequestsTableData> {
  final Value<String> id;
  final Value<String> fromUserId;
  final Value<String> toUserId;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FriendRequestsTableCompanion({
    this.id = const Value.absent(),
    this.fromUserId = const Value.absent(),
    this.toUserId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FriendRequestsTableCompanion.insert({
    required String id,
    required String fromUserId,
    required String toUserId,
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromUserId = Value(fromUserId),
       toUserId = Value(toUserId),
       createdAt = Value(createdAt);
  static Insertable<FriendRequestsTableData> custom({
    Expression<String>? id,
    Expression<String>? fromUserId,
    Expression<String>? toUserId,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromUserId != null) 'from_user_id': fromUserId,
      if (toUserId != null) 'to_user_id': toUserId,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FriendRequestsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? fromUserId,
    Value<String>? toUserId,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return FriendRequestsTableCompanion(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      status: status ?? this.status,
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
    if (fromUserId.present) {
      map['from_user_id'] = Variable<String>(fromUserId.value);
    }
    if (toUserId.present) {
      map['to_user_id'] = Variable<String>(toUserId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
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
    return (StringBuffer('FriendRequestsTableCompanion(')
          ..write('id: $id, ')
          ..write('fromUserId: $fromUserId, ')
          ..write('toUserId: $toUserId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReactionsTableTable extends ReactionsTable
    with TableInfo<$ReactionsTableTable, ReactionsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReactionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageLocalIdMeta = const VerificationMeta(
    'messageLocalId',
  );
  @override
  late final GeneratedColumn<String> messageLocalId = GeneratedColumn<String>(
    'message_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageLocalId,
    conversationId,
    userId,
    emoji,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reactions_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReactionsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_local_id')) {
      context.handle(
        _messageLocalIdMeta,
        messageLocalId.isAcceptableOrUnknown(
          data['message_local_id']!,
          _messageLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageLocalIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
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
  ReactionsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReactionsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_local_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReactionsTableTable createAlias(String alias) {
    return $ReactionsTableTable(attachedDatabase, alias);
  }
}

class ReactionsTableData extends DataClass
    implements Insertable<ReactionsTableData> {
  final String id;
  final String messageLocalId;
  final String conversationId;
  final String userId;
  final String emoji;
  final DateTime createdAt;
  const ReactionsTableData({
    required this.id,
    required this.messageLocalId,
    required this.conversationId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['message_local_id'] = Variable<String>(messageLocalId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['user_id'] = Variable<String>(userId);
    map['emoji'] = Variable<String>(emoji);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReactionsTableCompanion toCompanion(bool nullToAbsent) {
    return ReactionsTableCompanion(
      id: Value(id),
      messageLocalId: Value(messageLocalId),
      conversationId: Value(conversationId),
      userId: Value(userId),
      emoji: Value(emoji),
      createdAt: Value(createdAt),
    );
  }

  factory ReactionsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReactionsTableData(
      id: serializer.fromJson<String>(json['id']),
      messageLocalId: serializer.fromJson<String>(json['messageLocalId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      userId: serializer.fromJson<String>(json['userId']),
      emoji: serializer.fromJson<String>(json['emoji']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageLocalId': serializer.toJson<String>(messageLocalId),
      'conversationId': serializer.toJson<String>(conversationId),
      'userId': serializer.toJson<String>(userId),
      'emoji': serializer.toJson<String>(emoji),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReactionsTableData copyWith({
    String? id,
    String? messageLocalId,
    String? conversationId,
    String? userId,
    String? emoji,
    DateTime? createdAt,
  }) => ReactionsTableData(
    id: id ?? this.id,
    messageLocalId: messageLocalId ?? this.messageLocalId,
    conversationId: conversationId ?? this.conversationId,
    userId: userId ?? this.userId,
    emoji: emoji ?? this.emoji,
    createdAt: createdAt ?? this.createdAt,
  );
  ReactionsTableData copyWithCompanion(ReactionsTableCompanion data) {
    return ReactionsTableData(
      id: data.id.present ? data.id.value : this.id,
      messageLocalId: data.messageLocalId.present
          ? data.messageLocalId.value
          : this.messageLocalId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      userId: data.userId.present ? data.userId.value : this.userId,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReactionsTableData(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, messageLocalId, conversationId, userId, emoji, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReactionsTableData &&
          other.id == this.id &&
          other.messageLocalId == this.messageLocalId &&
          other.conversationId == this.conversationId &&
          other.userId == this.userId &&
          other.emoji == this.emoji &&
          other.createdAt == this.createdAt);
}

class ReactionsTableCompanion extends UpdateCompanion<ReactionsTableData> {
  final Value<String> id;
  final Value<String> messageLocalId;
  final Value<String> conversationId;
  final Value<String> userId;
  final Value<String> emoji;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReactionsTableCompanion({
    this.id = const Value.absent(),
    this.messageLocalId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.userId = const Value.absent(),
    this.emoji = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReactionsTableCompanion.insert({
    required String id,
    required String messageLocalId,
    required String conversationId,
    required String userId,
    required String emoji,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       messageLocalId = Value(messageLocalId),
       conversationId = Value(conversationId),
       userId = Value(userId),
       emoji = Value(emoji),
       createdAt = Value(createdAt);
  static Insertable<ReactionsTableData> custom({
    Expression<String>? id,
    Expression<String>? messageLocalId,
    Expression<String>? conversationId,
    Expression<String>? userId,
    Expression<String>? emoji,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageLocalId != null) 'message_local_id': messageLocalId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (userId != null) 'user_id': userId,
      if (emoji != null) 'emoji': emoji,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReactionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? messageLocalId,
    Value<String>? conversationId,
    Value<String>? userId,
    Value<String>? emoji,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReactionsTableCompanion(
      id: id ?? this.id,
      messageLocalId: messageLocalId ?? this.messageLocalId,
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      emoji: emoji ?? this.emoji,
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
    if (messageLocalId.present) {
      map['message_local_id'] = Variable<String>(messageLocalId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
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
    return (StringBuffer('ReactionsTableCompanion(')
          ..write('id: $id, ')
          ..write('messageLocalId: $messageLocalId, ')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTableTable extends AppSettingsTable
    with TableInfo<$AppSettingsTableTable, AppSettingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'app_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsTableData> instance, {
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
  AppSettingsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsTableData(
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
  $AppSettingsTableTable createAlias(String alias) {
    return $AppSettingsTableTable(attachedDatabase, alias);
  }
}

class AppSettingsTableData extends DataClass
    implements Insertable<AppSettingsTableData> {
  final String key;
  final String value;
  const AppSettingsTableData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory AppSettingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsTableData(
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

  AppSettingsTableData copyWith({String? key, String? value}) =>
      AppSettingsTableData(key: key ?? this.key, value: value ?? this.value);
  AppSettingsTableData copyWithCompanion(AppSettingsTableCompanion data) {
    return AppSettingsTableData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableData(')
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
      (other is AppSettingsTableData &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsTableCompanion extends UpdateCompanion<AppSettingsTableData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSettingsTableData> custom({
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

  AppSettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsTableCompanion(
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
    return (StringBuffer('AppSettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageDraftsTableTable extends MessageDraftsTable
    with TableInfo<$MessageDraftsTableTable, MessageDraftsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageDraftsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftTextMeta = const VerificationMeta(
    'draftText',
  );
  @override
  late final GeneratedColumn<String> draftText = GeneratedColumn<String>(
    'draft_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToLocalIdMeta = const VerificationMeta(
    'replyToLocalId',
  );
  @override
  late final GeneratedColumn<String> replyToLocalId = GeneratedColumn<String>(
    'reply_to_local_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    draftText,
    replyToLocalId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_drafts_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageDraftsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('draft_text')) {
      context.handle(
        _draftTextMeta,
        draftText.isAcceptableOrUnknown(data['draft_text']!, _draftTextMeta),
      );
    } else if (isInserting) {
      context.missing(_draftTextMeta);
    }
    if (data.containsKey('reply_to_local_id')) {
      context.handle(
        _replyToLocalIdMeta,
        replyToLocalId.isAcceptableOrUnknown(
          data['reply_to_local_id']!,
          _replyToLocalIdMeta,
        ),
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
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  MessageDraftsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageDraftsTableData(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      draftText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_text'],
      )!,
      replyToLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_local_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MessageDraftsTableTable createAlias(String alias) {
    return $MessageDraftsTableTable(attachedDatabase, alias);
  }
}

class MessageDraftsTableData extends DataClass
    implements Insertable<MessageDraftsTableData> {
  final String conversationId;
  final String draftText;
  final String? replyToLocalId;
  final DateTime updatedAt;
  const MessageDraftsTableData({
    required this.conversationId,
    required this.draftText,
    this.replyToLocalId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['draft_text'] = Variable<String>(draftText);
    if (!nullToAbsent || replyToLocalId != null) {
      map['reply_to_local_id'] = Variable<String>(replyToLocalId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MessageDraftsTableCompanion toCompanion(bool nullToAbsent) {
    return MessageDraftsTableCompanion(
      conversationId: Value(conversationId),
      draftText: Value(draftText),
      replyToLocalId: replyToLocalId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToLocalId),
      updatedAt: Value(updatedAt),
    );
  }

  factory MessageDraftsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageDraftsTableData(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      draftText: serializer.fromJson<String>(json['draftText']),
      replyToLocalId: serializer.fromJson<String?>(json['replyToLocalId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'draftText': serializer.toJson<String>(draftText),
      'replyToLocalId': serializer.toJson<String?>(replyToLocalId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MessageDraftsTableData copyWith({
    String? conversationId,
    String? draftText,
    Value<String?> replyToLocalId = const Value.absent(),
    DateTime? updatedAt,
  }) => MessageDraftsTableData(
    conversationId: conversationId ?? this.conversationId,
    draftText: draftText ?? this.draftText,
    replyToLocalId: replyToLocalId.present
        ? replyToLocalId.value
        : this.replyToLocalId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MessageDraftsTableData copyWithCompanion(MessageDraftsTableCompanion data) {
    return MessageDraftsTableData(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      draftText: data.draftText.present ? data.draftText.value : this.draftText,
      replyToLocalId: data.replyToLocalId.present
          ? data.replyToLocalId.value
          : this.replyToLocalId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageDraftsTableData(')
          ..write('conversationId: $conversationId, ')
          ..write('draftText: $draftText, ')
          ..write('replyToLocalId: $replyToLocalId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(conversationId, draftText, replyToLocalId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageDraftsTableData &&
          other.conversationId == this.conversationId &&
          other.draftText == this.draftText &&
          other.replyToLocalId == this.replyToLocalId &&
          other.updatedAt == this.updatedAt);
}

class MessageDraftsTableCompanion
    extends UpdateCompanion<MessageDraftsTableData> {
  final Value<String> conversationId;
  final Value<String> draftText;
  final Value<String?> replyToLocalId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MessageDraftsTableCompanion({
    this.conversationId = const Value.absent(),
    this.draftText = const Value.absent(),
    this.replyToLocalId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageDraftsTableCompanion.insert({
    required String conversationId,
    required String draftText,
    this.replyToLocalId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       draftText = Value(draftText),
       updatedAt = Value(updatedAt);
  static Insertable<MessageDraftsTableData> custom({
    Expression<String>? conversationId,
    Expression<String>? draftText,
    Expression<String>? replyToLocalId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (draftText != null) 'draft_text': draftText,
      if (replyToLocalId != null) 'reply_to_local_id': replyToLocalId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageDraftsTableCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? draftText,
    Value<String?>? replyToLocalId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MessageDraftsTableCompanion(
      conversationId: conversationId ?? this.conversationId,
      draftText: draftText ?? this.draftText,
      replyToLocalId: replyToLocalId ?? this.replyToLocalId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (draftText.present) {
      map['draft_text'] = Variable<String>(draftText.value);
    }
    if (replyToLocalId.present) {
      map['reply_to_local_id'] = Variable<String>(replyToLocalId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageDraftsTableCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('draftText: $draftText, ')
          ..write('replyToLocalId: $replyToLocalId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTableTable usersTable = $UsersTableTable(this);
  late final $ConversationsTableTable conversationsTable =
      $ConversationsTableTable(this);
  late final $ConversationMembersTableTable conversationMembersTable =
      $ConversationMembersTableTable(this);
  late final $MessagesTableTable messagesTable = $MessagesTableTable(this);
  late final $MessageReceiptsTableTable messageReceiptsTable =
      $MessageReceiptsTableTable(this);
  late final $MessageMediaTableTable messageMediaTable =
      $MessageMediaTableTable(this);
  late final $FriendshipsTableTable friendshipsTable = $FriendshipsTableTable(
    this,
  );
  late final $FriendRequestsTableTable friendRequestsTable =
      $FriendRequestsTableTable(this);
  late final $ReactionsTableTable reactionsTable = $ReactionsTableTable(this);
  late final $AppSettingsTableTable appSettingsTable = $AppSettingsTableTable(
    this,
  );
  late final $MessageDraftsTableTable messageDraftsTable =
      $MessageDraftsTableTable(this);
  late final UsersDao usersDao = UsersDao(this as AppDatabase);
  late final ConversationsDao conversationsDao = ConversationsDao(
    this as AppDatabase,
  );
  late final MessagesDao messagesDao = MessagesDao(this as AppDatabase);
  late final FriendsDao friendsDao = FriendsDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    usersTable,
    conversationsTable,
    conversationMembersTable,
    messagesTable,
    messageReceiptsTable,
    messageMediaTable,
    friendshipsTable,
    friendRequestsTable,
    reactionsTable,
    appSettingsTable,
    messageDraftsTable,
  ];
}

typedef $$UsersTableTableCreateCompanionBuilder =
    UsersTableCompanion Function({
      required String id,
      required String displayName,
      required String username,
      Value<String?> email,
      Value<String?> avatarUrl,
      Value<String?> about,
      required String friendCode,
      Value<bool> isOnline,
      Value<DateTime?> lastSeen,
      Value<String?> publicKey,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$UsersTableTableUpdateCompanionBuilder =
    UsersTableCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String> username,
      Value<String?> email,
      Value<String?> avatarUrl,
      Value<String?> about,
      Value<String> friendCode,
      Value<bool> isOnline,
      Value<DateTime?> lastSeen,
      Value<String?> publicKey,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$UsersTableTableFilterComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableFilterComposer({
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

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get about => $composableBuilder(
    column: $table.about,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendCode => $composableBuilder(
    column: $table.friendCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOnline => $composableBuilder(
    column: $table.isOnline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableOrderingComposer({
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

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get about => $composableBuilder(
    column: $table.about,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendCode => $composableBuilder(
    column: $table.friendCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOnline => $composableBuilder(
    column: $table.isOnline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTableTable> {
  $$UsersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get about =>
      $composableBuilder(column: $table.about, builder: (column) => column);

  GeneratedColumn<String> get friendCode => $composableBuilder(
    column: $table.friendCode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOnline =>
      $composableBuilder(column: $table.isOnline, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UsersTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTableTable,
          UsersTableData,
          $$UsersTableTableFilterComposer,
          $$UsersTableTableOrderingComposer,
          $$UsersTableTableAnnotationComposer,
          $$UsersTableTableCreateCompanionBuilder,
          $$UsersTableTableUpdateCompanionBuilder,
          (
            UsersTableData,
            BaseReferences<_$AppDatabase, $UsersTableTable, UsersTableData>,
          ),
          UsersTableData,
          PrefetchHooks Function()
        > {
  $$UsersTableTableTableManager(_$AppDatabase db, $UsersTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> about = const Value.absent(),
                Value<String> friendCode = const Value.absent(),
                Value<bool> isOnline = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersTableCompanion(
                id: id,
                displayName: displayName,
                username: username,
                email: email,
                avatarUrl: avatarUrl,
                about: about,
                friendCode: friendCode,
                isOnline: isOnline,
                lastSeen: lastSeen,
                publicKey: publicKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String username,
                Value<String?> email = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> about = const Value.absent(),
                required String friendCode,
                Value<bool> isOnline = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => UsersTableCompanion.insert(
                id: id,
                displayName: displayName,
                username: username,
                email: email,
                avatarUrl: avatarUrl,
                about: about,
                friendCode: friendCode,
                isOnline: isOnline,
                lastSeen: lastSeen,
                publicKey: publicKey,
                createdAt: createdAt,
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

typedef $$UsersTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTableTable,
      UsersTableData,
      $$UsersTableTableFilterComposer,
      $$UsersTableTableOrderingComposer,
      $$UsersTableTableAnnotationComposer,
      $$UsersTableTableCreateCompanionBuilder,
      $$UsersTableTableUpdateCompanionBuilder,
      (
        UsersTableData,
        BaseReferences<_$AppDatabase, $UsersTableTable, UsersTableData>,
      ),
      UsersTableData,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableTableCreateCompanionBuilder =
    ConversationsTableCompanion Function({
      required String id,
      required String type,
      Value<String?> name,
      Value<String?> iconUrl,
      required String createdById,
      Value<String?> lastMessagePreview,
      Value<DateTime?> lastMessageAt,
      Value<int> disappearingDuration,
      Value<bool> isPinned,
      Value<DateTime?> muteUntil,
      Value<String?> wallpaperPath,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableTableUpdateCompanionBuilder =
    ConversationsTableCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String?> name,
      Value<String?> iconUrl,
      Value<String> createdById,
      Value<String?> lastMessagePreview,
      Value<DateTime?> lastMessageAt,
      Value<int> disappearingDuration,
      Value<bool> isPinned,
      Value<DateTime?> muteUntil,
      Value<String?> wallpaperPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ConversationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconUrl => $composableBuilder(
    column: $table.iconUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdById => $composableBuilder(
    column: $table.createdById,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disappearingDuration => $composableBuilder(
    column: $table.disappearingDuration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get muteUntil => $composableBuilder(
    column: $table.muteUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wallpaperPath => $composableBuilder(
    column: $table.wallpaperPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconUrl => $composableBuilder(
    column: $table.iconUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdById => $composableBuilder(
    column: $table.createdById,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disappearingDuration => $composableBuilder(
    column: $table.disappearingDuration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get muteUntil => $composableBuilder(
    column: $table.muteUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wallpaperPath => $composableBuilder(
    column: $table.wallpaperPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get iconUrl =>
      $composableBuilder(column: $table.iconUrl, builder: (column) => column);

  GeneratedColumn<String> get createdById => $composableBuilder(
    column: $table.createdById,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get disappearingDuration => $composableBuilder(
    column: $table.disappearingDuration,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<DateTime> get muteUntil =>
      $composableBuilder(column: $table.muteUntil, builder: (column) => column);

  GeneratedColumn<String> get wallpaperPath => $composableBuilder(
    column: $table.wallpaperPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTableTable,
          ConversationsTableData,
          $$ConversationsTableTableFilterComposer,
          $$ConversationsTableTableOrderingComposer,
          $$ConversationsTableTableAnnotationComposer,
          $$ConversationsTableTableCreateCompanionBuilder,
          $$ConversationsTableTableUpdateCompanionBuilder,
          (
            ConversationsTableData,
            BaseReferences<
              _$AppDatabase,
              $ConversationsTableTable,
              ConversationsTableData
            >,
          ),
          ConversationsTableData,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableTableManager(
    _$AppDatabase db,
    $ConversationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> iconUrl = const Value.absent(),
                Value<String> createdById = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<int> disappearingDuration = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<DateTime?> muteUntil = const Value.absent(),
                Value<String?> wallpaperPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsTableCompanion(
                id: id,
                type: type,
                name: name,
                iconUrl: iconUrl,
                createdById: createdById,
                lastMessagePreview: lastMessagePreview,
                lastMessageAt: lastMessageAt,
                disappearingDuration: disappearingDuration,
                isPinned: isPinned,
                muteUntil: muteUntil,
                wallpaperPath: wallpaperPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                Value<String?> name = const Value.absent(),
                Value<String?> iconUrl = const Value.absent(),
                required String createdById,
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<int> disappearingDuration = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<DateTime?> muteUntil = const Value.absent(),
                Value<String?> wallpaperPath = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsTableCompanion.insert(
                id: id,
                type: type,
                name: name,
                iconUrl: iconUrl,
                createdById: createdById,
                lastMessagePreview: lastMessagePreview,
                lastMessageAt: lastMessageAt,
                disappearingDuration: disappearingDuration,
                isPinned: isPinned,
                muteUntil: muteUntil,
                wallpaperPath: wallpaperPath,
                createdAt: createdAt,
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

typedef $$ConversationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTableTable,
      ConversationsTableData,
      $$ConversationsTableTableFilterComposer,
      $$ConversationsTableTableOrderingComposer,
      $$ConversationsTableTableAnnotationComposer,
      $$ConversationsTableTableCreateCompanionBuilder,
      $$ConversationsTableTableUpdateCompanionBuilder,
      (
        ConversationsTableData,
        BaseReferences<
          _$AppDatabase,
          $ConversationsTableTable,
          ConversationsTableData
        >,
      ),
      ConversationsTableData,
      PrefetchHooks Function()
    >;
typedef $$ConversationMembersTableTableCreateCompanionBuilder =
    ConversationMembersTableCompanion Function({
      required String id,
      required String conversationId,
      required String userId,
      Value<String> role,
      required DateTime joinedAt,
      Value<String?> lastReadMessageId,
      Value<int> rowid,
    });
typedef $$ConversationMembersTableTableUpdateCompanionBuilder =
    ConversationMembersTableCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> userId,
      Value<String> role,
      Value<DateTime> joinedAt,
      Value<String?> lastReadMessageId,
      Value<int> rowid,
    });

class $$ConversationMembersTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationMembersTableTable> {
  $$ConversationMembersTableTableFilterComposer({
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

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationMembersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationMembersTableTable> {
  $$ConversationMembersTableTableOrderingComposer({
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

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationMembersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationMembersTableTable> {
  $$ConversationMembersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  GeneratedColumn<String> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => column,
  );
}

class $$ConversationMembersTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationMembersTableTable,
          ConversationMembersTableData,
          $$ConversationMembersTableTableFilterComposer,
          $$ConversationMembersTableTableOrderingComposer,
          $$ConversationMembersTableTableAnnotationComposer,
          $$ConversationMembersTableTableCreateCompanionBuilder,
          $$ConversationMembersTableTableUpdateCompanionBuilder,
          (
            ConversationMembersTableData,
            BaseReferences<
              _$AppDatabase,
              $ConversationMembersTableTable,
              ConversationMembersTableData
            >,
          ),
          ConversationMembersTableData,
          PrefetchHooks Function()
        > {
  $$ConversationMembersTableTableTableManager(
    _$AppDatabase db,
    $ConversationMembersTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationMembersTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ConversationMembersTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConversationMembersTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<DateTime> joinedAt = const Value.absent(),
                Value<String?> lastReadMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationMembersTableCompanion(
                id: id,
                conversationId: conversationId,
                userId: userId,
                role: role,
                joinedAt: joinedAt,
                lastReadMessageId: lastReadMessageId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String userId,
                Value<String> role = const Value.absent(),
                required DateTime joinedAt,
                Value<String?> lastReadMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationMembersTableCompanion.insert(
                id: id,
                conversationId: conversationId,
                userId: userId,
                role: role,
                joinedAt: joinedAt,
                lastReadMessageId: lastReadMessageId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationMembersTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationMembersTableTable,
      ConversationMembersTableData,
      $$ConversationMembersTableTableFilterComposer,
      $$ConversationMembersTableTableOrderingComposer,
      $$ConversationMembersTableTableAnnotationComposer,
      $$ConversationMembersTableTableCreateCompanionBuilder,
      $$ConversationMembersTableTableUpdateCompanionBuilder,
      (
        ConversationMembersTableData,
        BaseReferences<
          _$AppDatabase,
          $ConversationMembersTableTable,
          ConversationMembersTableData
        >,
      ),
      ConversationMembersTableData,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableTableCreateCompanionBuilder =
    MessagesTableCompanion Function({
      required String localId,
      Value<String?> serverId,
      required String conversationId,
      required String senderId,
      required String type,
      required String encryptedBody,
      required String iv,
      Value<String?> decryptedBody,
      Value<String?> replyToId,
      Value<String?> replyPreview,
      Value<bool> isDeletedForEveryone,
      Value<bool> isDeletedForMe,
      Value<bool> isPinned,
      Value<bool> isStarred,
      Value<DateTime?> expiresAt,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MessagesTableTableUpdateCompanionBuilder =
    MessagesTableCompanion Function({
      Value<String> localId,
      Value<String?> serverId,
      Value<String> conversationId,
      Value<String> senderId,
      Value<String> type,
      Value<String> encryptedBody,
      Value<String> iv,
      Value<String?> decryptedBody,
      Value<String?> replyToId,
      Value<String?> replyPreview,
      Value<bool> isDeletedForEveryone,
      Value<bool> isDeletedForMe,
      Value<bool> isPinned,
      Value<bool> isStarred,
      Value<DateTime?> expiresAt,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MessagesTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iv => $composableBuilder(
    column: $table.iv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decryptedBody => $composableBuilder(
    column: $table.decryptedBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyPreview => $composableBuilder(
    column: $table.replyPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeletedForEveryone => $composableBuilder(
    column: $table.isDeletedForEveryone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeletedForMe => $composableBuilder(
    column: $table.isDeletedForMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isStarred => $composableBuilder(
    column: $table.isStarred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iv => $composableBuilder(
    column: $table.iv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decryptedBody => $composableBuilder(
    column: $table.decryptedBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyPreview => $composableBuilder(
    column: $table.replyPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeletedForEveryone => $composableBuilder(
    column: $table.isDeletedForEveryone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeletedForMe => $composableBuilder(
    column: $table.isDeletedForMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isStarred => $composableBuilder(
    column: $table.isStarred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iv =>
      $composableBuilder(column: $table.iv, builder: (column) => column);

  GeneratedColumn<String> get decryptedBody => $composableBuilder(
    column: $table.decryptedBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get replyPreview => $composableBuilder(
    column: $table.replyPreview,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeletedForEveryone => $composableBuilder(
    column: $table.isDeletedForEveryone,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeletedForMe => $composableBuilder(
    column: $table.isDeletedForMe,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isStarred =>
      $composableBuilder(column: $table.isStarred, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MessagesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTableTable,
          MessagesTableData,
          $$MessagesTableTableFilterComposer,
          $$MessagesTableTableOrderingComposer,
          $$MessagesTableTableAnnotationComposer,
          $$MessagesTableTableCreateCompanionBuilder,
          $$MessagesTableTableUpdateCompanionBuilder,
          (
            MessagesTableData,
            BaseReferences<
              _$AppDatabase,
              $MessagesTableTable,
              MessagesTableData
            >,
          ),
          MessagesTableData,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableTableManager(_$AppDatabase db, $MessagesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> encryptedBody = const Value.absent(),
                Value<String> iv = const Value.absent(),
                Value<String?> decryptedBody = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyPreview = const Value.absent(),
                Value<bool> isDeletedForEveryone = const Value.absent(),
                Value<bool> isDeletedForMe = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isStarred = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesTableCompanion(
                localId: localId,
                serverId: serverId,
                conversationId: conversationId,
                senderId: senderId,
                type: type,
                encryptedBody: encryptedBody,
                iv: iv,
                decryptedBody: decryptedBody,
                replyToId: replyToId,
                replyPreview: replyPreview,
                isDeletedForEveryone: isDeletedForEveryone,
                isDeletedForMe: isDeletedForMe,
                isPinned: isPinned,
                isStarred: isStarred,
                expiresAt: expiresAt,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                Value<String?> serverId = const Value.absent(),
                required String conversationId,
                required String senderId,
                required String type,
                required String encryptedBody,
                required String iv,
                Value<String?> decryptedBody = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyPreview = const Value.absent(),
                Value<bool> isDeletedForEveryone = const Value.absent(),
                Value<bool> isDeletedForMe = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isStarred = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MessagesTableCompanion.insert(
                localId: localId,
                serverId: serverId,
                conversationId: conversationId,
                senderId: senderId,
                type: type,
                encryptedBody: encryptedBody,
                iv: iv,
                decryptedBody: decryptedBody,
                replyToId: replyToId,
                replyPreview: replyPreview,
                isDeletedForEveryone: isDeletedForEveryone,
                isDeletedForMe: isDeletedForMe,
                isPinned: isPinned,
                isStarred: isStarred,
                expiresAt: expiresAt,
                status: status,
                createdAt: createdAt,
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

typedef $$MessagesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTableTable,
      MessagesTableData,
      $$MessagesTableTableFilterComposer,
      $$MessagesTableTableOrderingComposer,
      $$MessagesTableTableAnnotationComposer,
      $$MessagesTableTableCreateCompanionBuilder,
      $$MessagesTableTableUpdateCompanionBuilder,
      (
        MessagesTableData,
        BaseReferences<_$AppDatabase, $MessagesTableTable, MessagesTableData>,
      ),
      MessagesTableData,
      PrefetchHooks Function()
    >;
typedef $$MessageReceiptsTableTableCreateCompanionBuilder =
    MessageReceiptsTableCompanion Function({
      required String id,
      required String messageLocalId,
      required String conversationId,
      required String recipientId,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });
typedef $$MessageReceiptsTableTableUpdateCompanionBuilder =
    MessageReceiptsTableCompanion Function({
      Value<String> id,
      Value<String> messageLocalId,
      Value<String> conversationId,
      Value<String> recipientId,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });

class $$MessageReceiptsTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTableTable> {
  $$MessageReceiptsTableTableFilterComposer({
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

  ColumnFilters<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientId => $composableBuilder(
    column: $table.recipientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageReceiptsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTableTable> {
  $$MessageReceiptsTableTableOrderingComposer({
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

  ColumnOrderings<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientId => $composableBuilder(
    column: $table.recipientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageReceiptsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTableTable> {
  $$MessageReceiptsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recipientId => $composableBuilder(
    column: $table.recipientId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);
}

class $$MessageReceiptsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageReceiptsTableTable,
          MessageReceiptsTableData,
          $$MessageReceiptsTableTableFilterComposer,
          $$MessageReceiptsTableTableOrderingComposer,
          $$MessageReceiptsTableTableAnnotationComposer,
          $$MessageReceiptsTableTableCreateCompanionBuilder,
          $$MessageReceiptsTableTableUpdateCompanionBuilder,
          (
            MessageReceiptsTableData,
            BaseReferences<
              _$AppDatabase,
              $MessageReceiptsTableTable,
              MessageReceiptsTableData
            >,
          ),
          MessageReceiptsTableData,
          PrefetchHooks Function()
        > {
  $$MessageReceiptsTableTableTableManager(
    _$AppDatabase db,
    $MessageReceiptsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReceiptsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReceiptsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MessageReceiptsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageLocalId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> recipientId = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsTableCompanion(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                recipientId: recipientId,
                deliveredAt: deliveredAt,
                readAt: readAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageLocalId,
                required String conversationId,
                required String recipientId,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsTableCompanion.insert(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                recipientId: recipientId,
                deliveredAt: deliveredAt,
                readAt: readAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageReceiptsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageReceiptsTableTable,
      MessageReceiptsTableData,
      $$MessageReceiptsTableTableFilterComposer,
      $$MessageReceiptsTableTableOrderingComposer,
      $$MessageReceiptsTableTableAnnotationComposer,
      $$MessageReceiptsTableTableCreateCompanionBuilder,
      $$MessageReceiptsTableTableUpdateCompanionBuilder,
      (
        MessageReceiptsTableData,
        BaseReferences<
          _$AppDatabase,
          $MessageReceiptsTableTable,
          MessageReceiptsTableData
        >,
      ),
      MessageReceiptsTableData,
      PrefetchHooks Function()
    >;
typedef $$MessageMediaTableTableCreateCompanionBuilder =
    MessageMediaTableCompanion Function({
      required String id,
      required String messageLocalId,
      required String conversationId,
      Value<String?> fileUrl,
      Value<String?> localPath,
      required String mediaType,
      required String fileName,
      Value<int> fileSize,
      Value<int?> durationSeconds,
      Value<String?> thumbnailUrl,
      Value<String?> thumbnailLocalPath,
      Value<String> quality,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });
typedef $$MessageMediaTableTableUpdateCompanionBuilder =
    MessageMediaTableCompanion Function({
      Value<String> id,
      Value<String> messageLocalId,
      Value<String> conversationId,
      Value<String?> fileUrl,
      Value<String?> localPath,
      Value<String> mediaType,
      Value<String> fileName,
      Value<int> fileSize,
      Value<int?> durationSeconds,
      Value<String?> thumbnailUrl,
      Value<String?> thumbnailLocalPath,
      Value<String> quality,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });

class $$MessageMediaTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessageMediaTableTable> {
  $$MessageMediaTableTableFilterComposer({
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

  ColumnFilters<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileUrl => $composableBuilder(
    column: $table.fileUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailLocalPath => $composableBuilder(
    column: $table.thumbnailLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageMediaTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageMediaTableTable> {
  $$MessageMediaTableTableOrderingComposer({
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

  ColumnOrderings<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileUrl => $composableBuilder(
    column: $table.fileUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailLocalPath => $composableBuilder(
    column: $table.thumbnailLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageMediaTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageMediaTableTable> {
  $$MessageMediaTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileUrl =>
      $composableBuilder(column: $table.fileUrl, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailLocalPath => $composableBuilder(
    column: $table.thumbnailLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$MessageMediaTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageMediaTableTable,
          MessageMediaTableData,
          $$MessageMediaTableTableFilterComposer,
          $$MessageMediaTableTableOrderingComposer,
          $$MessageMediaTableTableAnnotationComposer,
          $$MessageMediaTableTableCreateCompanionBuilder,
          $$MessageMediaTableTableUpdateCompanionBuilder,
          (
            MessageMediaTableData,
            BaseReferences<
              _$AppDatabase,
              $MessageMediaTableTable,
              MessageMediaTableData
            >,
          ),
          MessageMediaTableData,
          PrefetchHooks Function()
        > {
  $$MessageMediaTableTableTableManager(
    _$AppDatabase db,
    $MessageMediaTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageMediaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageMediaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageMediaTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageLocalId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String?> fileUrl = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> thumbnailLocalPath = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageMediaTableCompanion(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                fileUrl: fileUrl,
                localPath: localPath,
                mediaType: mediaType,
                fileName: fileName,
                fileSize: fileSize,
                durationSeconds: durationSeconds,
                thumbnailUrl: thumbnailUrl,
                thumbnailLocalPath: thumbnailLocalPath,
                quality: quality,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageLocalId,
                required String conversationId,
                Value<String?> fileUrl = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                required String mediaType,
                required String fileName,
                Value<int> fileSize = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> thumbnailLocalPath = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageMediaTableCompanion.insert(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                fileUrl: fileUrl,
                localPath: localPath,
                mediaType: mediaType,
                fileName: fileName,
                fileSize: fileSize,
                durationSeconds: durationSeconds,
                thumbnailUrl: thumbnailUrl,
                thumbnailLocalPath: thumbnailLocalPath,
                quality: quality,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageMediaTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageMediaTableTable,
      MessageMediaTableData,
      $$MessageMediaTableTableFilterComposer,
      $$MessageMediaTableTableOrderingComposer,
      $$MessageMediaTableTableAnnotationComposer,
      $$MessageMediaTableTableCreateCompanionBuilder,
      $$MessageMediaTableTableUpdateCompanionBuilder,
      (
        MessageMediaTableData,
        BaseReferences<
          _$AppDatabase,
          $MessageMediaTableTable,
          MessageMediaTableData
        >,
      ),
      MessageMediaTableData,
      PrefetchHooks Function()
    >;
typedef $$FriendshipsTableTableCreateCompanionBuilder =
    FriendshipsTableCompanion Function({
      required String id,
      required String userAId,
      required String userBId,
      Value<String?> customNickname,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$FriendshipsTableTableUpdateCompanionBuilder =
    FriendshipsTableCompanion Function({
      Value<String> id,
      Value<String> userAId,
      Value<String> userBId,
      Value<String?> customNickname,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$FriendshipsTableTableFilterComposer
    extends Composer<_$AppDatabase, $FriendshipsTableTable> {
  $$FriendshipsTableTableFilterComposer({
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

  ColumnFilters<String> get userAId => $composableBuilder(
    column: $table.userAId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userBId => $composableBuilder(
    column: $table.userBId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customNickname => $composableBuilder(
    column: $table.customNickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FriendshipsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $FriendshipsTableTable> {
  $$FriendshipsTableTableOrderingComposer({
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

  ColumnOrderings<String> get userAId => $composableBuilder(
    column: $table.userAId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userBId => $composableBuilder(
    column: $table.userBId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customNickname => $composableBuilder(
    column: $table.customNickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FriendshipsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $FriendshipsTableTable> {
  $$FriendshipsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userAId =>
      $composableBuilder(column: $table.userAId, builder: (column) => column);

  GeneratedColumn<String> get userBId =>
      $composableBuilder(column: $table.userBId, builder: (column) => column);

  GeneratedColumn<String> get customNickname => $composableBuilder(
    column: $table.customNickname,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FriendshipsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FriendshipsTableTable,
          FriendshipsTableData,
          $$FriendshipsTableTableFilterComposer,
          $$FriendshipsTableTableOrderingComposer,
          $$FriendshipsTableTableAnnotationComposer,
          $$FriendshipsTableTableCreateCompanionBuilder,
          $$FriendshipsTableTableUpdateCompanionBuilder,
          (
            FriendshipsTableData,
            BaseReferences<
              _$AppDatabase,
              $FriendshipsTableTable,
              FriendshipsTableData
            >,
          ),
          FriendshipsTableData,
          PrefetchHooks Function()
        > {
  $$FriendshipsTableTableTableManager(
    _$AppDatabase db,
    $FriendshipsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FriendshipsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FriendshipsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FriendshipsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userAId = const Value.absent(),
                Value<String> userBId = const Value.absent(),
                Value<String?> customNickname = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendshipsTableCompanion(
                id: id,
                userAId: userAId,
                userBId: userBId,
                customNickname: customNickname,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userAId,
                required String userBId,
                Value<String?> customNickname = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FriendshipsTableCompanion.insert(
                id: id,
                userAId: userAId,
                userBId: userBId,
                customNickname: customNickname,
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

typedef $$FriendshipsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FriendshipsTableTable,
      FriendshipsTableData,
      $$FriendshipsTableTableFilterComposer,
      $$FriendshipsTableTableOrderingComposer,
      $$FriendshipsTableTableAnnotationComposer,
      $$FriendshipsTableTableCreateCompanionBuilder,
      $$FriendshipsTableTableUpdateCompanionBuilder,
      (
        FriendshipsTableData,
        BaseReferences<
          _$AppDatabase,
          $FriendshipsTableTable,
          FriendshipsTableData
        >,
      ),
      FriendshipsTableData,
      PrefetchHooks Function()
    >;
typedef $$FriendRequestsTableTableCreateCompanionBuilder =
    FriendRequestsTableCompanion Function({
      required String id,
      required String fromUserId,
      required String toUserId,
      Value<String> status,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$FriendRequestsTableTableUpdateCompanionBuilder =
    FriendRequestsTableCompanion Function({
      Value<String> id,
      Value<String> fromUserId,
      Value<String> toUserId,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$FriendRequestsTableTableFilterComposer
    extends Composer<_$AppDatabase, $FriendRequestsTableTable> {
  $$FriendRequestsTableTableFilterComposer({
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

  ColumnFilters<String> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toUserId => $composableBuilder(
    column: $table.toUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FriendRequestsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $FriendRequestsTableTable> {
  $$FriendRequestsTableTableOrderingComposer({
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

  ColumnOrderings<String> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toUserId => $composableBuilder(
    column: $table.toUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FriendRequestsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $FriendRequestsTableTable> {
  $$FriendRequestsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toUserId =>
      $composableBuilder(column: $table.toUserId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FriendRequestsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FriendRequestsTableTable,
          FriendRequestsTableData,
          $$FriendRequestsTableTableFilterComposer,
          $$FriendRequestsTableTableOrderingComposer,
          $$FriendRequestsTableTableAnnotationComposer,
          $$FriendRequestsTableTableCreateCompanionBuilder,
          $$FriendRequestsTableTableUpdateCompanionBuilder,
          (
            FriendRequestsTableData,
            BaseReferences<
              _$AppDatabase,
              $FriendRequestsTableTable,
              FriendRequestsTableData
            >,
          ),
          FriendRequestsTableData,
          PrefetchHooks Function()
        > {
  $$FriendRequestsTableTableTableManager(
    _$AppDatabase db,
    $FriendRequestsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FriendRequestsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FriendRequestsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FriendRequestsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromUserId = const Value.absent(),
                Value<String> toUserId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendRequestsTableCompanion(
                id: id,
                fromUserId: fromUserId,
                toUserId: toUserId,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromUserId,
                required String toUserId,
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FriendRequestsTableCompanion.insert(
                id: id,
                fromUserId: fromUserId,
                toUserId: toUserId,
                status: status,
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

typedef $$FriendRequestsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FriendRequestsTableTable,
      FriendRequestsTableData,
      $$FriendRequestsTableTableFilterComposer,
      $$FriendRequestsTableTableOrderingComposer,
      $$FriendRequestsTableTableAnnotationComposer,
      $$FriendRequestsTableTableCreateCompanionBuilder,
      $$FriendRequestsTableTableUpdateCompanionBuilder,
      (
        FriendRequestsTableData,
        BaseReferences<
          _$AppDatabase,
          $FriendRequestsTableTable,
          FriendRequestsTableData
        >,
      ),
      FriendRequestsTableData,
      PrefetchHooks Function()
    >;
typedef $$ReactionsTableTableCreateCompanionBuilder =
    ReactionsTableCompanion Function({
      required String id,
      required String messageLocalId,
      required String conversationId,
      required String userId,
      required String emoji,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ReactionsTableTableUpdateCompanionBuilder =
    ReactionsTableCompanion Function({
      Value<String> id,
      Value<String> messageLocalId,
      Value<String> conversationId,
      Value<String> userId,
      Value<String> emoji,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ReactionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ReactionsTableTable> {
  $$ReactionsTableTableFilterComposer({
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

  ColumnFilters<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReactionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ReactionsTableTable> {
  $$ReactionsTableTableOrderingComposer({
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

  ColumnOrderings<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReactionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReactionsTableTable> {
  $$ReactionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageLocalId => $composableBuilder(
    column: $table.messageLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ReactionsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReactionsTableTable,
          ReactionsTableData,
          $$ReactionsTableTableFilterComposer,
          $$ReactionsTableTableOrderingComposer,
          $$ReactionsTableTableAnnotationComposer,
          $$ReactionsTableTableCreateCompanionBuilder,
          $$ReactionsTableTableUpdateCompanionBuilder,
          (
            ReactionsTableData,
            BaseReferences<
              _$AppDatabase,
              $ReactionsTableTable,
              ReactionsTableData
            >,
          ),
          ReactionsTableData,
          PrefetchHooks Function()
        > {
  $$ReactionsTableTableTableManager(
    _$AppDatabase db,
    $ReactionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReactionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReactionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReactionsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> messageLocalId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReactionsTableCompanion(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                userId: userId,
                emoji: emoji,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String messageLocalId,
                required String conversationId,
                required String userId,
                required String emoji,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReactionsTableCompanion.insert(
                id: id,
                messageLocalId: messageLocalId,
                conversationId: conversationId,
                userId: userId,
                emoji: emoji,
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

typedef $$ReactionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReactionsTableTable,
      ReactionsTableData,
      $$ReactionsTableTableFilterComposer,
      $$ReactionsTableTableOrderingComposer,
      $$ReactionsTableTableAnnotationComposer,
      $$ReactionsTableTableCreateCompanionBuilder,
      $$ReactionsTableTableUpdateCompanionBuilder,
      (
        ReactionsTableData,
        BaseReferences<_$AppDatabase, $ReactionsTableTable, ReactionsTableData>,
      ),
      ReactionsTableData,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableTableCreateCompanionBuilder =
    AppSettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableTableUpdateCompanionBuilder =
    AppSettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableFilterComposer({
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

class $$AppSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableOrderingComposer({
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

class $$AppSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableAnnotationComposer({
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

class $$AppSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData,
          $$AppSettingsTableTableFilterComposer,
          $$AppSettingsTableTableOrderingComposer,
          $$AppSettingsTableTableAnnotationComposer,
          $$AppSettingsTableTableCreateCompanionBuilder,
          $$AppSettingsTableTableUpdateCompanionBuilder,
          (
            AppSettingsTableData,
            BaseReferences<
              _$AppDatabase,
              $AppSettingsTableTable,
              AppSettingsTableData
            >,
          ),
          AppSettingsTableData,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableTableManager(
    _$AppDatabase db,
    $AppSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsTableCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsTableCompanion.insert(
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

typedef $$AppSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTableTable,
      AppSettingsTableData,
      $$AppSettingsTableTableFilterComposer,
      $$AppSettingsTableTableOrderingComposer,
      $$AppSettingsTableTableAnnotationComposer,
      $$AppSettingsTableTableCreateCompanionBuilder,
      $$AppSettingsTableTableUpdateCompanionBuilder,
      (
        AppSettingsTableData,
        BaseReferences<
          _$AppDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData
        >,
      ),
      AppSettingsTableData,
      PrefetchHooks Function()
    >;
typedef $$MessageDraftsTableTableCreateCompanionBuilder =
    MessageDraftsTableCompanion Function({
      required String conversationId,
      required String draftText,
      Value<String?> replyToLocalId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$MessageDraftsTableTableUpdateCompanionBuilder =
    MessageDraftsTableCompanion Function({
      Value<String> conversationId,
      Value<String> draftText,
      Value<String?> replyToLocalId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MessageDraftsTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessageDraftsTableTable> {
  $$MessageDraftsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draftText => $composableBuilder(
    column: $table.draftText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToLocalId => $composableBuilder(
    column: $table.replyToLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageDraftsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageDraftsTableTable> {
  $$MessageDraftsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draftText => $composableBuilder(
    column: $table.draftText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToLocalId => $composableBuilder(
    column: $table.replyToLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageDraftsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageDraftsTableTable> {
  $$MessageDraftsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get draftText =>
      $composableBuilder(column: $table.draftText, builder: (column) => column);

  GeneratedColumn<String> get replyToLocalId => $composableBuilder(
    column: $table.replyToLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MessageDraftsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageDraftsTableTable,
          MessageDraftsTableData,
          $$MessageDraftsTableTableFilterComposer,
          $$MessageDraftsTableTableOrderingComposer,
          $$MessageDraftsTableTableAnnotationComposer,
          $$MessageDraftsTableTableCreateCompanionBuilder,
          $$MessageDraftsTableTableUpdateCompanionBuilder,
          (
            MessageDraftsTableData,
            BaseReferences<
              _$AppDatabase,
              $MessageDraftsTableTable,
              MessageDraftsTableData
            >,
          ),
          MessageDraftsTableData,
          PrefetchHooks Function()
        > {
  $$MessageDraftsTableTableTableManager(
    _$AppDatabase db,
    $MessageDraftsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageDraftsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageDraftsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageDraftsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> draftText = const Value.absent(),
                Value<String?> replyToLocalId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageDraftsTableCompanion(
                conversationId: conversationId,
                draftText: draftText,
                replyToLocalId: replyToLocalId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String draftText,
                Value<String?> replyToLocalId = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MessageDraftsTableCompanion.insert(
                conversationId: conversationId,
                draftText: draftText,
                replyToLocalId: replyToLocalId,
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

typedef $$MessageDraftsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageDraftsTableTable,
      MessageDraftsTableData,
      $$MessageDraftsTableTableFilterComposer,
      $$MessageDraftsTableTableOrderingComposer,
      $$MessageDraftsTableTableAnnotationComposer,
      $$MessageDraftsTableTableCreateCompanionBuilder,
      $$MessageDraftsTableTableUpdateCompanionBuilder,
      (
        MessageDraftsTableData,
        BaseReferences<
          _$AppDatabase,
          $MessageDraftsTableTable,
          MessageDraftsTableData
        >,
      ),
      MessageDraftsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db, _db.usersTable);
  $$ConversationsTableTableTableManager get conversationsTable =>
      $$ConversationsTableTableTableManager(_db, _db.conversationsTable);
  $$ConversationMembersTableTableTableManager get conversationMembersTable =>
      $$ConversationMembersTableTableTableManager(
        _db,
        _db.conversationMembersTable,
      );
  $$MessagesTableTableTableManager get messagesTable =>
      $$MessagesTableTableTableManager(_db, _db.messagesTable);
  $$MessageReceiptsTableTableTableManager get messageReceiptsTable =>
      $$MessageReceiptsTableTableTableManager(_db, _db.messageReceiptsTable);
  $$MessageMediaTableTableTableManager get messageMediaTable =>
      $$MessageMediaTableTableTableManager(_db, _db.messageMediaTable);
  $$FriendshipsTableTableTableManager get friendshipsTable =>
      $$FriendshipsTableTableTableManager(_db, _db.friendshipsTable);
  $$FriendRequestsTableTableTableManager get friendRequestsTable =>
      $$FriendRequestsTableTableTableManager(_db, _db.friendRequestsTable);
  $$ReactionsTableTableTableManager get reactionsTable =>
      $$ReactionsTableTableTableManager(_db, _db.reactionsTable);
  $$AppSettingsTableTableTableManager get appSettingsTable =>
      $$AppSettingsTableTableTableManager(_db, _db.appSettingsTable);
  $$MessageDraftsTableTableTableManager get messageDraftsTable =>
      $$MessageDraftsTableTableTableManager(_db, _db.messageDraftsTable);
}
