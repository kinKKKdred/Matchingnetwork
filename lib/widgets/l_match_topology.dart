import 'package:flutter/material.dart';
import '../utils/matching_calculator.dart'; // 引用其中的 LTopologyType

// 内部使用的元件类型枚举
enum ComponentType { inductor, capacitor, none }

class LMatchTopology extends StatelessWidget {
  final LTopologyType topology;
  final Map<String, double> values;
  final String zInitialValue;
  final String zTargetValue;

  final double width;
  final double height;

  const LMatchTopology({
    Key? key,
    required this.topology,
    required this.values,
    required this.zInitialValue,
    required this.zTargetValue,
    this.width = 340,
    this.height = 160, // 高度可以稍微减小，因为图里没字了
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. 解析元件信息（类型、标签、格式化后的数值）
    ComponentType seriesType = ComponentType.none;
    String seriesLabelStr = "";
    String seriesValueStr = "";

    ComponentType shuntType = ComponentType.none;
    String shuntLabelStr = "";
    String shuntValueStr = "";

    // 解析串联元件
    if (values.containsKey("Series Inductance (H)")) {
      seriesType = ComponentType.inductor;
      seriesLabelStr = "L_series";
      seriesValueStr = _formatValue(values["Series Inductance (H)"]!, "H");
    } else if (values.containsKey("Series Capacitance (F)")) {
      seriesType = ComponentType.capacitor;
      seriesLabelStr = "C_series";
      seriesValueStr = _formatValue(values["Series Capacitance (F)"]!, "F");
    }

    // 解析并联元件
    if (values.containsKey("Shunt Inductance (H)")) {
      shuntType = ComponentType.inductor;
      shuntLabelStr = "L_shunt";
      shuntValueStr = _formatValue(values["Shunt Inductance (H)"]!, "H");
    } else if (values.containsKey("Shunt Capacitance (F)")) {
      shuntType = ComponentType.capacitor;
      shuntLabelStr = "C_shunt";
      shuntValueStr = _formatValue(values["Shunt Capacitance (F)"]!, "F");
    }

    // 2. 使用 Column 布局：上面是图，下面是参数图例
    return Column(
      children: [
        // === 上部分：干净的电路图 ===
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)), // 只圆上面
          ),
          child: CustomPaint(
            painter: LMatchCircuitPainter(
              topology: topology,
              seriesType: seriesType,
              seriesLabel: seriesLabelStr, // 只传标签(L_series)
              shuntType: shuntType,
              shuntLabel: shuntLabelStr, // 只传标签(C_shunt)
            ),
          ),
        ),

        // === 下部分：参数图例区域 ===
        Container(
          width: width,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100, // 浅灰色背景
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)), // 只圆下面
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 端口阻抗值
              _buildLegendRow("Ports:", [
                "Z_init = $zInitialValue",
                "Z_tar = $zTargetValue",
              ]),
              SizedBox(height: 8),
              // 元件值
              _buildLegendRow("Components:", [
                if (seriesValueStr.isNotEmpty) "$seriesLabelStr = $seriesValueStr",
                if (shuntValueStr.isNotEmpty) "$shuntLabelStr = $shuntValueStr",
              ]),
            ],
          ),
        ),
      ],
    );
  }

  // 构建图例行的辅助函数
  Widget _buildLegendRow(String title, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey[800])),
        SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            children: items.map((item) => Text(item, style: TextStyle(fontSize: 13, fontFamily: 'RobotoMono'))).toList(),
          ),
        ),
      ],
    );
  }

  String _formatValue(double val, String unit) {
    if (val < 1e-9) return "${(val * 1e12).toStringAsFixed(2)} p$unit";
    if (val < 1e-6) return "${(val * 1e9).toStringAsFixed(2)} n$unit";
    if (val < 1e-3) return "${(val * 1e6).toStringAsFixed(2)} μ$unit";
    return "${val.toStringAsExponential(2)} $unit";
  }
}

