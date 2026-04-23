import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<Uint8List?> showSignaturePadDialog(
  BuildContext context, {
  String title = 'Draw Signature',
}) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SignaturePadDialog(title: title),
  );
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog({required this.title});

  final String title;

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<Offset?> _points = <Offset?>[];
  final GlobalKey _repaintKey = GlobalKey();
  int? _activePointer;

  bool get _hasStroke => _points.any((p) => p != null);

  Future<void> _save() async {
    if (!_hasStroke) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw your signature first.')),
      );
      return;
    }

    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || byteData == null) return;
    Navigator.of(context).pop(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use your finger/mouse to sign below.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            RepaintBoundary(
              key: _repaintKey,
              child: Container(
                height: 210,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      _activePointer ??= event.pointer;
                      if (_activePointer != event.pointer) return;
                      final box = _repaintKey.currentContext?.findRenderObject() as RenderBox?;
                      final local = box?.globalToLocal(event.position);
                      if (local == null) return;
                      setState(() => _points.add(local));
                    },
                    onPointerMove: (event) {
                      if (_activePointer != event.pointer) return;
                      final box = _repaintKey.currentContext?.findRenderObject() as RenderBox?;
                      final local = box?.globalToLocal(event.position);
                      if (local == null) return;
                      setState(() => _points.add(local));
                    },
                    onPointerUp: (event) {
                      if (_activePointer != event.pointer) return;
                      setState(() => _points.add(null));
                      _activePointer = null;
                    },
                    onPointerCancel: (event) {
                      if (_activePointer != event.pointer) return;
                      setState(() => _points.add(null));
                      _activePointer = null;
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(_points),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_points.clear),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Use Signature'),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true;
  }
}
