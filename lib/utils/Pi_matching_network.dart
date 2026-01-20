import 'dart:math';
import 'package:complex/complex.dart';
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart';

class PiMatchingResult {
  final Map<String, double> values;
  final List<String> steps;
  final String topology;
  final List<SmithPath> paths;

  PiMatchingResult({
    required this.values,
    required this.steps,
    required this.topology,
    required this.paths,
  });
}

class PiMatchingCalculator {

  static PiMatchingResult calculatePiMatching(ImpedanceData data, {double? userQ}) {
    List<String> steps = [];
    Map<String, double> values = {};
    List<SmithPath> paths = [];

    // 1. 数据准备
    double f = data.frequency;
    double omega = 2 * pi * f;
    Complex zS = data.zOriginal ?? Complex(50, 0);
    Complex zL = data.zTarget ?? Complex(50, 0);
    Complex yS = Complex(1, 0) / zS;
    Complex yL = Complex(1, 0) / zL;

    steps.add(r'\textbf{Step 1. Analyze Admittances:}');
    steps.add(r'\text{Pi-Network works with parallel nodes, so we convert Z to Y:}');
    steps.add(r'Y_{ori} = 1/Z_{ori} = ' + outputNum(yS, precision: 4) + r'\;\mathrm{S}');
    steps.add(r'Y_{tar} = 1/Z_{tar} = ' + outputNum(yL, precision: 4) + r'\;\mathrm{S}');

    // 2. Q 值与 Rv 计算 (详细教学版)
    double RpS = 1 / yS.real;
    double RpL = 1 / yL.real;
    double R_high = max(RpS, RpL);
    double R_low = min(RpS, RpL);

    // 计算临界 Q
    double qMin = sqrt(max(0, R_high / R_low - 1));

    steps.add(r'\textbf{Step 2. Determine Q Factor & Virtual Resistor:}');
    steps.add(r'\text{To form a Pi-network, the intermediate Virtual Resistor } R_v \text{ must be smaller than both } R_{src} \text{ and } R_{load}.');
    steps.add(r'\text{Minimum Q required: } Q_{min} = \sqrt{\frac{R_{high}}{R_{low}} - 1} = \sqrt{\frac{' + outputNum(R_high, precision: 1) + '}{' + outputNum(R_low, precision: 1) + '} - 1} = ' + outputNum(qMin, precision: 2));

    double Q = userQ ?? (qMin < 1.0 ? 2.0 : qMin + 1.0);
    if (Q < qMin) {
      Q = qMin + 0.1;
      steps.add(r'\color{red}\text{User Q is too low. Adjusted to } ' + outputNum(Q, precision: 2));
    } else {
      steps.add(r'\text{Selected Q: } \mathbf{Q = ' + outputNum(Q, precision: 2) + r'}');
    }

    // Rv 计算
    double Rv = R_high / (pow(Q, 2) + 1);
    steps.add(r'\text{Calculate Virtual Resistor } R_v:');
    steps.add(r'R_v = \frac{R_{high}}{Q^2 + 1} = \frac{' + outputNum(R_high, precision: 1) + '}{' + outputNum(Q, precision: 2) + '^2 + 1} = \\mathbf{' + outputNum(Rv, precision: 2) + r'\;\Omega}');

    // 3. 计算理想电抗
    double Q_L = sqrt(max(0, RpS / Rv - 1));
    double Bp1_ideal = Q_L / RpS;
    double Xs1_ideal = Q_L * Rv;

    double Q_R = sqrt(max(0, RpL / Rv - 1));
    double Bp2_ideal = Q_R / RpL;
    double Xs2_ideal = Q_R * Rv;

    // 4. 去嵌入与元件值计算 (Low Pass)
    double B_src = yS.imaginary;
    double B_net1 = Bp1_ideal - B_src;

    double B_load = yL.imaginary;
    double B_net2 = Bp2_ideal - B_load;

    double X_series_total = Xs1_ideal + Xs2_ideal;

    steps.add(r'\textbf{Step 3. Calculate Components (De-embedding):}');
    steps.add(r'\text{Subtract parasitic source/load susceptance from ideal values.}');

    // C1 Calculation details
    String c1Eq = "";
    if (B_net1 > 0) {
      double C1 = B_net1 / omega;
      values['C_shunt1'] = C1;
      // 限制小数位 digits: 3
      c1Eq = r'C_1 = \frac{B_{ideal} - B_{src}}{\omega} = ' + toLatexScientific(C1, digits: 3) + r'\;\mathrm{F}';
    } else {
      double L1 = -1 / (B_net1 * omega);
      values['L_shunt1'] = L1;
      c1Eq = r'L_1 = \frac{-1}{(B_{ideal} - B_{src})\omega} = ' + toLatexScientific(L1, digits: 3) + r'\;\mathrm{H}';
    }
    steps.add(c1Eq);

    // L2 (Series) details
    String serEq = "";
    if (X_series_total > 0) {
      double L2 = X_series_total / omega;
      values['L_series'] = L2;
      serEq = r'L_{series} = \frac{X_{s1} + X_{s2}}{\omega} = ' + toLatexScientific(L2, digits: 3) + r'\;\mathrm{H}';
    } else {
      double C2 = -1 / (X_series_total * omega);
      values['C_series'] = C2;
      serEq = r'C_{series} = ' + toLatexScientific(C2, digits: 3) + r'\;\mathrm{F}';
    }
    steps.add(serEq);

    // C3 details
    String c2Eq = "";
    if (B_net2 > 0) {
      double C3 = B_net2 / omega;
      values['C_shunt2'] = C3;
      c2Eq = r'C_2 = \frac{B_{ideal} - B_{load}}{\omega} = ' + toLatexScientific(C3, digits: 3) + r'\;\mathrm{F}';
    } else {
      double L3 = -1 / (B_net2 * omega);
      values['L_shunt2'] = L3;
      c2Eq = r'L_2 = ' + toLatexScientific(L3, digits: 3) + r'\;\mathrm{H}';
    }
    steps.add(c2Eq);

    // 5. 生成史密斯图路径
    Complex yMid1 = yS + Complex(0, B_net1);
    Complex zMid1 = Complex(1, 0) / yMid1;
    paths.add(SmithPath(startGamma: _zToGamma(zS), endGamma: _zToGamma(zMid1), type: PathType.shunt, label: "Input Shunt"));

    Complex zMid2 = zMid1 + Complex(0, X_series_total);
    paths.add(SmithPath(startGamma: _zToGamma(zMid1), endGamma: _zToGamma(zMid2), type: PathType.series, label: "Series"));

    paths.add(SmithPath(startGamma: _zToGamma(zMid2), endGamma: _zToGamma(zL), type: PathType.shunt, label: "Output Shunt"));

    return PiMatchingResult(
      values: values,
      steps: steps,
      topology: "Low Pass (Pi Type)",
      paths: paths,
    );
  }

  static Complex _zToGamma(Complex z) {
    if (z.real.isInfinite || z.abs() > 1e6) return Complex(1,0);
    return (z - Complex(50, 0)) / (z + Complex(50, 0));
  }
}