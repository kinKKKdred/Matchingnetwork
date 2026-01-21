import 'dart:math';
import 'package:complex/complex.dart';

// 请确保引入了你的模型和工具类
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart'; // 假设这里有 outputNum 和 toLatexScientific

// 拓扑类型枚举
enum LTopologyType {
  seriesFirst, // 串联后并联
  shuntFirst,  // 并联后串联
}

// 单个解的数据结构
class LMatchSolution {
  final String title;
  final LTopologyType topologyType;
  final Map<String, double> values;
  final List<String> steps;
  final List<SmithPath> paths;
  final String filterType;

  LMatchSolution({
    required this.title,
    required this.topologyType,
    required this.values,
    required this.steps,
    required this.paths,
    this.filterType = "",
  });
}

// 总结果类
class MatchingResult {
  final List<LMatchSolution> solutions;
  final List<String> commonSteps;

  MatchingResult({
    required this.solutions,
    this.commonSteps = const [],
  });
}

/// L型网络匹配计算器 (完整版：包含鲁棒性修复 + 直通检测 + 完整计算逻辑)
class MatchingCalculator {

  static MatchingResult calculateLMatch(ImpedanceData data) {
    // ================= 1. 公共预处理 (输入转换与归一化) =================
    List<String> commonSteps = [];
    Complex zInitial, zTarget;

    // 解析输入
    if (data.zInitial != null && data.zTarget != null) {
      zInitial = data.zInitial!;
      zTarget = data.zTarget!;
    } else if (data.gammaInitial != null && data.gammaTarget != null) {
      zInitial = gammaToZ(data.gammaInitial!, data.z0);
      zTarget = gammaToZ(data.gammaTarget!, data.z0);
      commonSteps.add(r'\textbf{Step 0. Convert Reflection Coefficient to Impedance:}');
      commonSteps.add(r'Z_\mathrm{Init} = Z_0 \frac{1+\Gamma_\mathrm{Init}}{1-\Gamma_\mathrm{Init}} = ' + outputNum(zInitial, precision: 3) + r'\;\Omega');
      commonSteps.add(r'Z_\mathrm{tar} = Z_0 \frac{1+\Gamma_\mathrm{tar}}{1-\Gamma_\mathrm{tar}} = ' + outputNum(zTarget, precision: 3) + r'\;\Omega');
    } else {
      throw Exception('Input incomplete');
    }

    // ================= [NEW 1] 检查是否无需匹配 (Already Matched) =================
    // 阈值：如果两个阻抗的差异小于 0.05 欧姆，认为是一样的
    if ((zInitial - zTarget).abs() < 0.05) {
      List<String> infoSteps = [];
      infoSteps.add(r'\textbf{Status: Already Matched}');
      infoSteps.add(r'\text{The source impedance is sufficiently close to the target impedance.}');
      infoSteps.add(r'\Delta Z = |Z_\mathrm{Init} - Z_\mathrm{tar}| \approx 0');
      infoSteps.add(r'\text{No matching network is required (Direct Connection).}');

      // 构造一个“已匹配”的解
      LMatchSolution matchedSolution = LMatchSolution(
        title: "No Match Needed",
        topologyType: LTopologyType.seriesFirst, // 占位
        values: {}, // 空元件值，UI会自动隐藏电路图
        steps: infoSteps,
        paths: [], // 空轨迹，UI只会画起点和终点（重合）
        filterType: "Direct Connect",
      );

      return MatchingResult(solutions: [matchedSolution], commonSteps: commonSteps);
    }

    // ================= [NEW 2] 鲁棒性保护：纯虚部输入检查 =================
    // 修复 Bug：当 Z_initial 实部为 0 (纯电抗) 且 Z_target 实部 > 0 时，L型网络无解。
    const double epsilon = 1e-6;

    // 检查条件：起点是纯虚部 (R ≈ 0) 且 终点有实部 (R > 0)
    if (zInitial.real.abs() < epsilon && zTarget.real.abs() > epsilon) {
      List<String> errorSteps = [];
      errorSteps.add(r'\textbf{Feasibility Check Failed:}');
      errorSteps.add(r'\color{red}{\text{Error: Cannot match a pure reactance source (R=0) to a resistive load (R>0) using lossless L-networks.}}');
      errorSteps.add(r'\text{Reason: L-networks assume finite Q factors. Pure reactance implies infinite Q.}');
      errorSteps.add(r'\text{Visual Check: Notice the Start Point is on the outermost circle (R=0), while Target is inside. No path can bridge them.}');

      LMatchSolution errorSolution = LMatchSolution(
        title: "Infeasible Case",
        topologyType: LTopologyType.seriesFirst,
        values: {}, // 没有元件值
        steps: errorSteps,
        paths: [], // 空轨迹
        filterType: "No Solution",
      );

      return MatchingResult(solutions: [errorSolution], commonSteps: commonSteps);
    }
    // ================= [结束] 鲁棒性保护 =================

    // 归一化
    final z1 = zInitial / Complex(data.z0, 0);
    final z2 = zTarget / Complex(data.z0, 0);
    commonSteps.add(r'\textbf{Step 1. Normalize Impedances:}');
    commonSteps.add(r'z_\mathrm{Init} = \frac{Z_\mathrm{Init}}{Z_0} = ' + outputNum(z1, precision: 3));
    commonSteps.add(r'z_\mathrm{tar} = \frac{Z_\mathrm{tar}}{Z_0} = ' + outputNum(z2, precision: 3));

    List<LMatchSolution> solutions = [];

    // ================= 2. 尝试计算所有可能的解 =================

    // --- 尝试拓扑 A: Series First (串联 -> 并联) ---
    // 判别式: r1 < Re(Z_parallel_equivalent_of_target)
    double r1 = z1.real;
    Complex y2 = Complex(1,0) / z2;
    double g2 = y2.real;

    // 判别式：Series First 有解的条件
    double discriminantSeries = r1 / g2 - r1 * r1;

    if (discriminantSeries >= -1e-9) { // 允许微小误差
      double xMid_base = sqrt(max(0, discriminantSeries));

      // 解 1: 正根
      solutions.add(_calculateSingleSolution(
          data: data, z1: z1, z2: z2,
          topology: LTopologyType.seriesFirst,
          rootValue: xMid_base,
          isPositiveRoot: true
      ));

      // 解 2: 负根 (如果根不为0)
      if (xMid_base > 1e-9) {
        solutions.add(_calculateSingleSolution(
            data: data, z1: z1, z2: z2,
            topology: LTopologyType.seriesFirst,
            rootValue: -xMid_base,
            isPositiveRoot: false
        ));
      }
    } else {
      commonSteps.add(r'\text{Note: Series-first topology (Series } \to \text{ Shunt) has no solution for these impedances.}');
    }

    // --- 尝试拓扑 B: Shunt First (并联 -> 串联) ---
    Complex y1 = Complex(1,0) / z1;
    double g1 = y1.real;
    double r2 = z2.real;

    // 判别式
    double discriminantShunt = g1 / r2 - g1 * g1;

    if (discriminantShunt >= -1e-9) {
      double bMid_base = sqrt(max(0, discriminantShunt));

      // 解 3: 正根
      solutions.add(_calculateSingleSolution(
          data: data, z1: z1, z2: z2,
          topology: LTopologyType.shuntFirst,
          rootValue: bMid_base,
          isPositiveRoot: true
      ));

      // 解 4: 负根
      if (bMid_base > 1e-9) {
        solutions.add(_calculateSingleSolution(
            data: data, z1: z1, z2: z2,
            topology: LTopologyType.shuntFirst,
            rootValue: -bMid_base,
            isPositiveRoot: false
        ));
      }
    } else {
      commonSteps.add(r'\text{Note: Shunt-first topology (Shunt } \to \text{ Series) has no solution for these impedances.}');
    }

    // 为解添加序号和标题
    for(int i=0; i<solutions.length; i++) {
      String filterGuess = _guessFilterType(solutions[i].values);
      String topoName = solutions[i].topologyType == LTopologyType.seriesFirst ? "Series-First" : "Shunt-First";

      solutions[i] = LMatchSolution(
          title: "Solution ${i+1}: $topoName",
          topologyType: solutions[i].topologyType,
          values: solutions[i].values,
          steps: solutions[i].steps,
          paths: solutions[i].paths,
          filterType: filterGuess
      );
    }

    return MatchingResult(
      solutions: solutions,
      commonSteps: commonSteps,
    );
  }

