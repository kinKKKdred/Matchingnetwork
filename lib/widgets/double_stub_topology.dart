import 'package:flutter/material.dart';
import 'package:complex/complex.dart';
import '../utils/complex_utils.dart';

/// Double-stub topology: two shunt stubs separated by spacing s on the main line.
///
/// Scheme used by the solver:
/// - d = 0 (Stub1 at input plane)
/// - spacing s selectable (e.g., λ/8 or 3λ/8)
class DoubleStubTopology extends StatelessWidget {
  final double mainLineLengthLambda; // d (kept for completeness; typically 0)
  final double spacingLengthLambda;  // s
  final double stub1LengthLambda;    // l1
  final double stub2LengthLambda;    // l2
  final bool isShortStub;

  final Complex? zInitial;
  final Complex? zTarget;
  final Complex? gammaInitial;
  final Complex? gammaTarget;

  final double width;
  final double height;

  const DoubleStubTopology({
    Key? key,
    required this.mainLineLengthLambda,
    required this.spacingLengthLambda,
    required this.stub1LengthLambda,
    required this.stub2LengthLambda,
    this.isShortStub = true,
    this.zInitial,
    this.zTarget,
    this.gammaInitial,
    this.gammaTarget,
    this.width = 340,
    this.height = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String zinitStr = zInitial != null
        ? "Z_init = ${outputNum(zInitial!)}Ω"
        : (gammaInitial != null ? "Γ_init = ${outputNum(gammaInitial!)}" : "Source");

    String zTarStr = zTarget != null
        ? "Z_tar = ${outputNum(zTarget!)}Ω"
        : (gammaTarget != null ? "Γ_tar = ${outputNum(gammaTarget!)}" : "Load");

    return Column(
      children: [
        // Drawing area
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: CustomPaint(
            painter: DoubleStubCircuitPainter(
              isShort: isShortStub,
            ),
          ),
        ),

        // Info area
        Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendRow("Ports:", [zinitStr, zTarStr]),
              const SizedBox(height: 6),
              _buildLegendRow("Elec. Lengths:", [
                "d = ${mainLineLengthLambda.toStringAsFixed(4)}λ",
                "s = ${spacingLengthLambda.toStringAsFixed(4)}λ",
                "l1 = ${stub1LengthLambda.toStringAsFixed(4)}λ",
                "l2 = ${stub2LengthLambda.toStringAsFixed(4)}λ",
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendRow(String title, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.blueGrey[800],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: items
                .map(
                  (item) => Text(
                    item,
                    style: const TextStyle(fontSize: 12, fontFamily: 'RobotoMono'),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class DoubleStubCircuitPainter extends CustomPainter {
  final bool isShort;

  DoubleStubCircuitPainter({required this.isShort});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Coordinates
    final double startX = 60;
    final double endX = size.width - 60;
    final double yMain = size.height * 0.40;
    final double stubEndY = size.height * 0.80;

    // Place Stub1 near the input port (visual d=0), Stub2 further right.
    final double stub1X = startX + 20;
    final double stub2X = endX - 70;

    // Main line
    canvas.drawLine(Offset(startX, yMain), Offset(endX, yMain), paint);

    // Stub1
    canvas.drawLine(Offset(stub1X, yMain), Offset(stub1X, stubEndY), paint);
    canvas.drawCircle(Offset(stub1X, yMain), 3.0, fillPaint);
    _drawTermination(canvas, paint, fillPaint, Offset(stub1X, stubEndY));

    // Stub2
    canvas.drawLine(Offset(stub2X, yMain), Offset(stub2X, stubEndY), paint);
    canvas.drawCircle(Offset(stub2X, yMain), 3.0, fillPaint);
    _drawTermination(canvas, paint, fillPaint, Offset(stub2X, stubEndY));

    // Port labels (match L-matching style)
    _drawPortLabel(canvas, Offset(startX, yMain), "Z_init", isLeft: true);
    _drawPortLabel(canvas, Offset(endX, yMain), "Z_tar", isLeft: false);

    // Dimension markers
    // d=0 (start -> stub1)
    _drawDimensionLine(canvas, Offset(startX, yMain + 20), Offset(stub1X, yMain + 20), "d=0");
    // s (stub1 -> stub2)
    _drawDimensionLine(canvas, Offset(stub1X, yMain + 20), Offset(stub2X, yMain + 20), "s");
    // l1, l2
    _drawDimensionLine(canvas, Offset(stub1X + 15, yMain), Offset(stub1X + 15, stubEndY), "l_1", isVertical: true);
    _drawDimensionLine(canvas, Offset(stub2X + 15, yMain), Offset(stub2X + 15, stubEndY), "l_2", isVertical: true);
  }

  void _drawTermination(Canvas canvas, Paint paint, Paint fillPaint, Offset p) {
    if (isShort) {
      _drawGround(canvas, paint, p);
    } else {
      final Paint whiteFill = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 4.0, fillPaint);
      canvas.drawCircle(p, 2.5, whiteFill);
    }
  }

  void _drawGround(Canvas canvas, Paint paint, Offset p) {
    canvas.drawLine(Offset(p.dx - 10, p.dy), Offset(p.dx + 10, p.dy), paint);
    canvas.drawLine(Offset(p.dx - 6, p.dy + 4), Offset(p.dx + 6, p.dy + 4), paint);
    canvas.drawLine(Offset(p.dx - 2, p.dy + 8), Offset(p.dx + 2, p.dy + 8), paint);
  }

  void _drawPortLabel(Canvas canvas, Offset p, String text, {required bool isLeft}) {
    // Black dot
    canvas.drawCircle(p, 3.5, Paint()..style = PaintingStyle.fill);

    // "← Z_xxx" above the dot
    final String label = "← $text";
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(p.dx - (isLeft ? 0 : tp.width), p.dy - 22));
  }

  void _drawDimensionLine(
    Canvas canvas,
    Offset start,
    Offset end,
    String label, {
    bool isVertical = false,
  }) {
    final paint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, end, paint);

    // End caps
    if (!isVertical) {
      canvas.drawLine(Offset(start.dx, start.dy - 4), Offset(start.dx, start.dy + 4), paint);
      canvas.drawLine(Offset(end.dx, end.dy - 4), Offset(end.dx, end.dy + 4), paint);
    } else {
      canvas.drawLine(Offset(start.dx - 4, start.dy), Offset(start.dx + 4, start.dy), paint);
      canvas.drawLine(Offset(end.dx - 4, end.dy), Offset(end.dx + 4, end.dy), paint);
    }

    // Label
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    tp.paint(canvas, mid - Offset(tp.width / 2, isVertical ? -6 : 18));
  }

  @override
  bool shouldRepaint(covariant DoubleStubCircuitPainter oldDelegate) {
    return oldDelegate.isShort != isShort;
  }
}
