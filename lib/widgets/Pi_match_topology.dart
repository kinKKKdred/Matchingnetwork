import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../utils/complex_utils.dart';

enum CompType { inductor, capacitor, none }

class PiMatchTopology extends StatelessWidget {
  final Map<String, double> values;
  final String zInitialStr;
  final String zTargetStr;
  final double width;
  final double height;

  const PiMatchTopology({
    Key? key,
    required this.values,
    required this.zInitialStr,
    required this.zTargetStr,
    this.width = 340,
    this.height = 220,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var c1 = _parseComp(values, 'L_shunt1', 'C_shunt1', '1');
    var c2 = _parseComp(values, 'L_series', 'C_series', 'series');
    var c3 = _parseComp(values, 'L_shunt2', 'C_shunt2', '2');

    return Column(
      children: [
        Container(
          width: width,
          height: height - 70,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: CustomPaint(
            painter: PiCircuitPainter(
              t1: c1.type, label1: c1.label,
              t2: c2.type, label2: c2.label,
              t3: c3.type, label3: c3.label,
            ),
          ),
        ),
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
              _buildLegendRow("Ports:", [zInitialStr, zTargetStr]),
              SizedBox(height: 6),
              Text("Components:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey[800])),
              SizedBox(height: 4),
              _buildLatexValue(c1.label, c1.valStr),
              _buildLatexValue(c2.label, c2.valStr),
              _buildLatexValue(c3.label, c3.valStr),
            ],
          ),
        ),
      ],
    );
  }

  _CompInfo _parseComp(Map<String, double> vals, String keyL, String keyC, String suffix) {
    if (vals.containsKey(keyL)) return _CompInfo(CompType.inductor, toLatexScientific(vals[keyL]!, digits: 3) + "\\mathrm{H}", 'L_{$suffix}');
    if (vals.containsKey(keyC)) return _CompInfo(CompType.capacitor, toLatexScientific(vals[keyC]!, digits: 3) + "\\mathrm{F}", 'C_{$suffix}');
    return _CompInfo(CompType.none, '', '');
  }

  Widget _buildLegendRow(String title, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey[800])),
        SizedBox(width: 8),
        Expanded(
          child: Wrap(spacing: 12, runSpacing: 4, children: items.map((item) => Text(item, style: TextStyle(fontSize: 12, fontFamily: 'RobotoMono'))).toList()),
        ),
      ],
    );
  }

  Widget _buildLatexValue(String label, String latexVal) {
    if (label.isEmpty) return SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Math.tex('$label = $latexVal', textStyle: TextStyle(fontSize: 13, color: Colors.black87)),
    );
  }
}

class _CompInfo {
  final CompType type;
  final String valStr;
  final String label;
  _CompInfo(this.type, this.valStr, this.label);
}

class PiCircuitPainter extends CustomPainter {
  final CompType t1; final String label1;
  final CompType t2; final String label2;
  final CompType t3; final String label3;

  PiCircuitPainter({required this.t1, required this.label1, required this.t2, required this.label2, required this.t3, required this.label3});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..strokeWidth = 2.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fillPaint = Paint()..color = Colors.black..style = PaintingStyle.fill;

    double startX = 50; double endX = size.width - 50;
    double midY = size.height * 0.45;
    double gndY = size.height * 0.85;

    double node1X = startX + (endX - startX) * 0.25;
    double node2X = startX + (endX - startX) * 0.75;

    // 1. 绘制主体
    canvas.drawLine(Offset(startX, midY), Offset(node1X, midY), paint);
    canvas.drawLine(Offset(node2X, midY), Offset(endX, midY), paint);

    // 2. 绘制元件
    _drawComponentVertical(canvas, paint, Offset(node1X, midY), gndY, t1, label1);
    _drawComponentHorizontal(canvas, paint, Offset(node1X, midY), Offset(node2X, midY), t2, label2);
    _drawComponentVertical(canvas, paint, Offset(node2X, midY), gndY, t3, label3);

    // 3. 端口箭头 (全部向左)
    _drawPortArrow(canvas, Offset(startX, midY), isInput: true);
    _drawPortArrow(canvas, Offset(endX, midY), isInput: false);

