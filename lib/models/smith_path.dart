import 'package:complex/complex.dart';

enum PathType {
  series,          // 串联元件 (沿电阻圆)
  shunt,           // 并联元件 (沿电导圆)
  transmissionLine // 传输线 (沿 VSWR 同心圆旋转)
}

class SmithPath {
  final Complex startGamma;
  final Complex endGamma;
  final PathType type;
  final String label;

  SmithPath({
    required this.startGamma,
    required this.endGamma,
    required this.type,
    this.label = '',
  });
}