// 核心绘图器 (只负责画图和标签，不画数值)
class LMatchCircuitPainter extends CustomPainter {
  final LTopologyType topology;
  final ComponentType seriesType;
  final String seriesLabel;
  final ComponentType shuntType;
  final String shuntLabel;

  LMatchCircuitPainter({
    required this.topology,
    required this.seriesType,
    required this.seriesLabel,
    required this.shuntType,
    required this.shuntLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double startX = 50;
    double endX = size.width - 50;
    double midY = size.height * 0.4;
    double gndY = size.height * 0.85;

    double slot1X = startX + (endX - startX) / 3;
    double slot2X = startX + 2 * (endX - startX) / 3;

    // 绘制端口 (只画带箭头的标签)
    _drawPort(canvas, Offset(startX, midY), "Z_init");
    _drawPort(canvas, Offset(endX, midY), "Z_tar");

    if (topology == LTopologyType.seriesFirst) {
      // start -> (series) -> slot2 -> end
      _drawComponentSeries(
        canvas,
        paint,
        Offset(startX, midY),
        Offset(slot2X, midY),
        seriesType,
        seriesLabel,
      );

      // 只有存在 shunt 元件时才画到地
      if (shuntType != ComponentType.none) {
        _drawComponentShunt(
          canvas,
          paint,
          Offset(slot2X, midY),
          gndY,
          shuntType,
          shuntLabel,
        );
      }

      canvas.drawLine(Offset(slot2X, midY), Offset(endX, midY), paint);
    } else {
      // start -> slot1
      canvas.drawLine(Offset(startX, midY), Offset(slot1X, midY), paint);

      // 只有存在 shunt 元件时才画到地
      if (shuntType != ComponentType.none) {
        _drawComponentShunt(
          canvas,
          paint,
          Offset(slot1X, midY),
          gndY,
          shuntType,
          shuntLabel,
        );
      }

      // slot1 -> (series) -> end
      _drawComponentSeries(
        canvas,
        paint,
        Offset(slot1X, midY),
        Offset(endX, midY),
        seriesType,
        seriesLabel,
      );
    }
  }

  // --- 绘制串联元件 (只画标签) ---
  void _drawComponentSeries(Canvas canvas, Paint paint, Offset p1, Offset p2, ComponentType type, String label) {
    double dist = p2.dx - p1.dx;
    double compWidth = 60;
    double wireLen = (dist - compWidth) / 2;
    Offset cStart = Offset(p1.dx + wireLen, p1.dy);
    Offset cEnd = Offset(p2.dx - wireLen, p2.dy);

    canvas.drawLine(p1, cStart, paint);
    canvas.drawLine(cEnd, p2, paint);

    // 文字垂直偏移量
    double textOffsetY = -25;

    if (type == ComponentType.inductor) {
      _drawInductor(canvas, paint, cStart, cEnd);
      _drawText(canvas, label, Offset((cStart.dx+cEnd.dx)/2, cStart.dy + textOffsetY));
    } else if (type == ComponentType.capacitor) {
      _drawCapacitor(canvas, paint, cStart, cEnd, isVertical: false);
      _drawText(canvas, label, Offset((cStart.dx+cEnd.dx)/2, cStart.dy + textOffsetY));
    } else {
      canvas.drawLine(cStart, cEnd, paint);
    }
  }

  // --- 绘制并联元件 (只画标签) ---
  void _drawComponentShunt(Canvas canvas, Paint paint, Offset topNode, double bottomY, ComponentType type, String label) {
    double dist = bottomY - topNode.dy;
    double compHeight = 40;
    double wireLen = (dist - compHeight) / 2;
    Offset cStart = Offset(topNode.dx, topNode.dy + wireLen);
    Offset cEnd = Offset(topNode.dx, bottomY - wireLen);

    canvas.drawLine(topNode, cStart, paint);
    canvas.drawLine(cEnd, Offset(topNode.dx, bottomY), paint);
    _drawGround(canvas, paint, Offset(topNode.dx, bottomY));
    canvas.drawCircle(topNode, 3, Paint()..style=PaintingStyle.fill);

    // 文字水平偏移量
    double textOffsetX = 45;

    if (type == ComponentType.inductor) {
      _drawInductorVertical(canvas, paint, cStart, cEnd);
      _drawText(canvas, label, Offset(cStart.dx + textOffsetX, (cStart.dy+cEnd.dy)/2));
    } else if (type == ComponentType.capacitor) {
      _drawCapacitor(canvas, paint, cStart, cEnd, isVertical: true);
      _drawText(canvas, label, Offset(cStart.dx + textOffsetX, (cStart.dy+cEnd.dy)/2));
    }
  }

  // --- 基础绘图函数 (保持不变) ---
  void _drawInductor(Canvas canvas, Paint paint, Offset p1, Offset p2) {
    double width = p2.dx - p1.dx;
    double coilRadius = 6.0;
    int coils = 4;
    double coilWidth = width / coils;
    Path path = Path();
    path.moveTo(p1.dx, p1.dy);
    for (int i = 0; i < coils; i++) {
      double startX = p1.dx + i * coilWidth;
      path.quadraticBezierTo(startX + coilWidth / 2, p1.dy - coilRadius * 2.2, startX + coilWidth, p1.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawInductorVertical(Canvas canvas, Paint paint, Offset p1, Offset p2) {
    double height = p2.dy - p1.dy;
    double coilRadius = 6.0;
    int coils = 4;
    double coilHeight = height / coils;
    Path path = Path();
    path.moveTo(p1.dx, p1.dy);
    for (int i = 0; i < coils; i++) {
      double startY = p1.dy + i * coilHeight;
      path.quadraticBezierTo(p1.dx + coilRadius * 2.2, startY + coilHeight / 2, p1.dx, startY + coilHeight);
    }
    canvas.drawPath(path, paint);
  }

  void _drawCapacitor(Canvas canvas, Paint paint, Offset p1, Offset p2, {required bool isVertical}) {
    double plateSize = 14.0;
    double gap = 6.0;
    if (!isVertical) {
      double midX = (p1.dx + p2.dx) / 2;
      canvas.drawLine(p1, Offset(midX - gap/2, p1.dy), paint);
      canvas.drawLine(Offset(midX - gap/2, p1.dy - plateSize), Offset(midX - gap/2, p1.dy + plateSize), paint);
      canvas.drawLine(Offset(midX + gap/2, p2.dy - plateSize), Offset(midX + gap/2, p2.dy + plateSize), paint);
      canvas.drawLine(Offset(midX + gap/2, p2.dy), p2, paint);
    } else {
      double midY = (p1.dy + p2.dy) / 2;
      canvas.drawLine(p1, Offset(p1.dx, midY - gap/2), paint);
      canvas.drawLine(Offset(p1.dx - plateSize, midY - gap/2), Offset(p1.dx + plateSize, midY - gap/2), paint);
      canvas.drawLine(Offset(p2.dx - plateSize, midY + gap/2), Offset(p2.dx + plateSize, midY + gap/2), paint);
      canvas.drawLine(Offset(p2.dx, midY + gap/2), p2, paint);
    }
  }

  void _drawGround(Canvas canvas, Paint paint, Offset p) {
    canvas.drawLine(Offset(p.dx - 12, p.dy), Offset(p.dx + 12, p.dy), paint);
    canvas.drawLine(Offset(p.dx - 7, p.dy + 4), Offset(p.dx + 7, p.dy + 4), paint);
    canvas.drawLine(Offset(p.dx - 2, p.dy + 8), Offset(p.dx + 2, p.dy + 8), paint);
  }

  // --- 改进：绘制带箭头的端口 ---
  void _drawPort(Canvas canvas, Offset p, String text) {
    Paint dotPaint = Paint()..style = PaintingStyle.fill..color = Colors.black;
    canvas.drawCircle(p, 3.5, dotPaint);

    // 在文字前加上向左的箭头
    _drawText(canvas, "← $text", Offset(p.dx, p.dy - 25));
  }

  void _drawText(Canvas canvas, String text, Offset center) {
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.bold, // 标签加粗
          fontFamily: 'Roboto',
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}