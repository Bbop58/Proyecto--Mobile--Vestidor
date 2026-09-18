import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/branch.dart';
import '../../services/branch_service.dart';

class BranchesPublicScreen extends StatefulWidget {
  const BranchesPublicScreen({super.key});

  @override
  State<BranchesPublicScreen> createState() => _BranchesPublicScreenState();
}

class _BranchesPublicScreenState extends State<BranchesPublicScreen> {
  List<Branch> _branches = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final service = context.read<BranchService>();
      final list = await service.getBranches(activaOnly: false);
      if (mounted) {
        setState(() {
          _branches = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar sucursales: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    // Agrupar por ciudad
    final Map<String, List<Branch>> byCiudad = {};
    for (final b in _branches) {
      final city = b.ciudad ?? 'Sin ciudad';
      byCiudad.putIfAbsent(city, () => []).add(b);
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border)),
        title: Text(
          'Nuestras Tiendas',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textSecondary),
            onPressed: _loadBranches,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                        const SizedBox(height: 12),
                        Text(_errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textSecondary)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadBranches,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _branches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store_outlined, size: 64, color: textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text('Sin tiendas disponibles',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: accent,
                      onRefresh: _loadBranches,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Header con total
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                              border: Border.all(color: accent.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.store_rounded, color: accent, size: 28),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_branches.where((b) => b.activa).length} tiendas activas',
                                      style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                                    ),
                                    Text(
                                      'en ${byCiudad.length} ${byCiudad.length == 1 ? "ciudad" : "ciudades"}',
                                      style: TextStyle(fontSize: 12, color: textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Sucursales por ciudad
                          ...byCiudad.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_city_rounded, size: 16, color: accent),
                                      const SizedBox(width: 6),
                                      Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: textPrimary,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...entry.value.map((branch) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                                          border: Border.all(color: border),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.03),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: branch.activa
                                                    ? AppTheme.successBg
                                                    : AppTheme.errorBg,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.storefront_rounded,
                                                color: branch.activa
                                                    ? AppTheme.successColor
                                                    : AppTheme.errorColor,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          branch.nombre,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w700,
                                                            color: textPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: branch.activa
                                                              ? AppTheme.successBg
                                                              : AppTheme.errorBg,
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(
                                                            color: branch.activa
                                                                ? AppTheme.successColor.withValues(alpha: 0.3)
                                                                : AppTheme.errorColor.withValues(alpha: 0.3),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          branch.activa ? 'Abierta' : 'Cerrada',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w700,
                                                            color: branch.activa
                                                                ? AppTheme.successColor
                                                                : AppTheme.errorColor,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.place_outlined,
                                                          size: 13, color: textSecondary),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          branch.direccion,
                                                          style: TextStyle(
                                                              fontSize: 12, color: textSecondary),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (branch.telefono != null) ...[
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Icon(Icons.phone_outlined,
                                                            size: 13, color: textSecondary),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          branch.telefono!,
                                                          style: TextStyle(
                                                              fontSize: 12, color: textSecondary),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )),
                                const SizedBox(height: 4),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
    );
  }
}
