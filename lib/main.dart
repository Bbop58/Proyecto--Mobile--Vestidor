import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/shop/cart_screen.dart';
import 'screens/shop/catalog_screen.dart';
import 'screens/reservations/reservations_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/branch_service.dart';
import 'services/cart_service.dart';
import 'services/category_service.dart';
import 'services/product_service.dart';
import 'services/reservation_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(
          create: (_) => StorageService(),
        ),
        ChangeNotifierProvider<ThemeService>(
          create: (context) => ThemeService(context.read<StorageService>()),
        ),
        ProxyProvider<StorageService, ApiService>(
          update: (_, storage, _) => ApiService(storage),
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
        ChangeNotifierProvider<CartService>(
          create: (_) => CartService(),
        ),
      ],
      child: Consumer2<AuthService, ThemeService>(
        builder: (context, auth, themeService, _) {
          return MaterialApp(
            title: 'FICCT STORE Mobile',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            home: const AuthWrapper(),
            routes: {
              AppRoutes.login: (context) => const LoginScreen(),
              AppRoutes.register: (context) => const RegisterScreen(),
              AppRoutes.home: (context) => const MainNavigationScreen(),
              AppRoutes.catalog: (context) => const CatalogScreen(),
              AppRoutes.cart: (context) => const CartScreen(),
              AppRoutes.reservations: (context) => const ReservationsScreen(),
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

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
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
                    'Cargando FICCT STORE...',
                    style: TextStyle(color: AppTheme.getTextSecondary(context)),
                  ),
                ],
              ),
            ),
          );
        }

        if (auth.isAuthenticated) {
          return const MainNavigationScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
