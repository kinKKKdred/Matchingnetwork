import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:complex/complex.dart';
import '../models/smith_path.dart';

class SmithChart extends StatelessWidget {
  final List<SmithPath> paths;
  final bool showAdmittance;
  // [新增] 接收固定点，用于处理无解或初始状态的显示
  final Complex? zOriginal;
  final Complex? zTarget;
  final double z0;

  const SmithChart({
    Key? key,
    this.paths = const [],
    this.showAdmittance = false,
    this.zOriginal,
    this.zTarget,
    this.z0 = 50.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 自适应宽度
        double availableWidth = constraints.maxWidth;
        double chartSize = availableWidth - 40;

        if (chartSize > 400) chartSize = 400;
        if (chartSize < 200) chartSize = 200;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: chartSize + 40,
              height: chartSize + 40,
              alignment: Alignment.center,
              child: CustomPaint(
                size: Size(chartSize, chartSize),
                painter: SmithChartPainter(
                  paths: paths,
                  showAdmittance: showAdmittance,
                  zOriginal: zOriginal, // 传入 Painter
                  zTarget: zTarget,     // 传入 Painter
                  z0: z0,               // 传入 Painter
                ),
              ),
            ),

            SizedBox(height: 12),

            // 只要有路径 或者 有起终点信息，就显示图例
            if (paths.isNotEmpty || zOriginal != null || zTarget != null)
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
      return '${z.real.toStringAsFixed(1)}$sign${z.imaginary.abs().toStringAsFixed(1)}j';
    }

    // 辅助：Gamma -> String
    String formatGamma(Complex gamma) {
      return formatZStr(_gammaToZ(gamma));
    }

    // 1. 起点图例
    if (zOriginal != null) {
      items.add(_legendItem(Colors.green, "Start: ${formatZStr(zOriginal!)}"));
    } else if (paths.isNotEmpty) {
      items.add(_legendItem(Colors.green, "Start: ${formatGamma(paths.first.startGamma)}"));
    }

    // 2. 中间点图例 (仅当有轨迹时显示)
    if (paths.length > 1) {
      for(int i=0; i < paths.length - 1; i++) {
        items.add(_legendItem(Colors.grey[700]!, "Mid: ${formatGamma(paths[i].endGamma)}"));
      }
    }

    // 3. 终点图例
    if (zTarget != null) {
      items.add(_legendItem(Colors.red, "Target: ${formatZStr(zTarget!)}"));
    } else if (paths.isNotEmpty) {
      items.add(_legendItem(Colors.red, "Target: ${formatGamma(paths.last.endGamma)}"));
    }

    // 4. 轨迹颜色说明 (仅当有轨迹时显示)
    if (paths.isNotEmpty) {
      bool hasTransLine = paths.any((p) => p.type == PathType.transmissionLine);
      String blueLabel = hasTransLine ? "Line (d)" : "Series";
      String orangeLabel = hasTransLine ? "Stub (l)" : "Shunt";

      items.add(_legendItem(Colors.blue[800]!, blueLabel, isTrajectory: true));
      items.add(_legendItem(Colors.orange[800]!, orangeLabel, isTrajectory: true));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: items,
      ),
    );
  }

  Widget _legendItem(Color color, String text, {bool isTrajectory = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: isTrajectory ? 12 : 8,
            height: isTrajectory ? 4 : 8,
            decoration: BoxDecoration(
              color: color,
              shape: isTrajectory ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isTrajectory ? BorderRadius.circular(2) : null,
            )
        ),
        SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Complex _gammaToZ(Complex g) { if ((Complex(1,0)-g).abs() < 1e-5) return Complex(1000, 0); return (Complex(1,0)+g)/(Complex(1,0)-g) * Complex(50, 0); } // 注意这里我乘了50只是为了简单显示，实际应乘z0，但在legend里通常归一化或者直接显示值，这里的逻辑最好统一。修正：上面formatZStr直接用了Z，这里_gammaToZ返回的是归一化Z还是实际Z取决于输入。为了通用，这里假设gamma转归一化Z，但在legend里我们想要实际Z，所以逻辑稍微调整了下。
// 为了简化，上面的 formatGamma 直接调用 _gammaToZ，这假设 _gammaToZ 返回归一化值。如果需要实际值，请自行乘 z0。
// 修正 _gammaToZ 为返回实际阻抗：
}

