import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/database/database_helper.dart';
import '../core/services/connectivity_service.dart';
import '../models/receipt_document.dart';
import '../services/api_service.dart';
import '../services/receipt_document_service.dart';

class ReceiptActions extends StatefulWidget {
  final ReceiptRef? reference;
  final ReceiptDocument? provisional;
  final String? email;
  final ReceiptDocumentService? service;
  const ReceiptActions({
    super.key,
    this.reference,
    this.provisional,
    this.email,
    this.service,
  });
  @override
  State<ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends State<ReceiptActions> {
  bool busy = false;
  String? message, attemptId, attemptRecipient;
  int generation = 0;
  BuildContext? emailDialog;
  ReceiptDocumentService get service =>
      widget.service ?? ReceiptDocumentService(context.read<ApiService>());
  @override
  void initState() {
    super.initState();
    DatabaseHelper.scopeChanges.addListener(_reset);
  }

  void _reset() {
    final dialog = emailDialog;
    if (dialog != null && dialog.mounted) {
      final route = ModalRoute.of(dialog);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.mounted && route != null){
          Navigator.of(dialog).removeRoute(route);
        }
      });
    }
    if (mounted) {
      setState(() {
        generation++;
        busy = false;
        message = null;
        attemptId = null;
        attemptRecipient = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReceiptActions old) {
    super.didUpdateWidget(old);
    if (old.reference?.id != widget.reference?.id ||
        old.reference?.kind != widget.reference?.kind ||
        old.provisional?.data['entity_id'] !=
            widget.provisional?.data['entity_id']) {
      generation++;
      busy = false;
      message = null;
      attemptId = null;
      attemptRecipient = null;
    }
  }

  @override
  void dispose() {
    generation++;
    DatabaseHelper.scopeChanges.removeListener(_reset);
    super.dispose();
  }

  bool current(int g, String? scope) =>
      mounted &&
      scope != null &&
      scope == DatabaseHelper.scope &&
      g == generation;
  Future<void> download() async {
    if (busy) return;
    final scope = DatabaseHelper.scope, g = generation;
    if (scope == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final bytes = widget.provisional != null
          ? await service.provisional(widget.provisional!)
          : await service.pdf(widget.reference!);
      if (current(g, scope)) {
        await service.export(
          bytes,
          widget.provisional?.data['entity_id']?.toString() ??
              widget.reference!.id,
        );
      }
    } catch (_) {
      if (current(g, scope)) {
        setState(
          () => message = 'No se pudo abrir el PDF. La operación se conserva. Revisa tu conexión.',
        );
      }
    } finally {
      if (current(g, scope)) setState(() => busy = false);
    }
  }

  Future<void> email() async {
    if (busy || widget.reference == null || widget.provisional != null) return;
    final scope = DatabaseHelper.scope, g = generation;
    if (scope == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (!await service.emailEnabled()) {
        throw StateError(
          'El envío de correo todavía no está configurado. Puedes descargar el PDF.',
        );
      }
      final address = await service.emailAddress(widget.reference!);
      if (!mounted || !current(g, scope)) return;
      final controller = TextEditingController(
        text: attemptRecipient ?? address ?? widget.email ?? '',
      );
      final recipient = await showDialog<String>(
        context: context,
        builder: (ctx) {
          emailDialog = ctx;
          return AlertDialog(
            title: const Text('Enviar comprobante'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Se enviará una copia PDF a este destinatario.'),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo destinatario',
                    ),
                    maxLength: 254,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Confirmar envío'),
              ),
            ],
          );
        },
      );
      emailDialog = null;
      // Dispose after the dialog route finishes unmounting its text field.
      Future.delayed(const Duration(seconds: 1), controller.dispose);
      if (!current(g, scope) || recipient == null) return;
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(recipient)) {
        throw StateError('Escribe un correo válido.');
      }
      if (attemptId == null || attemptRecipient != recipient) {
        attemptId = const Uuid().v4();
        attemptRecipient = recipient;
      }
      final result = await service.email(
        widget.reference!,
        recipient,
        attemptId!,
      );
      if (current(g, scope)) {
        setState(
          () => message =
              result['message']?.toString() ?? 'Consulta el estado del envío.',
        );
      }
    } catch (error) {
      if (current(g, scope)) {
        setState(
          () => message = error is StateError
              ? error.message.toString()
              : 'No se pudo consultar el correo. Puedes descargar el PDF.',
        );
      }
    } finally {
      if (current(g, scope)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityService?>()?.isOnline ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: busy || (!online && widget.provisional == null)
                    ? null
                    : download,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(busy ? 'Procesando…' : 'Descargar PDF'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !online || widget.provisional != null
                    ? null
                    : email,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Enviar al correo'),
              ),
            ],
          ),
          if (widget.provisional != null)
            const Text('Provisional: pendiente de confirmación central.'),
          if (!online || widget.provisional != null)
            const Text(
              'El correo requiere conexión y comprobante confirmado. No se enviará automáticamente.',
            ),
          if (message != null) Text(message!, semanticsLabel: message),
        ],
      ),
    );
  }
}
