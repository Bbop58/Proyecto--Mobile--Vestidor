import 'dart:async';
import 'package:flutter/material.dart';

import 'screens/auth/platform_access_screen.dart';

import 'package:provider/provider.dart';

import 'config/routes.dart';
import 'config/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/branches_public_screen.dart';
import 'screens/home/purchase_history_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/shop/cart_screen.dart';
import 'screens/shop/catalog_screen.dart';
import 'screens/shop/virtual_fitting_screen.dart';
import 'screens/reservations/reservations_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/mobile_session_service.dart';
import 'services/branch_service.dart';
import 'services/cart_service.dart';
import 'services/category_service.dart';
import 'services/inventory_service.dart';
import 'services/product_service.dart';
import 'services/reservation_service.dart';
import 'services/sale_service.dart';
import 'services/season_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'services/paypal_service.dart';
import 'services/notification_service.dart';
import 'services/local_notification_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/session_lifecycle_service.dart';
import 'core/services/offline_authorization_service.dart';
import 'core/database/database_helper.dart';
import 'screens/offline/offline_sync_screen.dart';
import 'services/chatbot_service.dart';
import 'services/tts_service.dart';
import 'screens/chatbot/chatbot_screen.dart';
import 'services/wallet_service.dart';
import 'screens/wallet/wallet_screen.dart';
import 'services/favorite_service.dart';
import 'screens/shop/favorites_screen.dart';
import 'screens/sales/cash_sale_screen.dart';
import 'screens/notifications/notifications_screen.dart';

final appNavigationKey=GlobalKey<NavigatorState>();
void openPushNotifications(){
  WidgetsBinding.instance.addPostFrameCallback((_){
    if(DatabaseHelper.scope!=null)appNavigationKey.currentState?.pushNamed(AppRoutes.notifications);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
  // Native permission prompts must not hold the first frame hostage.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    LocalNotificationService.initialize().catchError((Object error) {
      debugPrint('No se pudieron iniciar las notificaciones: $error');
    });
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(create: (_) => StorageService()),
        ChangeNotifierProvider<MobileSessionService>(
          create: (context) =>
              MobileSessionService(context.read<StorageService>()),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => ConnectivityService(),
        ),
        ChangeNotifierProvider<ThemeService>(
          create: (context) => ThemeService(context.read<StorageService>()),
        ),
        ProxyProvider2<StorageService, MobileSessionService, ApiService>(
          update: (_, storage, sessions, previous) =>
              previous ?? ApiService(storage, sessions: sessions),
          dispose: (_, api) => api.dispose(),
        ),
        ChangeNotifierProxyProvider2<ApiService, StorageService, AuthService>(
          create: (context) => AuthService(
            context.read<ApiService>(),
            context.read<StorageService>(),
          ),
          update: (_, api, storage, auth) {
            if (auth != null) return auth;
            return AuthService(api, storage);
          },
        ),
        ChangeNotifierProxyProvider3<
          ApiService,
          ConnectivityService,
          StorageService,
          WalletService
        >(
          create: (context) => WalletService(
            context.read<ApiService>(),
            context.read<ConnectivityService>(),
            context.read<StorageService>(),
          ),
          update: (_, api, conn, storage, wallet) {
            if (wallet != null) return wallet;
            return WalletService(api, conn, storage);
          },
        ),
        ChangeNotifierProxyProvider2<
          ApiService,
          ConnectivityService,
          OfflineSyncService
        >(
          create: (context) => OfflineSyncService(
            context.read<ApiService>(),
            context.read<ConnectivityService>(),
            walletService: context.read<WalletService>(),
          ),
          update: (context, api, conn, sync) {
            if (sync != null) return sync;
            return OfflineSyncService(
              api,
              conn,
              walletService: context.read<WalletService>(),
            );
          },
        ),
        ProxyProvider<ApiService, CategoryService>(
          update: (_, api, _) => CategoryService(api),
        ),
        ProxyProvider<ApiService, BranchService>(
          update: (_, api, _) => BranchService(api),
        ),
        ProxyProvider<ApiService, ProductService>(
          update: (_, api, _) => ProductService(api),
        ),
        ProxyProvider<ApiService, ReservationService>(
          update: (_, api, _) => ReservationService(api),
        ),
        ProxyProvider<ApiService, SeasonService>(
          update: (_, api, _) => SeasonService(api),
        ),
        ProxyProvider<ApiService, InventoryService>(
          update: (_, api, _) => InventoryService(api),
        ),
        ProxyProvider<ApiService, SaleService>(
          update: (_, api, _) => SaleService(api),
        ),
        ProxyProvider<ApiService, PayPalService>(
          update: (_, api, _) => PayPalService(api),
        ),
        ChangeNotifierProxyProvider<ApiService, NotificationService>(
          create: (context) => NotificationService(context.read<ApiService>(),onPushOpened:openPushNotifications),
          update: (_, api, notif) {
            if (notif != null) return notif;
            return NotificationService(api,onPushOpened:openPushNotifications);
          },
        ),
        ChangeNotifierProvider<CartService>(create: (_) => CartService()),
        ChangeNotifierProvider<TtsService>(create: (_) => TtsService()),
        ChangeNotifierProxyProvider<ApiService, ChatbotService>(
          create: (context) => ChatbotService(context.read<ApiService>()),
          update: (_, api, chatbot) {
            if (chatbot != null) return chatbot;
            return ChatbotService(api);
          },
        ),
        ChangeNotifierProxyProvider3<
          ApiService,
          ConnectivityService,
          StorageService,
          FavoriteService
        >(
          create: (context) => FavoriteService(
            context.read<ApiService>(),
            context.read<ConnectivityService>(),
            context.read<StorageService>(),
          ),
          update: (_, api, conn, storage, favService) {
            if (favService != null) return favService;
            return FavoriteService(api, conn, storage);
          },
        ),
      ],
      child: Consumer2<AuthService, ThemeService>(
        builder: (context, auth, themeService, _) {
          return MaterialApp(
            navigatorKey:appNavigationKey,
            title: 'ficcstore',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            home: const AuthWrapper(),
            routes: {
              AppRoutes.login: (context) => const AuthWrapper(),
              AppRoutes.register: (context) => const RegisterScreen(),
              AppRoutes.home: (context) => const AuthWrapper(),
              AppRoutes.catalog: (context) => const CatalogScreen(),
              AppRoutes.cart: (context) => const CartScreen(),
              AppRoutes.reservations: (context) => const ReservationsScreen(),
              AppRoutes.purchases: (context) => const PurchaseHistoryScreen(),
              AppRoutes.branches: (context) => const BranchesPublicScreen(),
              AppRoutes.virtualFitting: (context) =>
                  const VirtualFittingScreen(),
              AppRoutes.offlineSync: (context) => const OfflineSyncScreen(),
              AppRoutes.chatbot: (context) => const ChatbotScreen(),
              AppRoutes.wallet: (context) => const WalletScreen(),
              AppRoutes.favorites: (context) => const FavoritesScreen(),
              AppRoutes.cashSale: (context) => const CashSaleScreen(),
              AppRoutes.notifications: (context) => const NotificationsScreen(),
            },
          );
        },
      ),
    );
  }
}

