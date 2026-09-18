import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Guía de tallas interactiva basada en medidas corporales
/// RF13 — Vestidor Virtual (implementación sin IA, basada en tabla de conversión)
class VirtualFittingScreen extends StatefulWidget {
  const VirtualFittingScreen({super.key});

  @override
  State<VirtualFittingScreen> createState() => _VirtualFittingScreenState();
}

class _VirtualFittingScreenState extends State<VirtualFittingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _alturaCtrl = TextEditingController();
  final _pesoCtrl = TextEditingController();
  final _pechoCtrl = TextEditingController();
  final _cinturaCtrl = TextEditingController();
  final _caderaCtrl = TextEditingController();

  Map<String, String>? _resultados;
  bool _calculated = false;

  @override
  void dispose() {
    _alturaCtrl.dispose();
    _pesoCtrl.dispose();
    _pechoCtrl.dispose();
    _cinturaCtrl.dispose();
    _caderaCtrl.dispose();
    super.dispose();
  }

  // ── Tabla de conversión para tops (poleras, camisas, sudaderas) ────────────
  String _calcTopSize(double pecho) {
    if (pecho < 84) return 'XS';
    if (pecho < 90) return 'S';
    if (pecho < 96) return 'M';
    if (pecho < 102) return 'L';
    if (pecho < 110) return 'XL';
    return 'XXL';
  }

  // ── Tabla de conversión para pantalones ───────────────────────────────────
  String _calcPantsSize(double cintura) {
    if (cintura < 68) return '26 / 27';
    if (cintura < 73) return '28 / 29';
    if (cintura < 78) return '30 / 31';
    if (cintura < 83) return '32 / 33';
    if (cintura < 90) return '34 / 35';
    if (cintura < 98) return '36 / 38';
    return '40+';
  }

  // ── Talla de calzado aproximada por altura ────────────────────────────────
  String _calcShoeSize(double altura) {
    if (altura < 155) return '35 – 36';
    if (altura < 162) return '37 – 38';
    if (altura < 170) return '38 – 39';
    if (altura < 178) return '40 – 41';
    if (altura < 185) return '42 – 43';
    return '44 – 45';
  }

  // ── IMC para contexto ─────────────────────────────────────────────────────
  String _calcIMC(double peso, double altura) {
    final imc = peso / ((altura / 100) * (altura / 100));
    if (imc < 18.5) return 'Delgado';
    if (imc < 25.0) return 'Normal';
    if (imc < 30.0) return 'Sobrepeso';
    return 'Obesidad leve';
  }

  void _calcular() {
    if (!_formKey.currentState!.validate()) return;

    final altura = double.parse(_alturaCtrl.text);
    final peso = double.parse(_pesoCtrl.text);
    final pecho = double.parse(_pechoCtrl.text);
    final cintura = double.parse(_cinturaCtrl.text);

    setState(() {
      _resultados = {
        'top': _calcTopSize(pecho),
        'pants': _calcPantsSize(cintura),
        'shoes': _calcShoeSize(altura),
        'imc': _calcIMC(peso, altura),
      };
      _calculated = true;
    });
  }

  void _resetear() {
    setState(() {
      _resultados = null;
      _calculated = false;
      _alturaCtrl.clear();
      _pesoCtrl.clear();
      _pechoCtrl.clear();
      _cinturaCtrl.clear();
      _caderaCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.getBg(context);
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vestidor Virtual',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary)),
            Text('Guía de tallas personalizada',
                style: TextStyle(fontSize: 11, color: textSecondary)),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner informativo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.12),
                    accent.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.straighten_rounded, color: accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Encuentra tu talla perfecta',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Ingresa tus medidas y te recomendaremos la talla ideal para cada tipo de prenda.',
                          style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Formulario de medidas
            Form(
              key: _formKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tus medidas',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _alturaCtrl,
                            label: 'Altura (cm)',
                            hint: 'Ej: 170',
                            icon: Icons.height_rounded,
                            context: context,
                            min: 120,
                            max: 220,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _pesoCtrl,
                            label: 'Peso (kg)',
                            hint: 'Ej: 65',
                            icon: Icons.monitor_weight_outlined,
                            context: context,
                            min: 30,
                            max: 200,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _pechoCtrl,
                            label: 'Contorno pecho (cm)',
                            hint: 'Ej: 92',
                            icon: Icons.accessibility_new_rounded,
                            context: context,
                            min: 60,
                            max: 150,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _cinturaCtrl,
                            label: 'Contorno cintura (cm)',
                            hint: 'Ej: 78',
                            icon: Icons.tune_rounded,
                            context: context,
                            min: 50,
                            max: 140,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _calcular,
                        icon: const Icon(Icons.checkroom_rounded, size: 18),
                        label: const Text(
                          'Calcular mis tallas',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Resultados
            if (_calculated && _resultados != null) ...[
              const SizedBox(height: 20),
              Text(
                'Tu guía de tallas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildResultCard(
                    context,
                    icon: Icons.dry_cleaning_rounded,
                    label: 'Poleras / Camisas\nSudaderas',
                    talla: _resultados!['top']!,
                  ),
                  _buildResultCard(
                    context,
                    icon: Icons.airline_seat_legroom_reduced_rounded,
                    label: 'Pantalones\nJeans / Shorts',
                    talla: _resultados!['pants']!,
                  ),
                  _buildResultCard(
                    context,
                    icon: Icons.directions_run_rounded,
                    label: 'Calzado\nZapatillas / Botines',
                    talla: _resultados!['shoes']!,
                  ),
                  _buildResultCard(
                    context,
                    icon: Icons.person_rounded,
                    label: 'Contexto corporal',
                    talla: _resultados!['imc']!,
                    isInfo: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Nota informativa
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.warningColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Los resultados son orientativos. Las tallas pueden variar según el fabricante o el tipo de corte de cada prenda.',
                        style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _resetear,
                  icon: Icon(Icons.refresh_rounded, size: 16, color: textSecondary),
                  label: Text('Recalcular con otras medidas',
                      style: TextStyle(color: textSecondary, fontSize: 13)),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required BuildContext context,
    required double min,
    required double max,
  }) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final border = AppTheme.getBorder(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            border: Border.all(color: border),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: Icon(icon, size: 18, color: textSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              final n = double.tryParse(v.trim());
              if (n == null) return 'Número inválido';
              if (n < min || n > max) return '${min.toInt()}-${max.toInt()}';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String talla,
    bool isInfo = false,
  }) {
    final cardBg = AppTheme.getCardBg(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final accent = AppTheme.getAccent(context);
    final border = AppTheme.getBorder(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isInfo ? cardBg : accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
        border: Border.all(
            color: isInfo ? border : accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: isInfo ? textSecondary : accent),
          const Spacer(),
          Text(
            talla,
            style: TextStyle(
              fontSize: isInfo ? 16 : 22,
              fontWeight: FontWeight.w800,
              color: isInfo ? textPrimary : accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: textSecondary, height: 1.3),
          ),
        ],
      ),
    );
  }
}
