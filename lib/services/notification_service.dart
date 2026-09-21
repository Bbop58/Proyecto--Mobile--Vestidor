import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/notification_model.dart';
import 'api_service.dart';

class NotificationService extends ChangeNotifier {
  final ApiService _api;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  NotificationService(this._api);

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  /// Obtener listado completo de notificaciones
  Future<void> fetchNotifications() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _api.getAuth(ApiConfig.notificationsUrl);
      if (response.success && response.data is List) {
        _notifications = (response.data as List)
            .map((item) => NotificationModel.fromJson(item as Map<String, dynamic>))
            .toList();

        _unreadCount = _notifications.where((n) => !n.isRead).length;
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Consultar solo el conteo de no leídas para la campanita
  Future<void> fetchUnreadCount() async {
    try {
      final response = await _api.getAuth(ApiConfig.unreadNotificationsCountUrl);
      if (response.success && response.data is Map<String, dynamic>) {
        _unreadCount = (response.data['unread_count'] as num?)?.toInt() ?? 0;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
    }
  }

  /// Marcar una notificación individual como leída
  Future<bool> markAsRead(String notificationId) async {
    try {
      final response = await _api.patchAuth(
        ApiConfig.markNotificationReadUrl(notificationId),
      );

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
    try {
      final response = await _api.postAuth(ApiConfig.markAllNotificationsReadUrl);
      if (response.success) {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
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
