import 'dart:convert';

enum SessionState {
  signedOut,
  restoring,
  online,
  offline,
  restricted,
  reauthRequired,
  storageError,
}

class SessionStorageException implements Exception {
  const SessionStorageException();
  @override
  String toString() =>
      'No se pudo leer o guardar la sesión de forma segura. Reintenta.';
}

class SessionFailure implements Exception {
  final int statusCode;
  final String code;
  final String message;
  const SessionFailure(this.statusCode, this.code, this.message);
  @override
  String toString() => message;
}

class SessionIdentity {
  final String sessionId, tenantId, userId;
  const SessionIdentity(this.sessionId, this.tenantId, this.userId);
  String get scope => '$tenantId:$userId';
  bool same(SessionIdentity other) =>
      sessionId == other.sessionId && scope == other.scope;
}

Map<String, dynamic>? accessClaims(String? token) {
  try {
    if (token == null || token.split('.').length != 3) return null;
    return Map<String, dynamic>.from(
      jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      ) as Map,
    );
  } catch (_) {
    return null;
  }
}

final _sessionId = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _credential = RegExp(r'^ms_[a-f0-9]{32}\.[A-Za-z0-9_-]{43}$');
bool _text(dynamic value) => value is String && value.trim().isNotEmpty;

Map<String, dynamic> sessionProfile(Map<String, dynamic> value) {
  if (!_text(value['id']) ||
      !_text(value['tenant_id']) ||
      value['access_scope'] != 'COMPANY' ||
      value['is_platform_admin'] == true ||
      value['is_active'] != true) {
    throw const FormatException('Invalid mobile identity');
  }
  final capabilities = value['subscription_capabilities'];
  final permissions = value['permissions'];
  if (permissions != null &&
      (permissions is! List ||
          permissions.any((permission) => permission is! String || permission.trim().isEmpty))) {
    throw const FormatException('Invalid mobile permissions');
  }
  if (capabilities != null &&
      (capabilities is! Map || capabilities.values.any((v) => v is! bool))) {
    throw const FormatException('Invalid mobile capabilities');
  }
  return Map.unmodifiable({
    'id': value['id'],
    'tenant_id': value['tenant_id'],
    'access_scope': 'COMPANY',
    'is_platform_admin': false,
    'is_active': true,
    'full_name': value['full_name'] is String ? value['full_name'] : '',
    'email': value['email'] is String ? value['email'] : '',
    'created_at': value['created_at'] is String ? value['created_at'] : '',
    'is_verified': value['is_verified'] == true,
    'service_restricted': value['service_restricted'] == true,
    'subscription_capabilities': Map<String, bool>.unmodifiable(
      Map<String, dynamic>.from(capabilities as Map? ?? {})
          .map((k, v) => MapEntry(k, v == true)),
    ),
    'permissions': List<String>.unmodifiable(
      (permissions as List? ?? const []).cast<String>(),
    ),
  });
}

class MobileSessionRecord {
  final String sessionId, sessionToken;
  final String? accessToken;
  final Map<String, dynamic> profile;
  MobileSessionRecord({
    required this.sessionId,
    required this.sessionToken,
    required this.accessToken,
    required Map<String, dynamic> profile,
  }) : profile = sessionProfile(profile) {
    if (!_sessionId.hasMatch(sessionId) ||
        !_credential.hasMatch(sessionToken) ||
        !sessionToken.startsWith('ms_${sessionId.replaceAll('-', '')}.')) {
      throw const FormatException('Invalid mobile credential');
    }
    if (accessToken != null) {
      final claims = accessClaims(accessToken);
      if (claims == null ||
          claims['type'] != 'access' ||
          claims['sub'] != profile['id'] ||
          claims['tenant_id'] != profile['tenant_id'] ||
          claims['mobile_session_id'] != sessionId ||
          claims['exp'] is! num) {
        throw const FormatException('Inconsistent access identity');
      }
    }
  }
  SessionIdentity get identity => SessionIdentity(
    sessionId,
    profile['tenant_id'] as String,
    profile['id'] as String,
  );
  factory MobileSessionRecord.fromJson(Map<String, dynamic> json) =>
      MobileSessionRecord(
        sessionId: json['session_id'] as String,
        sessionToken: json['session_token'] as String,
        accessToken: json['access_token'] as String?,
        profile: Map<String, dynamic>.from(json['user'] as Map),
      );
  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'session_token': sessionToken,
    'access_token': accessToken,
    'user': profile,
  };
  MobileSessionRecord renewed(Map<String, dynamic> response) {
    if (response['session_id'] != sessionId) {
      throw const FormatException('Session changed');
    }
    final next = MobileSessionRecord(
      sessionId: sessionId,
      sessionToken: sessionToken,
      accessToken: response['access_token'] as String,
      profile: Map<String, dynamic>.from(response['user'] as Map),
    );
    if (!identity.same(next.identity)) {
      throw const FormatException('Owner changed');
    }
    return next;
  }
}

class PendingRevocation {
  final String kind, credential;
  final String? refreshToken;
  const PendingRevocation.mobile(this.credential)
    : kind = 'mobile',
      refreshToken = null;
  const PendingRevocation.legacy(this.credential, this.refreshToken)
    : kind = 'legacy';
  factory PendingRevocation.fromJson(Map<String, dynamic> value) {
    final credential = value['credential'];
    if (!_text(credential)) throw const FormatException('Missing revocation');
    if (value['kind'] == 'mobile' &&
        _credential.hasMatch(credential as String)) {
      return PendingRevocation.mobile(credential);
    }
    if (value['kind'] == 'legacy' &&
        (value['refresh_token'] == null || _text(value['refresh_token']))) {
      return PendingRevocation.legacy(
        credential as String,
        value['refresh_token'] as String?,
      );
    }
    throw const FormatException('Invalid revocation');
  }
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'credential': credential,
    if (refreshToken != null) 'refresh_token': refreshToken,
  };
  bool same(PendingRevocation other) =>
      kind == other.kind && credential == other.credential;
}

class SessionEnvelope {
  final MobileSessionRecord? active;
  final List<PendingRevocation> pendingRevocations;
  const SessionEnvelope({this.active, this.pendingRevocations = const []});
  factory SessionEnvelope.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1 || value['pending_revocations'] is! List) {
      throw const FormatException('Invalid session version');
    }
    return SessionEnvelope(
      active: value['active'] == null
          ? null
          : MobileSessionRecord.fromJson(
              Map<String, dynamic>.from(value['active'] as Map),
            ),
      pendingRevocations: List.unmodifiable(
        (value['pending_revocations'] as List).map(
          (v) =>
              PendingRevocation.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'active': active?.toJson(),
    'pending_revocations': pendingRevocations.map((r) => r.toJson()).toList(),
  };
}
