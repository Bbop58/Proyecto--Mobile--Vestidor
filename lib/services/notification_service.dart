import 'package:flutter/foundation.dart';

import '../core/database/database_helper.dart';
import '../config/api_config.dart';
import '../models/notification_model.dart';
import 'api_service.dart';
import 'local_notification_service.dart';

class NotificationService extends ChangeNotifier {
  final ApiService _api;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _errorMessage;
  final Set<String> _knownNotificationIds = {};
  bool _isFirstFetch = true;

  bool _disposed = false;
  NotificationService(this._api) {
    DatabaseHelper.scopeChanges.addListener(_reset);
  }
  void _reset() {
    _notifications = [];
    _unreadCount = 0;
    _knownNotificationIds.clear();
    _isFirstFetch = true;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  bool _current(String? owner) => !_disposed && owner == DatabaseHelper.scope;
  @override
  void dispose() {
    _disposed = true;
    DatabaseHelper.scopeChanges.removeListener(_reset);
    super.dispose();
  }

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Obtener listado completo de notificaciones y disparar notificación local si hay nuevas
  Future<void> fetchNotifications() async {
    final owner = DatabaseHelper.scope;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.getAuth(ApiConfig.notificationsUrl);
      if (!_current(owner)) return;
      if (response.success && response.data is List) {
        _notifications = (response.data as List)
            .map(
              (item) =>
                  NotificationModel.fromJson(item as Map<String, dynamic>),
            )
            .toList();

        _unreadCount = _notifications.where((n) => !n.isRead).length;

        // Disparar notificación nativa en Android/iOS para cada nueva notificación
        for (final n in _notifications) {
          if (!_isFirstFetch &&
              !n.isRead &&
              !_knownNotificationIds.contains(n.id)) {
            LocalNotificationService.showNotification(
              id: n.id.hashCode,
              title: n.title,
              body: n.message,
              payload: n.referenceId,
            );
          }
          _knownNotificationIds.add(n.id);
        }
        _isFirstFetch = false;
      } else {
        _errorMessage =
            response.error ?? 'No se pudieron cargar las notificaciones';
      }
    } catch (e) {
      if (_current(owner)) {
        _errorMessage = 'No se pudieron cargar las notificaciones. Reintenta.';
      }
      debugPrint('Error fetching notifications: $e');
    } finally {
      if (_current(owner)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Consultar solo el conteo de no leídas para la campanita
  Future<void> fetchUnreadCount() async {
    final owner = DatabaseHelper.scope;
    try {
      final response = await _api.getAuth(
        ApiConfig.unreadNotificationsCountUrl,
      );
      if (!_current(owner)) return;
      if (response.success && response.data is Map<String, dynamic>) {
        final newCount = (response.data['unread_count'] as num?)?.toInt() ?? 0;
        if (newCount > _unreadCount) {
          // Hay nuevas notificaciones no leídas, sincronizar listado para disparar alerta local
          _unreadCount = newCount;
          notifyListeners();
          fetchNotifications();
        } else {
          _unreadCount = newCount;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
    }
  }

  /// Marcar una notificación individual como leída
  Future<bool> markAsRead(String notificationId) async {
    final owner = DatabaseHelper.scope;
    try {
      final response = await _api.patchAuth(
        ApiConfig.markNotificationReadUrl(notificationId),
      );

      if (!_current(owner)) return false;
      if (response.success) {
        final index = _notifications.indexWhere((n) => n.id == notificationId);
        if (index != -1 && !_notifications[index].isRead) {
          _notifications[index] = _notifications[index].copyWith(isRead: true);
          if (_unreadCount > 0) _unreadCount--;
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      return false;
    }
  }

  /// Marcar todas las notificaciones como leídas
  Future<bool> markAllAsRead() async {
    final owner = DatabaseHelper.scope;
    try {
      final response = await _api.postAuth(
        ApiConfig.markAllNotificationsReadUrl,
      );
      if (!_current(owner)) return false;
      if (response.success) {
        _notifications = _notifications
            .map((n) => n.copyWith(isRead: true))
            .toList();
        _unreadCount = 0;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
      return false;
    }
  }
}
