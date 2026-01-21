import 'package:complex/complex.dart';

class ImpedanceData {
  /// 初始阻抗 Zinitial
  final Complex? zInitial;

  /// 目标阻抗 Ztarget
  final Complex? zTarget;

  /// 初始反射系数 Γinitial
  final Complex? gammaInitial;

  /// 目标反射系数 Γtarget
  final Complex? gammaTarget;

  /// 频率
  final double frequency;

  /// 特性阻抗 Z0
  final double z0;

  /// 构造函数，阻抗/反射系数参数二选一，未用部分传 null 即可
  ImpedanceData({
    this.zInitial,
    this.zTarget,
    this.gammaInitial,
    this.gammaTarget,
    required this.frequency,
    required this.z0,
  });
}
