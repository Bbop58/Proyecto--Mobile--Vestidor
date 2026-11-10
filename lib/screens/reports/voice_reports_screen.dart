import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/voice_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/speech_recognition_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_report_export_service.dart';
import '../../services/voice_report_service.dart';

class VoiceReportsScreen extends StatefulWidget {
  const VoiceReportsScreen({super.key});
  @override
  State<VoiceReportsScreen> createState() => _VoiceReportsScreenState();
}

class _VoiceReportsScreenState extends State<VoiceReportsScreen> {
  final _question = TextEditingController();
  final _speech = SpeechRecognitionService();
  TtsService? _tts;
  VoiceReport? _report;
  String? _reportOwner;
  String? _reportTenant;
  String? _error;
  bool _busy = false, _exporting = false, _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tts = context.read<TtsService>();
  }

  @override
  void dispose() {
    _speech.dispose();
    _tts?.stop();
    _question.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    if (mounted) {
      setState(
        () => _error = error is FormatException
            ? error.message
            : 'No se pudo completar la operación. Reintenta.',
      );
    }
  }

  Future<void> _toggleMic() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      await _speech.listen((text) {
        if (!mounted) return;
        _question.text = text;
        _question.selection = TextSelection.collapsed(offset: text.length);
      }, onListening: (active) {
        if (mounted) setState(() => _listening = active);
      });
      if (mounted) {
        setState(() {
          _listening = true;
          _error = null;
        });
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _query() async {
    if (_busy) return;
    final auth = context.read<AuthService>();
    final owner = auth.currentUser?.id;
    final tenant = auth.currentUser?.tenantId;
    if (auth.currentUser?.canViewVoiceReports != true) return;
    await _speech.stop();
    _tts?.stop();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _listening = false;
      _error = null;
      _report = null;
      _reportOwner = null;
      _reportTenant = null;
    });
    try {
      final report = await VoiceReportService(context.read<ApiService>())
          .query(_question.text);
      if (!mounted ||
          auth.currentUser?.id != owner ||
          auth.currentUser?.tenantId != tenant) {
        return;
      }
      setState(() {
        _report = report;
        _reportOwner = owner;
        _reportTenant = tenant;
      });
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool pdf) async {
    if (_exporting || _report == null) return;
    final auth = context.read<AuthService>();
    final owner = auth.currentUser?.id;
    final tenant = auth.currentUser?.tenantId;
    if (auth.currentUser?.canViewVoiceReports != true ||
        owner != _reportOwner || tenant != _reportTenant) {
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final export = VoiceReportExportService(context.read<ApiService>());
      final bytes = pdf
          ? await export.pdfBytes(_report!)
          : await export.excelBytes(_report!);
      if (!mounted ||
          auth.currentUser?.id != owner ||
          auth.currentUser?.tenantId != tenant) {
        return;
      }
      await export.share(
        bytes,
        pdf ? 'pdf' : 'xlsx',
        pdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final allowed = user?.canViewVoiceReports == true;
    final report = allowed && user?.id == _reportOwner &&
            user?.tenantId == _reportTenant ? _report : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes por voz')),
      body: !allowed
          ? const Center(child: Text('Tu cuenta no tiene acceso a reportes.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Pregunta por ventas, productos o sucursales.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _question,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Tu pregunta',
                    border: OutlineInputBorder(),
                    hintText: 'Ej. Top 5 productos más vendidos',
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _toggleMic,
                      icon: Icon(_listening ? Icons.stop : Icons.mic),
                      label: Text(_listening ? 'Detener dictado' : 'Dictar'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _query,
                        child: Text(
                          _busy ? 'Consultando...' : 'Generar reporte',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (report != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Resumen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report.interpretation.isEmpty
                        ? 'Sin interpretación disponible.'
                        : report.interpretation,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _tts?.toggleSpeak(
                      report.spokenSummary.isEmpty
                          ? report.interpretation
                          : report.spokenSummary,
                      id: 'reporte-voz',
                    ),
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Escuchar / detener'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Resultados (${report.rows.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (report.columns.isEmpty || report.rows.isEmpty)
                    const Text('La consulta no devolvió filas.')
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: report.columns
                            .map((c) => DataColumn(label: Text(c)))
                            .toList(),
                        rows: report.rows
                            .map(
                              (row) => DataRow(
                                cells: report.columns
                                    .map(
                                      (c) => DataCell(
                                        Text(row[c]?.toString() ?? '—'),
                                      ),
                                    )
                                    .toList(),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _export(true),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Guardar PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _export(false),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Guardar Excel'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