  // ================= 私有辅助函数：计算单个解并生成详细步骤 =================
  static LMatchSolution _calculateSingleSolution({
    required ImpedanceData data,
    required Complex z1,
    required Complex z2,
    required LTopologyType topology,
    required double rootValue, // Series时为xMid, Shunt时为bMid
    required bool isPositiveRoot,
  }) {
    List<String> steps = [];
    List<SmithPath> smithPaths = [];
    Map<String, double> componentValues = {};

    Complex zMid;
    double Xs_norm = 0, B_norm = 0; // 归一化值
    double Xs_real = 0, Xp_real = 0; // 真实欧姆值

    if (topology == LTopologyType.seriesFirst) {
      // ================= Series First 详细计算 =================
      steps.add(r'\textbf{Step 2. Topology Selection (Series First):}');
      steps.add(r'\text{We connect a Series element first, moving along the constant-resistance circle to an intermediate point } z_{mid} \text{, and then a Shunt element to reach } z_{tar}.');

      // 1. 计算中间点
      double r1 = z1.real;
      double xMid = rootValue;
      zMid = Complex(r1, xMid);
      steps.add(r'\text{Calculated Intermediate Point (Intersection of circles):}');
      steps.add(r'z_{mid} = ' + outputNum(zMid, precision: 3));

      // 2. 串联元件计算 (z1 -> zMid)
      Complex diff = zMid - z1;
      Xs_norm = diff.imaginary;
      Xs_real = Xs_norm * data.z0;

      steps.add(r'\textbf{Step 3. Calculate Series Element:}');
      steps.add(r'\text{The series reactance required to move from } z_{Init} \text{ to } z_{mid} \text{ is:}');
      steps.add(r'j x_s = z_{mid} - z_{Init} = (' + outputNum(zMid, precision: 2) + r') - (' + outputNum(z1, precision: 2) + r')');
      steps.add(r'x_s = ' + outputNum(Xs_norm, precision: 3));
      steps.add(r'X_{series} = x_s \times Z_0 = ' + outputNum(Xs_norm, precision: 3) + r' \times ' + outputNum(data.z0) + r' = ' + outputNum(Xs_real, precision: 2) + r'\;\Omega');

      smithPaths.add(SmithPath(
          startGamma: zToGamma(z1), endGamma: zToGamma(zMid),
          type: PathType.series, label: Xs_real > 0 ? "L_ser" : "C_ser"
      ));

      // 3. 并联元件计算 (zMid -> z2)
      Complex y2 = Complex(1,0)/z2;
      Complex yMid = Complex(1,0)/zMid;
      Complex yDiff = y2 - yMid;
      B_norm = yDiff.imaginary;
      Xp_real = -data.z0 / B_norm;

      steps.add(r'\textbf{Step 4. Calculate Shunt Element:}');
      steps.add(r'\text{The shunt susceptance required to move from } z_{mid} \text{ to } z_{tar} \text{ is:}');
      steps.add(r'j b_p = y_{tar} - y_{mid} = \frac{1}{z_{tar}} - \frac{1}{z_{mid}}');
      steps.add(r'j b_p = (' + outputNum(y2, precision: 2) + r') - (' + outputNum(yMid, precision: 2) + r')');
      steps.add(r'b_p = ' + outputNum(B_norm, precision: 3));
      steps.add(r'\text{Convert susceptance to reactance: }');
      steps.add(r'X_{shunt} = \frac{-1}{B_{real}} = \frac{-Z_0}{b_p} = \frac{-' + outputNum(data.z0) + r'}{' + outputNum(B_norm, precision: 3) + r'} = ' + outputNum(Xp_real, precision: 2) + r'\;\Omega');

      smithPaths.add(SmithPath(
          startGamma: zToGamma(zMid), endGamma: zToGamma(z2),
          type: PathType.shunt, label: Xp_real > 0 ? "L_sh" : "C_sh"
      ));

    } else {
      // ================= Shunt First 详细计算 =================
      steps.add(r'\textbf{Step 2. Topology Selection (Shunt First):}');
      steps.add(r'\text{We connect a Shunt element first, moving along the constant-conductance circle to an intermediate point } z_{mid} \text{, and then a Series element to reach } z_{tar}.');

      // 1. 计算中间点
      double bMid = rootValue;
      Complex y1 = Complex(1,0)/z1;
      Complex yMid = Complex(y1.real, bMid);
      zMid = Complex(1,0)/yMid;

      steps.add(r'\text{Calculated Intermediate Admittance } y_{mid} \text{ and Impedance } z_{mid}:');
      steps.add(r'y_{mid} = ' + outputNum(yMid, precision: 3));
      steps.add(r'z_{mid} = 1 / y_{mid} = ' + outputNum(zMid, precision: 3));

      // 2. 并联元件计算 (y1 -> yMid)
      Complex diff = yMid - y1;
      B_norm = diff.imaginary;
      Xp_real = -data.z0 / B_norm;

      steps.add(r'\textbf{Step 3. Calculate Shunt Element:}');
      steps.add(r'\text{The shunt susceptance to move from } y_{Init} \text{ to } y_{mid} \text{ is:}');
      steps.add(r'j b_p = y_{mid} - y_{Init} = (' + outputNum(yMid, precision: 2) + r') - (' + outputNum(y1, precision: 2) + r')');
      steps.add(r'b_p = ' + outputNum(B_norm, precision: 3));
      steps.add(r'X_{shunt} = \frac{-Z_0}{b_p} = \frac{-' + outputNum(data.z0) + r'}{' + outputNum(B_norm, precision: 3) + r'} = ' + outputNum(Xp_real, precision: 2) + r'\;\Omega');

      smithPaths.add(SmithPath(
          startGamma: zToGamma(z1), endGamma: zToGamma(zMid),
          type: PathType.shunt, label: Xp_real > 0 ? "L_sh" : "C_sh"
      ));

      // 3. 串联元件计算 (zMid -> z2)
      Complex zDiff = z2 - zMid;
      Xs_norm = zDiff.imaginary;
      Xs_real = Xs_norm * data.z0;

      steps.add(r'\textbf{Step 4. Calculate Series Element:}');
      steps.add(r'\text{The series reactance to move from } z_{mid} \text{ to } z_{tar} \text{ is:}');
      steps.add(r'j x_s = z_{tar} - z_{mid} = (' + outputNum(z2, precision: 2) + r') - (' + outputNum(zMid, precision: 2) + r')');
      steps.add(r'x_s = ' + outputNum(Xs_norm, precision: 3));
      steps.add(r'X_{series} = x_s \times Z_0 = ' + outputNum(Xs_norm, precision: 3) + r' \times ' + outputNum(data.z0) + r' = ' + outputNum(Xs_real, precision: 2) + r'\;\Omega');

      smithPaths.add(SmithPath(
          startGamma: zToGamma(zMid), endGamma: zToGamma(z2),
          type: PathType.series, label: Xs_real > 0 ? "L_ser" : "C_ser"
      ));
    }

    // ================= 元件值转换步骤 =================
    steps.add(r'\textbf{Step 5. Convert to Component Values:}');
    _calculateComponentValuesDetailed(steps, Xs_real, Xp_real, data.frequency, componentValues);

    return LMatchSolution(
      title: "Temp Title",
      topologyType: topology,
      values: componentValues,
      steps: steps,
      paths: smithPaths,
    );
  }

