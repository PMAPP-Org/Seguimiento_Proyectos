// Lienzo de firma táctil (Paso 22, tarea 4). Sin dependencias externas: los
// trazos se guardan como listas de puntos y se exportan a PNG con el mismo
// motor de dibujo de Flutter. La firma resultante se trata igual que una foto:
// se encola por su `sha256` (`AttachmentQueue`).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.every((stroke) => stroke.isEmpty);

  void startStroke(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void extendStroke(Offset point) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(point);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// PNG de la firma sobre papel blanco, o `null` si no se ha firmado.
  /// [pixelRatio] da resolución suficiente para imprimirla.
  Future<Uint8List?> toPng(Size size, {double pixelRatio = 2}) async {
    if (isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _SignaturePainter(_strokes).paint(canvas, size);
    final image = await recorder.endRecording().toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller});

  final SignatureController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.signatureHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: GestureDetector(
            onPanStart: (details) => controller.startStroke(details.localPosition),
            onPanUpdate: (details) => controller.extendStroke(details.localPosition),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => CustomPaint(
                painter: _SignaturePainter(controller.strokes),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppPalette.signaturePaper);
    final ink = Paint()
      ..color = AppPalette.signatureInk
      ..strokeWidth = AppSizes.signatureStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, AppSizes.signatureStroke / 2, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
