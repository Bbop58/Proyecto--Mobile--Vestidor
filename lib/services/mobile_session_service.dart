import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/mobile_session.dart';
import 'storage_service.dart';

/// One owner for durable identity, renewal, and pending revocations. No HTTP in constructor.
class MobileSessionService extends ChangeNotifier {
  final StorageService storage;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  MobileSessionService(
    this.storage, {
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;
  SessionEnvelope _envelope = const SessionEnvelope();
  MobileSessionRecord? _restrictionPending;
  bool _loaded = false,
      _hadDocument = false,
      _blocked = false,
      _disposed = false;
  bool _logoutNeedsRetry = false, _legacyPending = false;
  int _generation = 0, _refreshGeneration = -1;
  Future<void> _mutations = Future.value();
  Future<void>? _loading, _restoring, _refreshing, _revoking;
  SessionState _state = SessionState.signedOut;
  String? _notice;
  bool _platformDenied = false;
  bool get platformDenied => _platformDenied;
  void dismissPlatformAccess() {
    _platformDenied = false;
    notifyListeners();
  }

  SessionState get state => _state;
  String? get notice => _notice;
  int get generation => _generation;
  bool get logoutNeedsRetry => _logoutNeedsRetry;
  bool get awaitingLegacyConnection => _legacyPending;
  bool get hasIdentity =>
      !_blocked &&
      _envelope.active != null &&
      [
        SessionState.online,
        SessionState.offline,
        SessionState.restricted,
      ].contains(_state);
  SessionIdentity? get identity =>
      hasIdentity ? _envelope.active!.identity : null;
  Map<String, dynamic>? get profile =>
      hasIdentity ? _envelope.active!.profile : null;
  String? get currentAccessToken =>
      hasIdentity ? _envelope.active!.accessToken : null;

  void _status(SessionState next, [String? message]) {
    if (_disposed) return;
    _state = next;
    _notice = message;
    notifyListeners();
  }

  bool _current(int attempt) => !_disposed && attempt == _generation;
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    _mutations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _load() => _loading ??= _read();
  Future<void> _read() async {
    if (_loaded) return;
    final stored = await storage.readSessionEnvelope();
    _hadDocument = stored != null;
    _envelope = stored ?? const SessionEnvelope();
    _loaded = true;
  }

  Future<void> _save(SessionEnvelope next) async {
    await storage.writeSessionEnvelope(next);
    _envelope = next;
    _hadDocument = true;
  }

  List<PendingRevocation> _pending(Iterable<PendingRevocation> extra) {
    final result = [..._envelope.pendingRevocations];
    for (final row in extra) {
      if (!result.any((v) => v.same(row))) result.add(row);
    }
    return List.unmodifiable(result);
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body, {
    String? access,
  }) async {
    http.Response response;
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..followRedirects = false;
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (access != null) 'Authorization': 'Bearer $access',
      });
      request.body = jsonEncode(body);
      response = await http.Response.fromStream(await _client.send(request))
          .timeout(ApiConfig.connectionTimeout);
    } catch (_) {
      throw const SessionFailure(
        0,
        'NETWORK',
        'Sin conexión con el servidor. Tu sesión se conserva.',
      );
    }
    Map<String, dynamic>? data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      /* No raw body in diagnostics. */
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data != null) {
      return data;
    }
    final detail = data?['detail'];
    final code = detail is Map && detail['code'] is String
        ? detail['code'] as String
        : response.statusCode == 403 &&
              detail == 'La plataforma no tiene sesión móvil comercial'
        ? 'PLATFORM_ONLY'
        : 'HTTP_${response.statusCode}';
    final message = switch (code) {
      'MOBILE_SESSION_INVALID' ||
      'MOBILE_SESSION_REVOKED' ||
      'MOBILE_IDENTITY_CHANGED' =>
        'Tu sesión dejó de ser válida. Vuelve a ingresar.',
      'MOBILE_ACCOUNT_INACTIVE' =>
        'La cuenta está desactivada. Vuelve a ingresar cuando se habilite.',
      'MOBILE_SERVICE_RESTRICTED' => 'La empresa tiene el acceso restringido.',
      'PLATFORM_ONLY' => 'Esta cuenta se gestiona en la web de FashionStore.',
      _ => 'No se pudo verificar la sesión. Reintenta sin borrar tus datos.',
    };
    throw SessionFailure(response.statusCode, code, message);
  }

  int beginAuthentication() {
    if (_logoutNeedsRetry) throw const SessionStorageException();
    final attempt = ++_generation;
    _blocked = true;
    _platformDenied = false;
    _status(SessionState.restoring);
    return attempt;
  }

  void cancelAuthentication(int attempt) {
    if (!_current(attempt)) return;
    _blocked = false;
    _status(
      _envelope.active == null ? SessionState.signedOut : SessionState.offline,
    );
  }

  Future<void> restore({bool retry = false}) {
    if (_logoutNeedsRetry) return signOut();
    if (_restoring != null) return _restoring!;
    if (_loaded && !retry) return Future.value();
    if (retry) {
      _loading = null;
      _loaded = false;
    }
    final future = _restore(_generation);
    _restoring = future;
    return future.whenComplete(() => _restoring = null);
  }

  Future<void> _restore(int attempt) async {
    _status(SessionState.restoring);
    try {
      if (_restrictionPending != null) {
        await _exclusive(() async {
          if (!_current(attempt)) return;
          await _save(
            SessionEnvelope(
              active: _restrictionPending,
              pendingRevocations: _envelope.pendingRevocations,
            ),
          );
          _restrictionPending = null;
        });
      }
      await _load();
      if (!_current(attempt)) return;
      _blocked = false;
      if (_envelope.active != null) {
        _status(SessionState.offline);
        await _refresh(attempt);
      } else if (!_hadDocument) {
        final legacy = await storage.readLegacySession();
        if (!_current(attempt)) return;
        if (legacy != null) {
          await _migrate(legacy, attempt);
        } else {
          _status(SessionState.signedOut);
        }
      } else {
        _status(SessionState.signedOut);
      }
      if (_current(attempt) && _envelope.pendingRevocations.isNotEmpty) {
        unawaited(flushPendingRevocations());
      }
    } on SessionStorageException {
      if (_current(attempt)) {
        _status(
          SessionState.storageError,
          const SessionStorageException().toString(),
        );
      }
    } on SessionFailure catch (error) {
      if (!_current(attempt)) return;
      if (_state != SessionState.reauthRequired &&
          _state != SessionState.restricted) {
        _status(SessionState.offline, error.message);
      }
    } catch (_) {
      if (_current(attempt)) {
        _status(
          SessionState.storageError,
          const SessionStorageException().toString(),
        );
      }
    }
  }

  Future<void> _migrate(Map<String, String> legacy, int attempt) async {
    _legacyPending = true;
    var access = legacy['access_token'];
    var refresh = legacy['refresh_token'];
    try {
      final claims = accessClaims(access);
      final expiry = claims?['exp'];
      if (access == null ||
          expiry is! num ||
          expiry <= _now().millisecondsSinceEpoch / 1000) {
        if (refresh == null) {
          throw const SessionFailure(
            401,
            'LEGACY_EXPIRED',
            'Vuelve a iniciar sesión para actualizarla.',
          );
        }
        final data = await _post(ApiConfig.refreshUrl, {
          'refresh_token': refresh,
        });
        access = data['access_token'] as String;
        refresh = data['refresh_token'] as String;
      }
      if (!_current(attempt)) {
        await _queue(PendingRevocation.legacy(access, refresh));
        return;
      }
      await bootstrap(
        legacyAccessToken: access,
        legacyRefreshToken: refresh,
        attempt: attempt,
      );
      _legacyPending = false;
    } on SessionFailure catch (error) {
      if (_current(attempt) &&
          (error.statusCode == 401 || error.code == 'PLATFORM_ONLY')) {
        if (access != null) {
          await _queue(PendingRevocation.legacy(access, refresh));
        }
        await _invalidate(attempt, error.message);
        _legacyPending = false;
        _platformDenied = error.code == 'PLATFORM_ONLY';
      }
      rethrow;
    }
  }

  Future<void> bootstrap({
    required String legacyAccessToken,
    String? legacyRefreshToken,
    int? attempt,
  }) async {
    final epoch = attempt ?? beginAuthentication();
    if (!_current(epoch)) return;
    final data = await _post(
      ApiConfig.mobileSessionUrl,
      {},
      access: legacyAccessToken,
    );
    MobileSessionRecord record;
    try {
      record = MobileSessionRecord.fromJson(data);
    } catch (_) {
      throw const SessionFailure(
        502,
        'INVALID_SESSION',
        'El servidor no devolvió una sesión móvil coherente.',
      );
    }
    await _establish(
      record,
      epoch,
      legacy: PendingRevocation.legacy(legacyAccessToken, legacyRefreshToken),
    );
  }

  Future<void> establish(Map<String, dynamic> response) async {
    final record = MobileSessionRecord.fromJson(response);
    await _establish(record, beginAuthentication());
  }

  Future<void> _establish(
    MobileSessionRecord record,
    int attempt, {
    PendingRevocation? legacy,
  }) async {
    try {
      await _exclusive(() async {
        await _load();
        if (!_current(attempt)) {
          await _save(
            SessionEnvelope(
              active: _envelope.active,
              pendingRevocations: _pending([
                PendingRevocation.mobile(record.sessionToken),
                if (legacy != null) legacy,
              ]),
            ),
          );
          return;
        }
        final previous = _envelope.active;
        await _save(
          SessionEnvelope(
            active: record,
            pendingRevocations: _pending([
              if (previous != null &&
                  previous.sessionToken != record.sessionToken)
                PendingRevocation.mobile(previous.sessionToken),
              if (legacy != null) legacy,
            ]),
          ),
        );
        if (!_current(attempt)) return;
        _restrictionPending = null;
        _blocked = false;
        _legacyPending = false;
        _status(
          record.profile['service_restricted'] == true
              ? SessionState.restricted
              : SessionState.online,
        );
      });
      // A saved envelope is authoritative even if deleting old keys fails.
      if (_current(attempt)) {
        try {
          await storage.clearLegacySession();
        } on SessionStorageException {
          /* Keep the saved document. */
        }
      }
    } on SessionStorageException {
      if (_current(attempt)) {
        _status(
          SessionState.storageError,
          const SessionStorageException().toString(),
        );
      }
      rethrow;
    }
  }

  Future<void> _refresh(int attempt) {
    if (_refreshing != null && _refreshGeneration == attempt) {
      return _refreshing!;
    }
    _refreshGeneration = attempt;
    final future = _doRefresh(attempt);
    _refreshing = future;
    return future.whenComplete(() {
      if (_refreshGeneration == attempt) _refreshing = null;
    });
  }

  Future<void> _doRefresh(int attempt) async {
    try {
      await _renew(attempt);
    } on SessionStorageException {
      if (_current(attempt)) {
        _blocked = true;
        _status(
          SessionState.storageError,
          const SessionStorageException().toString(),
        );
      }
      rethrow;
    }
  }

  Future<void> _renew(int attempt) async {
    final record = _envelope.active;
    if (record == null || !_current(attempt) || _blocked) return;
    try {
      final data = await _post(ApiConfig.mobileRefreshUrl, {
        'session_token': record.sessionToken,
      });
      if (!_current(attempt) || _blocked) return;
      MobileSessionRecord next;
      try {
        next = record.renewed(data);
      } catch (_) {
        throw const SessionFailure(
          502,
          'INVALID_SESSION',
          'La respuesta no corresponde a tu sesión. Reintenta.',
        );
      }
      await _exclusive(() async {
        if (!_current(attempt) || _blocked) return;
        await _save(
          SessionEnvelope(
            active: next,
            pendingRevocations: _envelope.pendingRevocations,
          ),
        );
        if (_current(attempt) && !_blocked) {
          _status(
            next.profile['service_restricted'] == true
                ? SessionState.restricted
                : SessionState.online,
          );
        }
      });
    } on SessionStorageException {
      if (_current(attempt)) {
        _status(
          SessionState.storageError,
          const SessionStorageException().toString(),
        );
      }
      rethrow;
    } on SessionFailure catch (error) {
      if (!_current(attempt)) return;
      if ([
        'MOBILE_SESSION_INVALID',
        'MOBILE_SESSION_REVOKED',
        'MOBILE_IDENTITY_CHANGED',
        'MOBILE_ACCOUNT_INACTIVE',
      ].contains(error.code)) {
        await _invalidate(attempt, error.message);
      } else if (error.code == 'MOBILE_SERVICE_RESTRICTED') {
        await _exclusive(() async {
          if (!_current(attempt) || _blocked) return;
          final current = _envelope.active!;
          final capabilities = Map<String, dynamic>.from(
            current.profile['subscription_capabilities'] as Map,
          );
          final restricted = MobileSessionRecord(
            sessionId: current.sessionId,
            sessionToken: current.sessionToken,
            accessToken: current.accessToken,
            profile: {
              ...current.profile,
              'service_restricted': true,
              'subscription_capabilities': capabilities.map(
                (k, v) => MapEntry(k, false),
              ),
            },
          );
          _restrictionPending = restricted;
          await _save(
            SessionEnvelope(
              active: restricted,
              pendingRevocations: _envelope.pendingRevocations,
            ),
          );
          _restrictionPending = null;
          if (_current(attempt) && !_blocked) {
            _status(SessionState.restricted, error.message);
          }
        });
      } else {
        _status(SessionState.offline, error.message);
      }
      rethrow;
    }
  }

  /// Revalidate the durable owner after resume/reconnection, even with a valid JWT.
  Future<bool> revalidate() async {
    if (!_loaded || _state == SessionState.restoring) {
      await restore();
    } else if (hasIdentity) {
      try { await _refresh(_generation); }
      on SessionFailure { return false; }
      on SessionStorageException { return false; }
    }
    return hasIdentity && _state == SessionState.online;
  }

  Future<String?> accessToken({
    bool forceRefresh = false,
    String? rejectedAccessToken,
  }) async {
    if (!_loaded) await restore();
    if (_state == SessionState.storageError) {
      throw const SessionStorageException();
    }
    if (!hasIdentity) return null;
    final token = currentAccessToken, expiry = accessClaims(token)?['exp'];
    final alreadyRenewed =
        forceRefresh &&
        rejectedAccessToken != null &&
        token != rejectedAccessToken;
    if (_state == SessionState.offline ||
        (!alreadyRenewed && forceRefresh) ||
        expiry is! num ||
        expiry <= _now().millisecondsSinceEpoch / 1000 + 30) {
      await _refresh(_generation);
    }
    return hasIdentity ? currentAccessToken : null;
  }

  Future<void> updateProfile(Map<String, dynamic> profile) async {
    final attempt = _generation;
    await _exclusive(() async {
      final record = _envelope.active;
      if (record == null || !_current(attempt) || _blocked) return;
      final next = record.renewed({
        'session_id': record.sessionId,
        'access_token': record.accessToken,
        'user': profile,
      });
      await _save(
        SessionEnvelope(
          active: next,
          pendingRevocations: _envelope.pendingRevocations,
        ),
      );
      if (_current(attempt)) {
        _status(
          next.profile['service_restricted'] == true
              ? SessionState.restricted
              : _state,
        );
      }
    });
  }

  Future<void> _invalidate(int attempt, String message) async {
    _blocked = true;
    _logoutNeedsRetry = true;
    await _exclusive(() async {
      if (!_current(attempt)) return;
      final active = _envelope.active;
      await _save(
        SessionEnvelope(
          pendingRevocations: _pending([
            if (active != null) PendingRevocation.mobile(active.sessionToken),
          ]),
        ),
      );
      if (_current(attempt)) {
        _logoutNeedsRetry = false;
        _status(SessionState.reauthRequired, message);
      }
    });
  }

  Future<void> _queue(PendingRevocation item) => _exclusive(() async {
    await _load();
    await _save(
      SessionEnvelope(
        active: _envelope.active,
        pendingRevocations: _pending([item]),
      ),
    );
  });

  Future<void> signOut() async {
    if (_logoutNeedsRetry && !_loaded) _loading = null;
    final attempt = ++_generation;
    _blocked = true;
    _legacyPending = false;
    _status(SessionState.signedOut);
    try {
      await _exclusive(() async {
        await _load();
        final legacy = _hadDocument ? null : await storage.readLegacySession();
        final active = _envelope.active;
        await _save(
          SessionEnvelope(
            pendingRevocations: _pending([
              if (active != null) PendingRevocation.mobile(active.sessionToken),
              if (legacy?['access_token'] != null)
                PendingRevocation.legacy(
                  legacy!['access_token']!,
                  legacy['refresh_token'],
                ),
            ]),
          ),
        );
        if (_current(attempt)) {
          _logoutNeedsRetry = false;
          _restrictionPending = null;
          _status(SessionState.signedOut);
        }
      });
      try {
        await storage.clearLegacySession();
      } on SessionStorageException {
        /* Tombstone already durable. */
      }
      unawaited(flushPendingRevocations());
    } on SessionStorageException {
      if (_current(attempt)) {
        _logoutNeedsRetry = true;
        _status(
          SessionState.storageError,
          'No se pudo guardar el cierre de sesión. Reintenta antes de cerrar la app.',
        );
      }
      rethrow;
    }
  }

  Future<void> flushPendingRevocations() {
    if (_revoking != null) return _revoking!;
    final future = _flush();
    _revoking = future;
    return future.whenComplete(() => _revoking = null);
  }

  Future<void> _flush() async {
    try {
      await _load();
      for (final pending in [..._envelope.pendingRevocations]) {
        try {
          await _post(
            pending.kind == 'mobile'
                ? ApiConfig.mobileLogoutUrl
                : ApiConfig.logoutUrl,
            pending.kind == 'mobile'
                ? {'session_token': pending.credential}
                : {'refresh_token': pending.refreshToken},
            access: pending.kind == 'legacy' ? pending.credential : null,
          );
        } on SessionFailure catch (error) {
          if (pending.kind != 'legacy' || error.statusCode != 401) continue;
          // Legacy logout requires a valid access JWT. Never renew a signed-out identity.
        }
        await _exclusive(() async {
          await _save(
            SessionEnvelope(
              active: _envelope.active,
              pendingRevocations: List.unmodifiable(
                _envelope.pendingRevocations.where((v) => !v.same(pending)),
              ),
            ),
          );
        });
      }
    } catch (_) {
      /* Keep pending revocations durable; retry at next explicit opportunity. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
