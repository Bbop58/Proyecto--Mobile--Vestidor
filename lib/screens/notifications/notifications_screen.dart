import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/notification_service.dart';


class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationService>().fetchNotifications();
    });
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Hace un momento';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} h';
    } else if (difference.inDays == 1) {
      return 'Ayer';
    } else if (difference.inDays < 7) {
      return 'Hace ${difference.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  IconData _getIconForType(String type) {
    switch (type.toUpperCase()) {
      case 'RESERVATION_READY':
        return Icons.inventory_2_rounded;
      case 'PURCHASE_SUCCESS':
        return Icons.receipt_long_rounded;
      case 'RESERVATION_EXPIRING':
        return Icons.access_time_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColorForType(String type, BuildContext context) {
    final accent = AppTheme.getAccent(context);
    switch (type.toUpperCase()) {
      case 'RESERVATION_READY':
        return const Color(0xFF10B981); // Emerald
      case 'PURCHASE_SUCCESS':
        return const Color(0xFF3B82F6); // Blue
      case 'RESERVATION_EXPIRING':
        return const Color(0xFFF59E0B); // Amber
      default:
        return accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);
    final accent = AppTheme.getAccent(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'Notificaciones',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Consumer<NotificationService>(
            builder: (context, notifService, _) {
              if (notifService.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  await notifService.markAllAsRead();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Todas las notificaciones marcadas como leídas'),
                        backgroundColor: AppTheme.successColor,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Text(
                  'Leer todas',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationService>(
        builder: (context, notifService, _) {
          if (notifService.isLoading && notifService.notifications.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }

          final notifications = notifService.notifications;

          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 40,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No tienes notificaciones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Te avisaremos aquí cuando tu reserva esté lista para recoger o confirmes una compra digital.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: accent,
            onRefresh: () => notifService.fetchNotifications(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notif = notifications[index];
                final iconColor = _getColorForType(notif.type, context);
                final icon = _getIconForType(notif.type);

                return InkWell(
                  onTap: () {
                    if (!notif.isRead) {
                      notifService.markAsRead(notif.id);
                    }
                  },
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: notif.isRead
                          ? cardBg
                          : accent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      border: Border.all(
                        color: notif.isRead
                            ? border
                            : accent.withValues(alpha: 0.35),
                        width: notif.isRead ? 1 : 1.5,
                      ),
                      boxShadow: notif.isRead
                          ? null
                          : [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icono temático
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: iconColor, size: 22),
                        ),
                        const SizedBox(width: 14),

                        // Contenido
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      notif.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (!notif.isRead) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                notif.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatTime(notif.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: textSecondary.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
