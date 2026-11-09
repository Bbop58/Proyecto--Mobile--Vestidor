import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static Future<void>? _initializing;

  /// Inicializa el plugin de notificaciones locales para Android, iOS y Web/Desktop
  static Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    return _initializing ??= _initializePlugin().whenComplete(() {
      _initializing = null;
    });
  }

  static Future<void> _initializePlugin() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notificación interactuada: ${response.payload}');
      },
    );

    // Prepare the channel without prompting on startup. Firebase requests the
    // Android permission only after the explicit "Activar avisos" action.
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel('ficct_store_channel','Notificaciones FashionStore',
            description:'Avisos de compras y reservas',importance:Importance.high),
        );
      }
    } catch (e) {
      debugPrint('Error solicitando permisos de notificación: $e');
    }

    _isInitialized = true;
  }

  /// Muestra una notificación emergente en la barra de estado con vibración y sonido
  static Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'ficct_store_channel',
            'Notificaciones FICCT STORE',
            channelDescription: 'Canal oficial para avisos de compras, reservas y novedades de catálogo',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            playSound: true,
            enableVibration: true,
          );

      const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error mostrando notificación local: $e');
    }
  }
}