    // 4. 节点
    canvas.drawCircle(Offset(node1X, midY), 3, fillPaint);
    canvas.drawCircle(Offset(node2X, midY), 3, fillPaint);
  }

  void _drawComponentHorizontal(Canvas canvas, Paint paint, Offset p1, Offset p2, CompType type, String label) {
    double width = p2.dx - p1.dx;
    double compLen = 40;
    double wireLen = (width - compLen) / 2;
    Offset c1 = Offset(p1.dx + wireLen, p1.dy);
    Offset c2 = Offset(p2.dx - wireLen, p2.dy);

    canvas.drawLine(p1, c1, paint);
    canvas.drawLine(c2, p2, paint);

    if (type == CompType.inductor) _drawInductor(canvas, paint, c1, c2);
    else if (type == CompType.capacitor) _drawCapacitor(canvas, paint, c1, c2, vertical: false);
    else canvas.drawLine(c1, c2, paint);

    _drawLabel(canvas, label, Offset((p1.dx+p2.dx)/2, p1.dy - 20));
  }

  void _drawComponentVertical(Canvas canvas, Paint paint, Offset top, double bottomY, CompType type, String label) {
    double height = bottomY - top.dy;
    double compLen = 40;
    double wireLen = (height - compLen) / 2;
    Offset c1 = Offset(top.dx, top.dy + wireLen);
    Offset c2 = Offset(top.dx, bottomY - wireLen);

    canvas.drawLine(top, c1, paint);
    canvas.drawLine(c2, Offset(top.dx, bottomY), paint);
    _drawGround(canvas, paint, Offset(top.dx, bottomY));

    if (type == CompType.inductor) _drawInductorVertical(canvas, paint, c1, c2);
    else if (type == CompType.capacitor) _drawCapacitor(canvas, paint, c1, c2, vertical: true);

    _drawLabel(canvas, label, Offset(top.dx + 25, (top.dy + bottomY)/2));
  }

  void _drawLabel(Canvas canvas, String text, Offset center) {
    if (text.isEmpty) return;
    String cleanText = text.replaceAll(RegExp(r'[\{\}\_\\]'), '');
    if(cleanText.contains('series')) cleanText = cleanText.replaceAll('series', 's');

    TextSpan span = TextSpan(
      style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
      text: cleanText,
    );
    TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width/2, tp.height/2));
  }

  // 【修复】箭头逻辑：全部向左
  void _drawPortArrow(Canvas canvas, Offset p, {required bool isInput}) {
    canvas.drawCircle(p, 3.5, Paint()..style=PaintingStyle.fill);
    Paint arrowPaint = Paint()..color = Colors.black..strokeWidth = 2.0;
    double arrowLen = 30;

    // 逻辑：全部向左指 (从右往左画)
    // 箭头起点(尾部): p (黑点)
    // 箭头终点(头部): p.dx - arrowLen (黑点左侧)
    Offset start = p;
    Offset end = Offset(p.dx - arrowLen, p.dy);

    canvas.drawLine(start, end, arrowPaint);

    // 画箭头头部
    double angle = (end - start).direction; // 应该是 pi (180度)
    Path path = Path()..moveTo(end.dx, end.dy)..relativeLineTo(-7, -4)..relativeLineTo(0, 8)..close();
    canvas.save();
    canvas.translate(end.dx, end.dy); canvas.rotate(angle); canvas.translate(-end.dx, -end.dy);
    canvas.drawPath(path, Paint()..color = Colors.black..style = PaintingStyle.fill);
    canvas.restore();

    // 文字标签 (统一格式：← Z_ori)
    String label = isInput ? "Z_init" : "Z_tar";
    String text = "← $label";

    TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    // 文字位置：箭头上方
    Offset textPos = Offset((start.dx + end.dx) / 2, start.dy - 20);
    tp.paint(canvas, textPos - Offset(tp.width / 2, 0));
  }

  void _drawInductor(Canvas canvas, Paint paint, Offset p1, Offset p2) {
    double w = p2.dx - p1.dx; Path path = Path()..moveTo(p1.dx, p1.dy);
    for(int i=0; i<4; i++) path.quadraticBezierTo(p1.dx + w/4*i + w/8, p1.dy-10, p1.dx + w/4*(i+1), p1.dy);
    canvas.drawPath(path, paint);
  }
  void _drawInductorVertical(Canvas canvas, Paint paint, Offset p1, Offset p2) {
    double h = p2.dy - p1.dy; Path path = Path()..moveTo(p1.dx, p1.dy);
    for(int i=0; i<4; i++) path.quadraticBezierTo(p1.dx+10, p1.dy + h/4*i + h/8, p1.dx, p1.dy + h/4*(i+1));
    canvas.drawPath(path, paint);
  }
  void _drawCapacitor(Canvas canvas, Paint paint, Offset p1, Offset p2, {required bool vertical}) {
    double gap = 6; double plate = 14;
    if (!vertical) {
      double mx = (p1.dx+p2.dx)/2;
      canvas.drawLine(p1, Offset(mx-gap/2, p1.dy), paint);
      canvas.drawLine(Offset(mx-gap/2, p1.dy-plate), Offset(mx-gap/2, p1.dy+plate), paint);
      canvas.drawLine(Offset(mx+gap/2, p2.dy-plate), Offset(mx+gap/2, p2.dy+plate), paint);
      canvas.drawLine(Offset(mx+gap/2, p2.dy), p2, paint);
    } else {
      double my = (p1.dy+p2.dy)/2;
      canvas.drawLine(p1, Offset(p1.dx, my-gap/2), paint);
      canvas.drawLine(Offset(p1.dx-plate, my-gap/2), Offset(p1.dx+plate, my-gap/2), paint);
      canvas.drawLine(Offset(p2.dx-plate, my+gap/2), Offset(p2.dx+plate, my+gap/2), paint);
      canvas.drawLine(Offset(p2.dx, my+gap/2), p2, paint);
    }
  }
  void _drawGround(Canvas canvas, Paint paint, Offset p) {
    canvas.drawLine(Offset(p.dx-10, p.dy), Offset(p.dx+10, p.dy), paint);
    canvas.drawLine(Offset(p.dx-6, p.dy+4), Offset(p.dx+6, p.dy+4), paint);
    canvas.drawLine(Offset(p.dx-2, p.dy+8), Offset(p.dx+2, p.dy+8), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}