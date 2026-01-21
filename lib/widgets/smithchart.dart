import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:complex/complex.dart';
import '../models/smith_path.dart';

class SmithChart extends StatelessWidget {
  final List<SmithPath> paths;
  final bool showAdmittance;
  // [新增] 接收固定点，用于处理无解或初始状态的显示
  final Complex? zInitial;
  final Complex? zTarget;
  final double z0;

  const SmithChart({
    Key? key,
    this.paths = const [],
    this.showAdmittance = false,
    this.zInitial,
    this.zTarget,
    this.z0 = 50.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double size = min(constraints.maxWidth, constraints.maxHeight);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: SmithChartPainter(
                  paths: paths,
                  showAdmittance: showAdmittance,
                  zInitial: zInitial,
                  zTarget: zTarget,
                  z0: z0,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (paths.isNotEmpty || zInitial != null || zTarget != null)
              _buildDynamicLegend(context),
          ],
        );
      },
    );
  }

  Widget _buildDynamicLegend(BuildContext context) {
    List<Widget> items = [];

    // 辅助：Z -> String
    String formatZStr(Complex z) {
      if (z.real.abs() > 900) return "∞";
      String sign = z.imaginary >= 0 ? '+' : '-';
      return "${z.real.toStringAsFixed(1)}${sign}${z.imaginary.abs().toStringAsFixed(1)}j";
    }

    // 辅助：Gamma -> String
    String formatGammaStr(Complex g) {
      String sign = g.imaginary >= 0 ? '+' : '-';
      return "${g.real.toStringAsFixed(3)}${sign}${g.imaginary.abs().toStringAsFixed(3)}j";
    }

    // [修改] 用传入的 zInitial/zTarget 优先生成 Legend 点
    Complex? startGamma;
    Complex? targetGamma;

    if (zInitial != null) {
      // 归一化到 z0 后再算 Gamma
      Complex normZ = zInitial! / Complex(z0, 0);
      startGamma = _zToGamma_Normalized(normZ);
    } else if (paths.isNotEmpty) {
      startGamma = paths.first.startGamma;
    }

    if (zTarget != null) {
      Complex normZt = zTarget! / Complex(z0, 0);
      targetGamma = _zToGamma_Normalized(normZt);
    } else if (paths.isNotEmpty) {
      targetGamma = paths.last.endGamma;
    }

    if (startGamma != null) {
      Complex zStartNorm = _gammaToZ_Normalized(startGamma);
      Complex zStart = zStartNorm * Complex(z0, 0);
      items.add(_legendRow(
        color: Colors.green,
        title: "Initial",
        detail: "${formatZStr(zStart)}  (Γ=${formatGammaStr(startGamma)})",
      ));
    }

    // 如果有中间点，就显示
    if (paths.length >= 2) {
      Complex midGamma = paths.first.endGamma;
      Complex zMidNorm = _gammaToZ_Normalized(midGamma);
      Complex zMid = zMidNorm * Complex(z0, 0);
      items.add(_legendRow(
        color: Colors.black54,
        title: "Mid",
        detail: "${formatZStr(zMid)}  (Γ=${formatGammaStr(midGamma)})",
      ));
    }

    if (targetGamma != null) {
      Complex zTNorm = _gammaToZ_Normalized(targetGamma);
      Complex zT = zTNorm * Complex(z0, 0);
      items.add(_legendRow(
        color: Colors.red,
        title: "Target",
        detail: "${formatZStr(zT)}  (Γ=${formatGammaStr(targetGamma)})",
      ));
    }

    // path types legend
    items.add(const SizedBox(height: 8));
    items.add(Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 6,
      children: [
        _legendLine(color: Colors.blue[800]!, label: "Series"),
        _legendLine(color: Colors.orange[800]!, label: "Shunt"),
      ],
    ));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: items,
      ),
    );
  }

  Widget _legendRow({required Color color, required String title, required String detail}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text("$title: ", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Flexible(child: Text(detail, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _legendLine({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 24, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // ====== 下面这些工具函数供 Legend 使用 ======
  // 归一化 Z -> Γ
  Complex _zToGamma_Normalized(Complex normZ) {
    // Γ = (z - 1) / (z + 1)
    return (normZ - Complex(1, 0)) / (normZ + Complex(1, 0));
  }

  // Γ -> 归一化 Z
  Complex _gammaToZ_Normalized(Complex gamma) {
    // z = (1 + Γ) / (1 - Γ)
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma);
  }
}

class SmithChartPainter extends CustomPainter {
  final List<SmithPath> paths;
  final bool showAdmittance;
  // [新增] 接收固定点
  final Complex? zInitial;
  final Complex? zTarget;
  final double z0;

  SmithChartPainter({
    required this.paths,
    required this.showAdmittance,
    required this.zInitial,
    required this.zTarget,
    required this.z0,
  });

  final List<double> rCircles = [0, 0.2, 0.5, 1.0, 2.0, 5.0];
  final List<double> xArcs = [0.2, 0.5, 1.0, 2.0, 5.0];
  final Color colorRes = Colors.redAccent.withOpacity(0.2);
  final Color colorReact = Colors.blueAccent.withOpacity(0.2);

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double scale = radius;

    // Clip to circle
    Path clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: scale));
    canvas.save();
    canvas.clipPath(clipPath);

    _drawGrid(canvas, center, scale);

    // 画 Initial/Target 的等电阻圆 + 等电抗线（高亮，虚线 + 颜色避冲突 + 数值标注）
    _drawKeyPointImpedanceGuides(canvas, center, scale);

    _drawActiveCircles(canvas, center, scale);
    _drawTrajectories(canvas, center, scale);

    canvas.restore();

    canvas.drawCircle(center, scale, Paint()..style = PaintingStyle.stroke..color = Colors.black);

    _drawAxisLabels(canvas, center, scale);

    // 绘制关键点 (包含无解时的起终点)
    _drawKeyPoints(canvas, center, scale);
  }

  void _drawGrid(Canvas canvas, Offset center, double scale) {
    final Paint rPaint = Paint()..style = PaintingStyle.stroke..color = colorRes..strokeWidth = 1.0;
    final Paint xPaint = Paint()..style = PaintingStyle.stroke..color = colorReact..strokeWidth = 1.0;
    final Paint axisPaint = Paint()..color = Colors.grey[400]!..strokeWidth = 1.0;

    canvas.drawLine(center + Offset(-scale, 0), center + Offset(scale, 0), axisPaint);
    for (double r in rCircles) {
      double cx = r / (1 + r);
      double cr = 1 / (1 + r);
      canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, rPaint);
    }
    for (double x in xArcs) {
      _drawArcCircle(canvas, center, scale, 1.0, 1 / x, 1 / x, xPaint);
      _drawArcCircle(canvas, center, scale, 1.0, -1 / x, 1 / x, xPaint);
    }

    // 导纳网格（等电导圆 + 等电纳线）
    if (showAdmittance) {
      _drawAdmittanceGrid(canvas, center, scale);
    }
  }

  Complex? _getStartGamma() {
    if (zInitial != null) {
      final normZ = zInitial! / Complex(z0, 0);
      return _zToGamma_Normalized(normZ);
    }
    if (paths.isNotEmpty) return paths.first.startGamma;
    return null;
  }

  Complex? _getTargetGamma() {
    if (zTarget != null) {
      final normZ = zTarget! / Complex(z0, 0);
      return _zToGamma_Normalized(normZ);
    }
    if (paths.isNotEmpty) return paths.last.endGamma;
    return null;
  }

  // ---------- 虚线工具 ----------
  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dash = 8, double gap = 6}) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      while (dist < metric.length) {
        final double len = min(dash, metric.length - dist);
        final Path extract = metric.extractPath(dist, dist + len);
        canvas.drawPath(extract, paint);
        dist += dash + gap;
      }
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint paint,
      {double dash = 8, double gap = 6}) {
    final Path p = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    _drawDashedPath(canvas, p, paint, dash: dash, gap: gap);
  }

  // ---------- 关键点引导线（等r圆 + 等x线）+ 数值标注 ----------
  void _drawKeyPointImpedanceGuides(Canvas canvas, Offset center, double scale) {
    final Complex? startGamma = _getStartGamma();
    final Complex? targetGamma = _getTargetGamma();

    // 颜色策略：避开导纳网格(绿/紫)，用 teal / deepOrange；并用虚线区分“引导线”
    final Paint initialPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.teal[800]!.withOpacity(0.80)
      ..strokeWidth = 1.8;

    final Paint targetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.deepOrange[800]!.withOpacity(0.80)
      ..strokeWidth = 1.8;

    if (startGamma != null) {
      _drawImpedanceGuidesForGamma(
        canvas,
        center,
        scale,
        startGamma,
        initialPaint,
        label: "Initial",
        labelColor: Colors.teal[900]!,
      );
    }
    if (targetGamma != null) {
      _drawImpedanceGuidesForGamma(
        canvas,
        center,
        scale,
        targetGamma,
        targetPaint,
        label: "Target",
        labelColor: Colors.deepOrange[900]!,
      );
    }
  }

  void _drawImpedanceGuidesForGamma(
      Canvas canvas,
      Offset center,
      double scale,
      Complex gamma,
      Paint paint, {
        required String label,
        required Color labelColor,
      }) {
    // Γ -> 归一化阻抗 z = r + jx（Smith 网格默认就是归一化）
    final Complex z = _gammaToZ_Normalized(gamma);
    final double r = z.real;
    final double x = z.imaginary;

    // 1) 等电阻圆（constant r circle）：圆心 (r/(1+r),0)，半径 1/(1+r)
    if (r > -0.999) {
      final double cx = r / (1 + r);
      final double cr = 1 / (1 + r);
      final Offset cc = _gammaToOffset(Complex(cx, 0), center, scale);
      _drawDashedCircle(canvas, cc, cr * scale, paint);
    }

    // 2) 等电抗线（constant x arc）：圆心 (1, 1/x)，半径 1/|x|
    if (x.abs() > 1e-3) {
      final double u = 1.0;
      final double v = 1 / x;             // 带符号
      final double radius = 1 / x.abs();  // 半径为正
      final Offset cc = _gammaToOffset(Complex(u, v), center, scale);
      _drawDashedCircle(canvas, cc, radius * scale, paint);
    }

    // 3) 数值标注：在点旁标 r/x（归一化值，与网格一致）
    final Offset p = _gammaToOffset(gamma, center, scale);
    final String txt = "$label  r=${r.toStringAsFixed(2)}, x=${x.toStringAsFixed(2)}";

    // 简单避让：如果点在下半圈且靠近底部，标签强制往上放，减少与图例挤压
    double dy = (gamma.imaginary >= 0) ? -18 : 18;
    if (p.dy > center.dy + scale * 0.55) {
      dy = -24;
    } else if (p.dy < center.dy - scale * 0.55) {
      dy = 24;
    }

    // 向右偏一点，避免压到点和轨迹（你也可以改 65/70 来微调）
    final Offset pos = p + Offset(70, dy);

    _drawText(
      canvas,
      txt,
      pos,
      style: TextStyle(
        color: labelColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        backgroundColor: Colors.white.withOpacity(0.55),
      ),
    );
  }

  void _drawAdmittanceGrid(Canvas canvas, Offset center, double scale) {
    // 说明：
    // 等电导圆（constant g）：圆心 (-g/(1+g), 0)，半径 1/(1+g)
    // 等电纳线（constant b）：圆心 (-1, ±1/b)，半径 1/|b|

    final Paint gPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.greenAccent.withOpacity(0.45)
      ..strokeWidth = 1.4;

    final Paint bPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.purpleAccent.withOpacity(0.45)
      ..strokeWidth = 1.4;

    // 等电导圆（g circles）
    for (double g in rCircles) {
      if (g == 0) continue; // g=0 对应单位圆（外圈已绘制），避免重复
      double cx = -g / (1 + g);
      double cr = 1 / (1 + g);
      canvas.drawCircle(
        _gammaToOffset(Complex(cx, 0), center, scale),
        cr * scale,
        gPaint,
      );
    }

    // 等电纳线（b arcs）
    for (double b in xArcs) {
      _drawArcCircle(canvas, center, scale, -1.0, 1 / b, 1 / b, bPaint);
      _drawArcCircle(canvas, center, scale, -1.0, -1 / b, 1 / b, bPaint);
    }
  }

  void _drawTrajectories(Canvas canvas, Offset center, double scale) {
    final Paint pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (var path in paths) {
      if (path.type == PathType.shunt) {
        pathPaint.color = Colors.orange[800]!;
      } else {
        pathPaint.color = Colors.blue[800]!;
      }

      Path drawPath = Path();
      List<Offset> points = _generatePoints(path, center, scale);

      if (points.isNotEmpty) {
        drawPath.moveTo(points.first.dx, points.first.dy);
        for (var p in points) {
          drawPath.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(drawPath, pathPaint);

      if (drawPath.computeMetrics().isNotEmpty) {
        ui.PathMetric metric = drawPath.computeMetrics().first;
        ui.Tangent? tangent = metric.getTangentForOffset(metric.length * 0.6);
        if (tangent != null) {
          _drawArrow(canvas, tangent.position, tangent.vector, pathPaint.color);
        }
      }
    }
  }

  List<Offset> _generatePoints(SmithPath path, Offset center, double scale) {
    List<Offset> points = [];
    int steps = 60;

    if (path.type == PathType.transmissionLine) {
      double r = path.startGamma.abs();
      double startPhase = atan2(path.startGamma.imaginary, path.startGamma.real);
      double endPhase = atan2(path.endGamma.imaginary, path.endGamma.real);
      double diff = startPhase - endPhase;
      while (diff < 0) diff += 2 * pi;

      for (int i = 0; i <= steps; i++) {
        double t = i / steps;
        double currentPhase = startPhase - diff * t;
        points.add(_gammaToOffset(
          Complex(r * cos(currentPhase), r * sin(currentPhase)),
          center,
          scale,
        ));
      }
      return points;
    }

    // series/shunt 需要在 Z 或 Y 平面插值
    Complex zStart = _gammaToZ_Normalized(path.startGamma);
    Complex zEnd = _gammaToZ_Normalized(path.endGamma);

    if (path.type == PathType.series) {
      double rConst = zStart.real;
      double xStart = zStart.imaginary;
      double xEnd = zEnd.imaginary;
      for (int i = 0; i <= steps; i++) {
        double t = i / steps;
        double x = xStart + (xEnd - xStart) * t;
        points.add(_gammaToOffset(_zToGamma_Normalized(Complex(rConst, x)), center, scale));
      }
    } else {
      // Shunt：在导纳平面插值
      Complex yStart = Complex(1, 0) / zStart;
      Complex yEnd = Complex(1, 0) / zEnd;
      double gConst = yStart.real;
      double bStart = yStart.imaginary;
      double bEnd = yEnd.imaginary;
      for (int i = 0; i <= steps; i++) {
        double t = i / steps;
        double b = bStart + (bEnd - bStart) * t;
        Complex y = Complex(gConst, b);
        Complex z = Complex(1, 0) / y;
        points.add(_gammaToOffset(_zToGamma_Normalized(z), center, scale));
      }
    }

    return points;
  }

  void _drawArrow(Canvas canvas, Offset pos, Offset vec, Color color) {
    final double arrowSize = 8;
    final angle = atan2(vec.dy, vec.dx);

    Path arrow = Path();
    arrow.moveTo(pos.dx, pos.dy);
    arrow.lineTo(
      pos.dx - arrowSize * cos(angle - pi / 6),
      pos.dy - arrowSize * sin(angle - pi / 6),
    );
    arrow.moveTo(pos.dx, pos.dy);
    arrow.lineTo(
      pos.dx - arrowSize * cos(angle + pi / 6),
      pos.dy - arrowSize * sin(angle + pi / 6),
    );

    canvas.drawPath(
      arrow,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  Offset _gammaToOffset(Complex gamma, Offset center, double scale) {
    return center + Offset(gamma.real * scale, -gamma.imaginary * scale);
  }

  Complex _zToGamma_Normalized(Complex normZ) {
    return (normZ - Complex(1, 0)) / (normZ + Complex(1, 0));
  }

  Complex _gammaToZ_Normalized(Complex gamma) {
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma);
  }

  void _drawArcCircle(Canvas canvas, Offset center, double scale, double u, double v, double r, Paint paint) {
    Offset circleCenter = _gammaToOffset(Complex(u, v), center, scale);
    canvas.drawCircle(circleCenter, r * scale, paint);
  }

  // 绘制关键点逻辑
  void _drawKeyPoints(Canvas canvas, Offset center, double scale) {
    Paint p = Paint()..style = PaintingStyle.fill;

    // 1. 绘制 起点 (绿色)
    if (zInitial != null) {
      p.color = Colors.green;
      Complex normZ = zInitial! / Complex(z0, 0);
      Complex gamma = _zToGamma_Normalized(normZ);
      canvas.drawCircle(_gammaToOffset(gamma, center, scale), 4.5, p);
    } else if (paths.isNotEmpty) {
      p.color = Colors.green;
      canvas.drawCircle(_gammaToOffset(paths.first.startGamma, center, scale), 4.5, p);
    }

    // 2. 绘制 终点 (红色)
    if (zTarget != null) {
      p.color = Colors.red;
      Complex normZt = zTarget! / Complex(z0, 0);
      Complex gammaT = _zToGamma_Normalized(normZt);
      canvas.drawCircle(_gammaToOffset(gammaT, center, scale), 4.5, p);
    } else if (paths.isNotEmpty) {
      p.color = Colors.red;
      canvas.drawCircle(_gammaToOffset(paths.last.endGamma, center, scale), 4.5, p);
    }

    // 3. 绘制 中间点 (黑)
    if (paths.length >= 2) {
      p.color = Colors.black54;
      canvas.drawCircle(_gammaToOffset(paths.first.endGamma, center, scale), 4.5, p);
    }
  }

  void _drawAxisLabels(Canvas canvas, Offset center, double scale) {
    final double fontSize = 10.0;

    // ===== 阻抗网格标注：r（红） =====
    final rStyle = TextStyle(
      color: Colors.red[900],
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );

    _drawText(canvas, "0", center + Offset(-scale + 8, -8), style: rStyle);
    _drawText(canvas, "∞", center + Offset(scale - 8, -8), style: rStyle);

    for (double r in rCircles) {
      if (r == 0) continue;
      double u = (r - 1) / (r + 1);
      if (u.abs() > 0.95) continue;
      _drawText(canvas, r.toString(), center + Offset(u * scale, -6), style: rStyle);
    }

    // ===== 阻抗网格标注：x（蓝） =====
    final xStyle = TextStyle(
      color: Colors.blue[900],
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );

    for (double x in xArcs) {
      Complex gUp = _zToGamma_Normalized(Complex(0, x));
      Offset posUp = _gammaToOffset(gUp, center, scale * 1.08);
      _drawText(canvas, "${x}j", posUp, style: xStyle);

      Complex gDown = _zToGamma_Normalized(Complex(0, -x));
      Offset posDown = _gammaToOffset(gDown, center, scale * 1.08);
      _drawText(canvas, "-${x}j", posDown, style: xStyle);
    }

    // ===== 导纳网格标注（g / b） =====
    if (showAdmittance) {
      final gStyle = TextStyle(
        color: Colors.green[800],
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      );
      // g = ∞（左端点） 和 g = 0（右端点）——放在实轴下方
      _drawText(canvas, "∞", center + Offset(-scale + 10, 12), style: gStyle);
      _drawText(canvas, "0", center + Offset(scale - 10, 12), style: gStyle);

      for (double g in rCircles) {
        if (g == 0) continue;
        double u = (1 - g) / (1 + g);
        if (u.abs() > 0.95) continue;
        _drawText(canvas, g.toString(), center + Offset(u * scale, 10), style: gStyle);
      }

      final bStyle = TextStyle(
        color: Colors.purple[800],
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      );

      Offset _shiftTangential(Offset pos, Offset center, double px) {
        final dx = pos.dx - center.dx;
        final dy = pos.dy - center.dy;
        final len = sqrt(dx * dx + dy * dy);
        if (len < 1e-6) return pos;
        final tx = -dy / len;
        final ty = dx / len;
        return Offset(pos.dx + tx * px, pos.dy + ty * px);
      }

      for (double b in xArcs) {
        const double bRadiusFactor = 0.92;
        const double tangentShiftPx = 6.0;

        // y = +jb -> z = -j/b
        Complex gammaBPos = _zToGamma_Normalized(Complex(0, -1 / b));
        Offset posBPos = _gammaToOffset(gammaBPos, center, scale * bRadiusFactor);
        posBPos = _shiftTangential(posBPos, center, tangentShiftPx);
        _drawText(canvas, "${b}j", posBPos, style: bStyle);

        // y = -jb -> z = +j/b
        Complex gammaBNeg = _zToGamma_Normalized(Complex(0, 1 / b));
        Offset posBNeg = _gammaToOffset(gammaBNeg, center, scale * bRadiusFactor);
        posBNeg = _shiftTangential(posBNeg, center, -tangentShiftPx);
        _drawText(canvas, "-${b}j", posBNeg, style: bStyle);
      }
    }
  }

  void _drawActiveCircles(Canvas canvas, Offset center, double scale) {
    final Paint paint = Paint()..style = PaintingStyle.stroke..color = Colors.black54..strokeWidth = 0.5;

    for (var path in paths) {
      if (path.type == PathType.transmissionLine) {
        canvas.drawCircle(center, path.startGamma.abs() * scale, paint);
      } else if (path.type == PathType.shunt) {
        Complex z = _gammaToZ_Normalized(path.startGamma);
        if (z.abs() < 0.01) continue;
        Complex y = Complex(1, 0) / z;
        double g = y.real;
        double cx = -g / (1 + g);
        double cr = 1 / (1 + g);
        canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, paint);
      } else if (path.type == PathType.series) {
        double r = _gammaToZ_Normalized(path.startGamma).real;
        double cx = r / (1 + r);
        double cr = 1 / (1 + r);
        canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, paint);
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, {TextStyle? style}) {
    final textSpan = TextSpan(text: text, style: style ?? const TextStyle(fontSize: 10, color: Colors.black));
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