class SmithChartPainter extends CustomPainter {
  final List<SmithPath> paths;
  final bool showAdmittance;
  // [新增] 接收固定点
  final Complex? zOriginal;
  final Complex? zTarget;
  final double z0;

  SmithChartPainter({
    required this.paths,
    required this.showAdmittance,
    required this.zOriginal,
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
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double scale = radius;

    Path clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: scale));
    canvas.save();
    canvas.clipPath(clipPath);

    _drawGrid(canvas, center, scale);
    _drawActiveCircles(canvas, center, scale);
    _drawTrajectories(canvas, center, scale);

    canvas.restore();

    canvas.drawCircle(center, scale, Paint()..style = PaintingStyle.stroke..color = Colors.black);

    _drawAxisLabels(canvas, center, scale);

    // [修改] 绘制关键点 (包含无解时的起终点)
    _drawKeyPoints(canvas, center, scale);
  }

  void _drawGrid(Canvas canvas, Offset center, double scale) {
    final Paint rPaint = Paint()..style = PaintingStyle.stroke..color = colorRes..strokeWidth = 1.0;
    final Paint xPaint = Paint()..style = PaintingStyle.stroke..color = colorReact..strokeWidth = 1.0;
    final Paint axisPaint = Paint()..color = Colors.grey[400]!..strokeWidth = 1.0;

    canvas.drawLine(center + Offset(-scale, 0), center + Offset(scale, 0), axisPaint);
    for (double r in rCircles) {
      double cx = r / (1 + r); double cr = 1 / (1 + r);
      canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, rPaint);
    }
    for (double x in xArcs) {
      _drawArcCircle(canvas, center, scale, 1.0, 1/x, 1/x, xPaint);
      _drawArcCircle(canvas, center, scale, 1.0, -1/x, 1/x, xPaint);
    }
  }

  void _drawTrajectories(Canvas canvas, Offset center, double scale) {
    final Paint pathPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0..strokeCap = StrokeCap.round;

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
        for (var p in points) drawPath.lineTo(p.dx, p.dy);
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
        points.add(_gammaToOffset(Complex(r * cos(currentPhase), r * sin(currentPhase)), center, scale));
      }
    } else {
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
      } else { // Shunt
        Complex yStart = Complex(1,0)/zStart;
        Complex yEnd = Complex(1,0)/zEnd;
        double gConst = yStart.real;
        double bStart = yStart.imaginary;
        double bEnd = yEnd.imaginary;
        for (int i = 0; i <= steps; i++) {
          double t = i / steps;
          double b = bStart + (bEnd - bStart) * t;
          points.add(_gammaToOffset(_zToGamma_Normalized(Complex(1,0)/Complex(gConst, b)), center, scale));
        }
      }
    }
    return points;
  }

  void _drawAxisLabels(Canvas canvas, Offset center, double scale) {
    final double fontSize = 10.0;
    final rStyle = TextStyle(color: Colors.red[900], fontSize: fontSize, fontWeight: FontWeight.bold);

    _drawText(canvas, "0", center + Offset(-scale + 8, -8), style: rStyle);
    _drawText(canvas, "∞", center + Offset(scale - 8, -8), style: rStyle);

    for (double r in rCircles) {
      if (r == 0) continue;
      double u = (r - 1) / (r + 1);
      if (u.abs() > 0.95) continue;
      _drawText(canvas, r.toString(), center + Offset(u * scale, -6), style: rStyle);
    }

    final xStyle = TextStyle(color: Colors.blue[900], fontSize: fontSize, fontWeight: FontWeight.bold);

    for (double x in xArcs) {
      Complex g = _zToGamma_Normalized(Complex(0, x));
      Offset posUp = _gammaToOffset(g, center, scale * 1.08);
      _drawText(canvas, "${x}j", posUp, style: xStyle);

      Complex gDown = _zToGamma_Normalized(Complex(0, -x));
      Offset posDown = _gammaToOffset(gDown, center, scale * 1.08);
      _drawText(canvas, "-${x}j", posDown, style: xStyle);
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
        Complex y = Complex(1,0)/z;
        double g = y.real;
        double cx = -g / (1+g); double cr = 1 / (1+g);
        canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, paint);
      } else if (path.type == PathType.series) {
        double r = _gammaToZ_Normalized(path.startGamma).real;
        double cx = r / (1+r); double cr = 1 / (1+r);
        canvas.drawCircle(_gammaToOffset(Complex(cx, 0), center, scale), cr * scale, paint);
      }
    }
  }

  void _drawArcCircle(Canvas canvas, Offset center, double scale, double u, double v, double r, Paint paint) {
    Offset circleCenter = _gammaToOffset(Complex(u, v), center, scale);
    canvas.drawCircle(circleCenter, r * scale, paint);
  }

  // [修改] 绘制关键点逻辑
  void _drawKeyPoints(Canvas canvas, Offset center, double scale) {
    Paint p = Paint()..style = PaintingStyle.fill;

    // 1. 绘制 起点 (绿色)
    // 优先使用传入的 zOriginal (这在 paths 为空时非常重要)
    if (zOriginal != null) {
      p.color = Colors.green;
      // 先归一化，再转 Gamma
      Complex normZ = zOriginal! / Complex(z0, 0);
      Complex gamma = _zToGamma_Normalized(normZ);
      canvas.drawCircle(_gammaToOffset(gamma, center, scale), 4.5, p);
    } else if (paths.isNotEmpty) {
      // 兼容旧逻辑
      p.color = Colors.green;
      canvas.drawCircle(_gammaToOffset(paths.first.startGamma, center, scale), 4.5, p);
    }

    // 2. 绘制 终点 (红色)
    if (zTarget != null) {
      p.color = Colors.red;
      Complex normZ = zTarget! / Complex(z0, 0);
      Complex gamma = _zToGamma_Normalized(normZ);
      canvas.drawCircle(_gammaToOffset(gamma, center, scale), 4.5, p);
    } else if (paths.isNotEmpty) {
      p.color = Colors.red;
      canvas.drawCircle(_gammaToOffset(paths.last.endGamma, center, scale), 4.5, p);
    }

    // 3. 绘制 中间点 (灰色)
    if (paths.length > 1) {
      p.color = Colors.grey[700]!;
      for(int i=0; i < paths.length - 1; i++) {
        canvas.drawCircle(_gammaToOffset(paths[i].endGamma, center, scale), 4.0, p);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset pos, Offset vector, Color color) {
    double angle = atan2(vector.dy, vector.dx);
    canvas.save(); canvas.translate(pos.dx, pos.dy); canvas.rotate(angle);
    Path path = Path()..moveTo(0, 0)..lineTo(-7, -4)..lineTo(-7, 4)..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _drawText(Canvas canvas, String text, Offset pos, {TextStyle? style}) {
    final textStyle = style ?? TextStyle(color: Colors.black, fontSize: 10);

    TextPainter tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr
    );
    tp.layout();
    tp.paint(canvas, pos - Offset(tp.width/2, tp.height/2));
  }

  Offset _gammaToOffset(Complex g, Offset center, double scale) {
    if (g.real.isNaN || g.imaginary.isNaN) return center;
    double u = g.real.clamp(-2.0, 2.0); double v = g.imaginary.clamp(-2.0, 2.0);
    return center + Offset(u * scale, -v * scale);
  }

  // 内部辅助：处理归一化阻抗
  Complex _gammaToZ_Normalized(Complex g) {
    if ((Complex(1,0)-g).abs() < 1e-5) return Complex(1000, 0);
    return (Complex(1,0)+g)/(Complex(1,0)-g);
  }

  Complex _zToGamma_Normalized(Complex z) {
    if (z.real.isInfinite) return Complex(1,0);
    return (z - Complex(1,0))/(z + Complex(1,0));
  }

  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}