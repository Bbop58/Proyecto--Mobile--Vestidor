import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import 'branches_public_screen.dart';
import 'purchase_history_screen.dart';
import '../shop/virtual_fitting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.getCardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
        ),
        title: Text(
          'Cerrar Sesión',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Text(
          '¿Estás seguro de que deseas salir de tu cuenta?',
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthService>().logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final isDark = themeService.isDarkMode;
    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Consumer<AuthService>(
            builder: (context, auth, _) {
              final user = auth.currentUser;
              if (user == null) {
                return Center(
                  child: CircularProgressIndicator(color: accent),
                );
              }

              return CustomScrollView(
                slivers: [
                  // App Bar / Topbar idéntico a Web
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cardBg,
                        border: Border(
                          bottom: BorderSide(color: border),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.borderRadiusSmall,
                                ),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  height: 34,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'FICCT STORE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Dark mode toggle button
                              IconButton(
                                icon: Icon(
                                  isDark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                  color: accent,
                                  size: 22,
                                ),
                                tooltip: isDark
                                    ? 'Cambiar a modo claro'
                                    : 'Cambiar a modo oscuro',
                                onPressed: () => themeService.toggleTheme(),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(
                                  Icons.logout_rounded,
                                  color: textSecondary,
                                  size: 22,
                                ),
                                tooltip: 'Cerrar Sesión',
                                onPressed: _handleLogout,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 20)),

                  // Welcome Banner con borde izquierdo Amber (Igual a Web)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(
                            AppTheme.borderRadiusLarge,
                          ),
                          border: Border(
                            left: BorderSide(color: accent, width: 4),
                            top: BorderSide(color: border),
                            right: BorderSide(color: border),
                            bottom: BorderSide(color: border),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? const Color(0x40000000)
                                  : const Color(0x12000000),
                              blurRadius: isDark ? 10 : 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 52,
                              height: 52,
                              decoration: AppTheme.logoBadgeDecorationOf(context),
                              child: Center(
                                child: Text(
                                  user.fullName.isNotEmpty
                                      ? user.fullName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hola, ${user.fullName}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    user.email,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: user.isActive
                                          ? AppTheme.successBg
                                          : AppTheme.errorBg,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.borderRadiusSmall,
                                      ),
                                      border: Border.all(
                                        color: user.isActive
                                            ? AppTheme.successColor.withValues(alpha: 0.3)
                                            : AppTheme.errorColor.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: user.isActive
                                                ? AppTheme.successColor
                                                : AppTheme.errorColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          user.isActive
                                              ? 'Cuenta Activa'
                                              : 'Cuenta Inactiva',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: user.isActive
                                                ? AppTheme.successColor
                                                : AppTheme.errorColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Info Cards
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              context: context,
                              icon: Icons.tag_rounded,
                              label: 'ID de Usuario',
                              value: '#${user.id.length > 8 ? user.id.substring(0, 8) : user.id}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              context: context,
                              icon: Icons.calendar_today_outlined,
                              label: 'Fecha Registro',
                              value: _formatDate(user.createdAt),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Action items
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: AppTheme.cardDecorationOf(context),
                        child: Column(
                          children: [
                            _buildActionTile(
                              context: context,
                              icon: Icons.receipt_long_rounded,
                              label: 'Mis Compras',
                              subtitle: 'Historial de compras digitales',
                              color: AppTheme.successColor,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PurchaseHistoryScreen(),
                                ),
                              ),
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: Icons.store_rounded,
                              label: 'Nuestras Tiendas',
                              subtitle: 'Sucursales y disponibilidad por ciudad',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BranchesPublicScreen(),
                                ),
                              ),
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: Icons.accessibility_new_rounded,
                              label: 'Vestidor Virtual & Guía de Tallas',
                              subtitle: 'Calcula tu talla exacta según tus medidas',
                              color: accent,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VirtualFittingScreen(),
                                ),
                              ),
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: Icons.edit_outlined,
                              label: 'Editar Perfil',
                              subtitle: 'Actualiza tu nombre y correo',
                              onTap: () => _showEditProfile(context, auth),
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: isDark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              label: isDark ? 'Modo Claro' : 'Modo Oscuro',
                              subtitle: isDark
                                  ? 'Cambiar a interfaz clara'
                                  : 'Cambiar a interfaz oscura',
                              color: accent,
                              onTap: () => themeService.toggleTheme(),
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: Icons.security_outlined,
                              label: 'Seguridad y Permisos',
                              subtitle: 'Sesión activa mediante JWT Seguro',
                              onTap: () {},
                            ),
                            Divider(height: 1, indent: 56, color: border),
                            _buildActionTile(
                              context: context,
                              icon: Icons.logout_rounded,
                              label: 'Cerrar Sesión',
                              subtitle: 'Finalizar sesión en este dispositivo',
                              color: AppTheme.errorColor,
                              onTap: _handleLogout,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final accent = AppTheme.getAccent(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);

    return Container(
      decoration: AppTheme.cardDecorationOf(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: AppTheme.logoBadgeDecorationOf(context),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final accent = AppTheme.getAccent(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final textMuted = AppTheme.getTextMuted(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (color ?? accent).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
        ),
        child: Icon(icon, color: color ?? accent, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color ?? textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: textMuted,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  void _showEditProfile(BuildContext context, AuthService authService) {
    final user = authService.currentUser!;
    final nameCtrl = TextEditingController(text: user.fullName);
    final emailCtrl = TextEditingController(text: user.email);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: border),
            left: BorderSide(color: border),
            right: BorderSide(color: border),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Editar Perfil',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: nameCtrl,
              style: TextStyle(color: textPrimary),
              decoration: AppTheme.inputDecorationOf(
                context,
                icon: Icons.person_outline_rounded,
                hint: 'Nombre completo',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: emailCtrl,
              style: TextStyle(color: textPrimary),
              decoration: AppTheme.inputDecorationOf(
                context,
                icon: Icons.mail_outline_rounded,
                hint: 'Correo electrónico',
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: () async {
                  final success = await authService.updateProfile(
                    fullName: nameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                  );
                  if (success && context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Text('Perfil actualizado correctamente'),
                          ],
                        ),
                        backgroundColor: AppTheme.successColor,
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.borderRadiusMedium,
                          ),
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppTheme.borderRadiusMedium,
                    ),
                  ),
                ),
                child: const Text(
                  'Guardar Cambios',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = [
        'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
