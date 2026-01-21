import 'dart:math';
import 'package:complex/complex.dart';
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart';

class TMatchingResult {
  final Map<String, double> values;
  final List<String> steps;
  final String topology;
  final List<SmithPath> paths;

  TMatchingResult({
    required this.values,
    required this.steps,
    required this.topology,
    required this.paths,
  });
}

class TMatchingCalculator {

  static TMatchingResult calculateTMatching(ImpedanceData data, {double? userQ}) {
    List<String> steps = [];
    Map<String, double> values = {};
    List<SmithPath> paths = [];

    // 1. 数据准备
    double f = data.frequency;
    double omega = 2 * pi * f;
    Complex zS = data.zInitial ?? Complex(50, 0);
    Complex zL = data.zTarget ?? Complex(50, 0);

    steps.add(r'\textbf{Step 1. System Analysis:}');
    steps.add(r'Z_{Init} = ' + outputNum(zS) + r'\;\Omega, \quad Z_{tar} = ' + outputNum(zL) + r'\;\Omega');

    // 2. 确定 Q 值与虚拟电阻 Rv
    double R_src = zS.real;
    double R_load = zL.real;
    double R_max = max(R_src, R_load);
    double R_min = min(R_src, R_load);

    // 计算临界 Q 值 (Q_min)
    // T-Network requires Rv > R_max.
    // Rv = R_min * (Q^2 + 1) > R_max  => Q^2 + 1 > R_max / R_min
    double qMin = sqrt(max(0, R_max / R_min - 1));

    steps.add(r'\textbf{Step 2. Determine Q & Virtual Resistor (High Z):}');
    steps.add(r'\text{T-Network transforms up to a high intermediate resistance } R_v.');
    steps.add(r'Q_{min} = \sqrt{\frac{R_{max}}{R_{min}} - 1} = ' + outputNum(qMin, precision: 2));

    double Q = userQ ?? (qMin < 1.0 ? 2.0 : qMin + 1.0);
    if (Q < qMin) {
      Q = qMin + 0.1;
      steps.add(r'\color{red}\text{User Q too low. Adjusted to } ' + outputNum(Q, precision: 2));
    } else {
      steps.add(r'\text{Selected Q: } \mathbf{Q = ' + outputNum(Q, precision: 2) + r'}');
    }

    // 计算虚拟电阻 Rv
    double Rv = R_min * (pow(Q, 2) + 1);
    // Safety check: Rv must be > R_max
    if (Rv < R_max) Rv = R_max * 1.05;

    steps.add(r'\text{Calculate Virtual Resistor } R_v:');
    steps.add(r'R_v = R_{min}(Q^2 + 1) = \mathbf{' + outputNum(Rv, precision: 1) + r'\;\Omega}');

    // 3. 计算左侧 L 网络 (Source -> Rv) [Step Up]
    double Q_L = sqrt(max(0, Rv / R_src - 1));
    double Xs1_ideal = Q_L * R_src; // Series Reactance
    double Bp1_ideal = Q_L / Rv;    // Shunt Susceptance

    steps.add(r'\textbf{Step 3. Left Side (Source } \to R_v):');
    steps.add(r'Q_L = \sqrt{R_v/R_{src} - 1} = ' + outputNum(Q_L, precision: 2));
    steps.add(r'X_{s1,ideal} = Q_L R_{src} = ' + outputNum(Xs1_ideal, precision: 2) + r'\;\Omega');

    // 4. 计算右侧 L 网络 (Load -> Rv) [Step Up]
    double Q_R = sqrt(max(0, Rv / R_load - 1));
    double Xs2_ideal = Q_R * R_load; // Series Reactance
    double Bp2_ideal = Q_R / Rv;    // Shunt Susceptance

    steps.add(r'\textbf{Step 4. Right Side (Load } \to R_v):');
    steps.add(r'Q_R = \sqrt{R_v/R_{load} - 1} = ' + outputNum(Q_R, precision: 2));
    steps.add(r'X_{s2,ideal} = Q_R R_{load} = ' + outputNum(Xs2_ideal, precision: 2) + r'\;\Omega');

    // 5. 组合与去嵌入 (Low Pass: L-C-L)
    // Series arms are Inductors (X > 0), Shunt arm is Capacitor (B > 0)

    // De-embedding Input Series
    double X_src = zS.imaginary;
    double X_net1 = Xs1_ideal - X_src;

    // De-embedding Output Series
    double X_load = zL.imaginary;
    double X_net2 = Xs2_ideal - X_load;

    // Center Shunt (Sum of susceptances)
    double B_total = Bp1_ideal + Bp2_ideal;

    steps.add(r'\textbf{Step 5. Component Calculation (De-embedded):}');
    steps.add(r'\text{Structure: Series } L_1 \text{ - Shunt } C_{sh} \text{ - Series } L_2');

    // L1 Calculation
    if (X_net1 > 0) {
      double L1 = X_net1 / omega;
      values['L_series1'] = L1;
      steps.add(r'L_1 = \frac{X_{s1} - X_{src}}{\omega} = ' + toLatexScientific(L1, digits: 3) + r'\;\mathrm{H}');
    } else {
      double C1 = -1 / (X_net1 * omega);
      values['C_series1'] = C1;
      steps.add(r'C_1 (\text{Neg. L}) = ' + toLatexScientific(C1, digits: 3) + r'\;\mathrm{F}');
    }

    // C_shunt Calculation
    if (B_total > 0) {
      double C_sh = B_total / omega;
      values['C_shunt'] = C_sh;
      steps.add(r'C_{shunt} = \frac{B_{p1} + B_{p2}}{\omega} = ' + toLatexScientific(C_sh, digits: 3) + r'\;\mathrm{F}');
    } else {
      double L_sh = -1 / (B_total * omega);
      values['L_shunt'] = L_sh;
      steps.add(r'L_{shunt} = ' + toLatexScientific(L_sh, digits: 3) + r'\;\mathrm{H}');
    }

    // L2 Calculation
    if (X_net2 > 0) {
      double L2 = X_net2 / omega;
      values['L_series2'] = L2;
      steps.add(r'L_2 = \frac{X_{s2} - X_{load}}{\omega} = ' + toLatexScientific(L2, digits: 3) + r'\;\mathrm{H}');
    } else {
      double C2 = -1 / (X_net2 * omega);
      values['C_series2'] = C2;
      steps.add(r'C_2 (\text{Neg. L}) = ' + toLatexScientific(C2, digits: 3) + r'\;\mathrm{F}');
    }

    // ================= 6. 生成史密斯图路径 =================
    // Path 1: Series 1 (Z_Init + jX_net1) -> Z_mid1
    Complex zMid1 = zS + Complex(0, X_net1);
    paths.add(SmithPath(
        startGamma: _zToGamma(zS),
        endGamma: _zToGamma(zMid1),
        type: PathType.series, // 蓝色
        label: "Series 1"
    ));

    // Path 2: Shunt (Y_mid1 + jB_total) -> Z_mid2
    // 注意: T网络的并联臂在中间，且 B_total 是两个部分之和
    Complex yMid1 = Complex(1,0) / zMid1;
    Complex yMid2 = yMid1 + Complex(0, B_total);
    Complex zMid2 = Complex(1,0) / yMid2;

    paths.add(SmithPath(
        startGamma: _zToGamma(zMid1),
        endGamma: _zToGamma(zMid2),
        type: PathType.shunt, // 橙色
        label: "Shunt"
    ));

    // Path 3: Series 2 (Z_mid2 + jX_net2) -> Target
    // 理论上终点应该是 zL (匹配源到负载)
    paths.add(SmithPath(
        startGamma: _zToGamma(zMid2),
        endGamma: _zToGamma(zL),
        type: PathType.series, // 蓝色
        label: "Series 2"
    ));

    return TMatchingResult(
      values: values,
      steps: steps,
      topology: "Low Pass (T Type)",
      paths: paths,
    );
  }

  static Complex _zToGamma(Complex z) {
    if (z.real.isInfinite || z.abs() > 1e6) return Complex(1,0);
    return (z - Complex(50,0)) / (z + Complex(50,0));
  }
}