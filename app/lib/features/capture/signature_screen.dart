// Pantalla de firma (Paso 22, tarea 4): devuelve el PNG de la firma, o `null`
// si el agente vuelve atrás sin aceptar.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/app_page_body.dart';
import '../../ui/widgets/signature_pad.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.title});

  /// Etiqueta del campo de firma de la plantilla.
  final String title;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _controller = SignatureController();
  final _padKey = GlobalKey();
  bool _exporting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final l10n = context.l10n;
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.signatureEmpty)));
      return;
    }
    final size = _padKey.currentContext?.size;
    if (size == null) return;
    setState(() => _exporting = true);
    final png = await _controller.toPng(size);
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(png);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AppPageBody(
        children: [
          Text(l10n.signatureHint),
          const AppGap.sm(),
          SignaturePad(key: _padKey, controller: _controller),
          const AppGap.sm(),
          OutlinedButton(
            key: const Key('signature_clear_button'),
            onPressed: _controller.clear,
            child: Text(l10n.signatureClear),
          ),
          const AppGap.sm(),
          AppButton(
            key: const Key('signature_accept_button'),
            label: l10n.signatureAccept,
            isLoading: _exporting,
            onPressed: _accept,
          ),
        ],
      ),
    );
  }
}