  // 简单猜测滤波类型
  static String _guessFilterType(Map<String, double> values) {
    bool hasLSer = values.keys.any((k) => k.contains("Series Inductance"));
    bool hasCSer = values.keys.any((k) => k.contains("Series Capacitance"));
    bool hasLShunt = values.keys.any((k) => k.contains("Shunt Inductance"));
    bool hasCShunt = values.keys.any((k) => k.contains("Shunt Capacitance"));

    if (hasLSer && hasCShunt) return "Low Pass (L-C)";
    if (hasCSer && hasLShunt) return "High Pass (C-L)";
    if (hasLSer && hasLShunt) return "L-L (DC Block)";
    if (hasCSer && hasCShunt) return "C-C (AC Block)";
    return "Complex Match";
  }

  // 辅助：计算元件 L/C 值并生成详细步骤
  static void _calculateComponentValuesDetailed(List<String> steps, double Xs, double Xp, double f, Map<String, double> values) {
    double omega = 2 * pi * f;

    // Series Element
    if (Xs > 1e-9) {
      double L = Xs / omega;
      values["Series Inductance (H)"] = L;
      steps.add(r'\text{Series Element is inductive } (X_s > 0):');
      steps.add(r'L_{series} = \frac{X_s}{2\pi f} = \frac{' + outputNum(Xs, precision: 2) + r'}{2\pi \times ' + outputNum(f) + r'} = ' + toLatexScientific(L, digits: 3) + r'\;\mathrm{H}');
    } else if (Xs < -1e-9) {
      double C = -1 / (omega * Xs);
      values["Series Capacitance (F)"] = C;
      steps.add(r'\text{Series Element is capacitive } (X_s < 0):');
      steps.add(r'C_{series} = \frac{-1}{2\pi f X_s} = \frac{-1}{2\pi \times ' + outputNum(f) + r' \times (' + outputNum(Xs, precision: 2) + r')} = ' + toLatexScientific(C, digits: 3) + r'\;\mathrm{F}');
    }

    // Shunt Element
    if (Xp > 1e-9) {
      double L = Xp / omega;
      values["Shunt Inductance (H)"] = L;
      steps.add(r'\text{Shunt Element is inductive } (X_p > 0):');
      steps.add(r'L_{shunt} = \frac{X_p}{2\pi f} = \frac{' + outputNum(Xp, precision: 2) + r'}{2\pi \times ' + outputNum(f) + r'} = ' + toLatexScientific(L, digits: 3) + r'\;\mathrm{H}');
    } else if (Xp < -1e-9) {
      double C = -1 / (omega * Xp);
      values["Shunt Capacitance (F)"] = C;
      steps.add(r'\text{Shunt Element is capacitive } (X_p < 0):');
      steps.add(r'C_{shunt} = \frac{-1}{2\pi f X_p} = \frac{-1}{2\pi \times ' + outputNum(f) + r' \times (' + outputNum(Xp, precision: 2) + r')} = ' + toLatexScientific(C, digits: 3) + r'\;\mathrm{F}');
    }
  }

  static Complex zToGamma(Complex z) {
    if (z.real.isInfinite) return Complex(1, 0);
    if (z.abs() > 1e9) return Complex(1,0);
    return (z - Complex(1, 0)) / (z + Complex(1, 0));
  }

  static Complex gammaToZ(Complex gamma, double z0) {
    if ((Complex(1,0)-gamma).abs() < 1e-9) return Complex(1e9, 0);
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma) * Complex(z0, 0);
  }
}