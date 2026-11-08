import 'dart:async';

import '../../models/mobile_session.dart';
import '../../services/api_service.dart';
import 'connectivity_service.dart';

/// Explicit app lifecycle owner; no network work in its constructor.
class SessionLifecycleService {
  final ApiService api;
  final ConnectivityService connection;
  final Future<void> Function() onReady;
  Future<void>? _running;
  int? _handledGeneration;
  bool _disposed = false, _started = false;
  SessionLifecycleService(this.api, this.connection, {required this.onReady});

  void start() {
    if (_started || _disposed) return;
    _started = true;
    connection.addListener(_onConnection);
    api.sessionCoordinator?.addListener(_onSession);
    _onSession();
  }

  void _onConnection() {
    if (connection.isOnline) unawaited(resume());
  }

  void _onSession() {
    final session = api.sessionCoordinator;
    if (session?.hasIdentity != true) {
      _handledGeneration = null;
      return;
    }
    if (session!.state != SessionState.online) {
      _handledGeneration = null;
      return;
    }
    if (session.state == SessionState.online &&
        session.generation != _handledGeneration &&
        _running == null) {
      unawaited(resume(revalidate: false));
    }
  }

  Future<void> resume({bool revalidate = true}) {
    if (_disposed || !connection.isOnline) return Future.value();
    if (_running != null) return _running!;
    final session = api.sessionCoordinator;
    final owner = session?.identity?.scope;
    if (session == null || owner == null) {
      return session?.flushPendingRevocations() ?? Future.value();
    }
    final generation = session.generation;
    final task = () async {
      if (!await api.prepareSession(
        expectedScope: owner,
        revalidate: revalidate,
      )) {
        return;
      }
      if (_disposed || session.generation != generation) return;
      _handledGeneration = generation;
      await session.flushPendingRevocations();
      if (_disposed || session.generation != generation) return;
      await onReady();
    }();
    final settled = task
        .catchError((Object _) {
          // Individual services expose errors and retain their durable queues.
        })
        .whenComplete(() {
          _running = null;
          if (!_disposed) _onSession();
        });
    _running = settled;
    return settled;
  }

  void dispose() {
    _disposed = true;
    connection.removeListener(_onConnection);
    api.sessionCoordinator?.removeListener(_onSession);
  }
}
