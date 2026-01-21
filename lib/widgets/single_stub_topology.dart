import 'package:flutter/material.dart';
import 'package:complex/complex.dart';
import '../utils/complex_utils.dart';

class SingleStubTopology extends StatelessWidget {
  final double mainLineLengthLambda;
  final double stubLengthLambda;
  final bool isShortStub;
  final String mode;
  final Complex? zInitial;
  final Complex? zTarget;
  final Complex? gammaInitial;
  final Complex? gammaTarget;

  final double width;
  final double height;

  const SingleStubTopology({
    Key? key,
    required this.mainLineLengthLambda,
    required this.stubLengthLambda,
    this.isShortStub = true,
    required this.mode,
    this.zInitial,
    this.zTarget,
    this.gammaInitial,
    this.gammaTarget,
    this.width = 340,
    this.height = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 准备显示的文本，保持简洁，因为上面已经有图例了
    String zinitStr = zInitial != null
        ? "Z_init = ${outputNum(zInitial!)}Ω"
        : (gammaInitial != null ? "Γ_init = ${outputNum(gammaInitial!)}" : "Source");

    String zTarStr = zTarget != null
        ? "Z_tar = ${outputNum(zTarget!)}Ω"
        : (gammaTarget != null ? "Γ_tar = ${outputNum(gammaTarget!)}" : "Load");

    return Column(
      children: [
        // 1. 绘图区域
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: CustomPaint(
            painter: SingleStubCircuitPainter(
              isShort: isShortStub,
            ),
          ),
        ),

        // 2. 参数信息区域
        Container(
          width: width,
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendRow("Ports:", [zinitStr, zTarStr]),
              SizedBox(height: 6),
              _buildLegendRow("Elec. Lengths:", [
                "d = ${mainLineLengthLambda.toStringAsFixed(4)}λ",
                "l = ${stubLengthLambda.toStringAsFixed(4)}λ",
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
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey[800])),
        SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: items.map((item) => Text(item, style: TextStyle(fontSize: 12, fontFamily: 'RobotoMono'))).toList(),
          ),
        ),
      ],
    );
  }
}

class SingleStubCircuitPainter extends CustomPainter {
  final bool isShort;

  SingleStubCircuitPainter({required this.isShort});

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

    // 坐标定义
    double startX = 60;
    double endX = size.width - 60;
    double yMain = size.height * 0.40;
    double stubX = endX - 70;
    // 【修复1】修正变量名
    double stubEndY = size.height * 0.80;

    // 1. 画主传输线
    canvas.drawLine(Offset(startX, yMain), Offset(endX, yMain), paint);

    // 2. 画 Stub
    canvas.drawLine(Offset(stubX, yMain), Offset(stubX, stubEndY), paint);

    // 连接点
    canvas.drawCircle(Offset(stubX, yMain), 3.0, fillPaint);

    // 3. 画 Stub 终端
    if (isShort) {
      _drawGround(canvas, paint, Offset(stubX, stubEndY));
    } else {
      Paint whiteFill = Paint()..color = Colors.white..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(stubX, stubEndY), 4.0, fillPaint);
      canvas.drawCircle(Offset(stubX, stubEndY), 2.5, whiteFill);
    }

    // 4. 【修复2】画端口标签（模仿 L-Match 风格）
    _drawPortLabel(canvas, Offset(startX, yMain), "Z_init", isLeft: true);
    _drawPortLabel(canvas, Offset(endX, yMain), "Z_tar", isLeft: false);

    // 5. 画尺寸标注
    _drawDimensionLine(canvas, Offset(startX, yMain + 20), Offset(stubX, yMain + 20), "d");
    _drawDimensionLine(canvas, Offset(stubX + 15, yMain), Offset(stubX + 15, stubEndY), "l", isVertical: true);
  }

  void _drawGround(Canvas canvas, Paint paint, Offset p) {
    canvas.drawLine(Offset(p.dx - 10, p.dy), Offset(p.dx + 10, p.dy), paint);
    canvas.drawLine(Offset(p.dx - 6, p.dy + 4), Offset(p.dx + 6, p.dy + 4), paint);
    canvas.drawLine(Offset(p.dx - 2, p.dy + 8), Offset(p.dx + 2, p.dy + 8), paint);
  }

  // 修改后的端口绘制函数，与 L-Match 风格一致
  void _drawPortLabel(Canvas canvas, Offset p, String text, {required bool isLeft}) {
    // 画黑点
    canvas.drawCircle(p, 3.5, Paint()..style=PaintingStyle.fill);

    // 画文字 "← Z_init"
    String label = "← $text";
    if (!isLeft) label = "$text →"; // 右边可能箭头向右比较好看，或者统一向左

    // 统一用 "← Z_xxx" 放在点上方
    label = "← $text";

    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    // 放在点上方 25 像素
    tp.paint(canvas, p - Offset(tp.width / 2, 25));
  }

  void _drawDimensionLine(Canvas canvas, Offset p1, Offset p2, String label, {bool isVertical = false}) {
    Paint dimPaint = Paint()..color = Colors.blueGrey..strokeWidth = 1.0;
    canvas.drawLine(p1, p2, dimPaint);

    _drawArrow(canvas, p1, p2, dimPaint.color);
    _drawArrow(canvas, p2, p1, dimPaint.color);

    TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: Colors.blueGrey, fontSize: 12, fontStyle: FontStyle.italic)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    Offset center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    if (isVertical) {
      tp.paint(canvas, center + Offset(5, -tp.height / 2));
    } else {
      tp.paint(canvas, center - Offset(tp.width / 2, 2));
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    double angle = (to - from).direction;
    Path path = Path();
    path.moveTo(to.dx, to.dy);
    path.relativeLineTo(-7, -4);
    path.relativeLineTo(0, 8);
    path.close();

    canvas.save();
    canvas.translate(to.dx, to.dy);
    canvas.rotate(angle);
    canvas.translate(-to.dx, -to.dy);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}