/// Widget envoltorio para determinar la pantalla inicial según estado de auth
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  SessionLifecycleService? _lifecycle;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_lifecycle?.resume() ?? Future.value());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        final api = context.read<ApiService>();
        _lifecycle = SessionLifecycleService(api,context.read<ConnectivityService>(),onReady:() async {
          final sync = context.read<OfflineSyncService>();
          final wallet = context.read<WalletService>();
          final favorites = context.read<FavoriteService>();
          final owner = DatabaseHelper.scope;
          final generation = api.sessionCoordinator?.generation;
          bool current() => mounted && owner == DatabaseHelper.scope && generation == api.sessionCoordinator?.generation;
          await sync.syncBatchNow();
          if (!current()) return;
          await wallet.fetchWallet(silent:true);
          if (!current()) return;
          await OfflineAuthorizationService(api).prefetch('SYNC');
          if (!current()) return;
          await favorites.fetchFavorites();
        });
        WidgetsBinding.instance.addObserver(this);
        _lifecycle!.start();
        context.read<AuthService>().initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (auth.isLoading && !auth.isAuthenticated) {
          return Scaffold(
            backgroundColor: AppTheme.getBg(context),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.getAccent(context)),
                  const SizedBox(height: 20),
                  Text(
                    'Cargando ficcstore...',
                    style: TextStyle(color: AppTheme.getTextSecondary(context)),
                  ),
                ],
              ),
            ),
          );
        }

        if (auth.platformOnly) {
          return const PlatformAccessScreen();
        }
        if (auth.sessionRecoveryNeeded) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock_outlined, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        auth.sessionRecoveryMessage,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: auth.isLoading
                            ? null
                            : () => auth.retrySession(),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (auth.isAuthenticated && auth.currentUser?.canUseMobile == true) {
          return const MainNavigationScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
