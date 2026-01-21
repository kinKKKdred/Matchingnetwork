import 'dart:math';
import 'package:complex/complex.dart';

// 请确保引入了你的模型和工具类
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart'; // 假设这里有 outputNum 和 toLatexScientific

// 拓扑类型枚举
enum LTopologyType {
  seriesFirst, // 串联后并联
  shuntFirst, // 并联后串联
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
  // ================= LaTeX-safe helpers (for StepCardDisplay / Math.tex) =================
  static const double _kEps = 1e-9;

  static String _latexNum(num v, {int digits = 3}) {
    if (v.abs() < 1e-12) return '0';
    return toLatexScientific(v, digits: digits);
  }

  static String _latexComplex(Complex c, {int digits = 3}) {
    final double re = c.real;
    final double im = c.imaginary;

    if (im.abs() < 1e-12) return _latexNum(re, digits: digits);
    if (re.abs() < 1e-12) return '${_latexNum(im, digits: digits)}\\,\\mathrm{j}';

    final String sign = im >= 0 ? '+' : '-';
    return '${_latexNum(re, digits: digits)} $sign ${_latexNum(im.abs(), digits: digits)}\\,\\mathrm{j}';
  }

  static MatchingResult calculateLMatch(ImpedanceData data) {
    // ================= Scheme 1 (Common steps + all solutions) =================
    final List<String> commonSteps = [];
    Complex zInitial, zTarget;

    final bool hasZ = (data.zInitial != null && data.zTarget != null);
    final bool hasGamma = (data.gammaInitial != null && data.gammaTarget != null);

    // ---------- Step 0 (optional): Γ -> Z ----------
    if (hasZ) {
      zInitial = data.zInitial!;
      zTarget = data.zTarget!;
    } else if (hasGamma) {
      zInitial = gammaToZ(data.gammaInitial!, data.z0);
      zTarget = gammaToZ(data.gammaTarget!, data.z0);

      commonSteps.add(r'\textbf{Step 0. Convert \Gamma to Z:}');
      commonSteps.add(r'Z_{\mathrm{init}} = Z_0 \frac{1+\Gamma_{\mathrm{init}}}{1-\Gamma_{\mathrm{init}}} = ' +
          _latexComplex(zInitial, digits: 4) + r'\,\Omega');
      commonSteps.add(r'Z_{\mathrm{tar}} = Z_0 \frac{1+\Gamma_{\mathrm{tar}}}{1-\Gamma_{\mathrm{tar}}} = ' +
          _latexComplex(zTarget, digits: 4) + r'\,\Omega');
    } else {
      throw Exception('Input incomplete: provide (Zinitial,Ztarget) or (Γinitial,Γtarget).');
    }

    // ---------- Step 1: Problem & Target ----------
    commonSteps.add(r'\textbf{Step 1. Problem \& Target:}');
    commonSteps.add(r'Z_0=' + _latexNum(data.z0, digits: 3) + r'\,\Omega,\quad f=' + _latexNum(data.frequency, digits: 3) + r'\,\mathrm{Hz}');
    commonSteps.add(r'Z_{\mathrm{init}}=' + _latexComplex(zInitial, digits: 4) + r'\,\Omega');
    commonSteps.add(r'Z_{\mathrm{tar}}=' + _latexComplex(zTarget, digits: 4) + r'\,\Omega');

    // ---------- Step 2: Normalize ----------
    final Complex z1 = zInitial / Complex(data.z0, 0); // normalized z_init
    final Complex z2 = zTarget / Complex(data.z0, 0);  // normalized z_tar
    final Complex y1 = Complex(1, 0) / z1;
    final Complex y2 = Complex(1, 0) / z2;

    commonSteps.add(r'\textbf{Step 2. Normalize (z,y):}');
    commonSteps.add(r'z_{\mathrm{init}}=Z_{\mathrm{init}}/Z_0=' + _latexComplex(z1) + r',\quad z_{\mathrm{tar}}=' + _latexComplex(z2));
    commonSteps.add(r'y_{\mathrm{init}}=1/z_{\mathrm{init}}=' + _latexComplex(y1) + r',\quad y_{\mathrm{tar}}=' + _latexComplex(y2));

    // ---------- Step 3: Special case (Already matched) ----------
    if ((zInitial - zTarget).abs() < 0.05) {
      commonSteps.add(r'\textbf{Step 3. Conclusion: Direct connect}');
      commonSteps.add(r'\text{Because } Z_{\mathrm{init}} \approx Z_{\mathrm{tar}}, \text{ no matching components are required.}');

      final LMatchSolution matchedSolution = LMatchSolution(
        title: "No Match Needed",
        topologyType: LTopologyType.seriesFirst, // placeholder
        values: {},
        steps: const [], // keep empty to avoid being treated as "infeasible" by UI
        paths: const [],
        filterType: "Direct Connect",
      );
      return MatchingResult(solutions: [matchedSolution], commonSteps: commonSteps);
    }

    // ---------- Step 4: Feasibility guard (pure reactance -> resistive target) ----------
    const double epsilon = 1e-6;
    if (zInitial.real.abs() < epsilon && zTarget.real.abs() > epsilon) {
      final List<String> errorSteps = [];
      errorSteps.add(r'\textbf{Step 6. Conclusion: No Solution (Feasibility failed)}');
      errorSteps.add(r'\text{Lossless L-networks cannot match a purely reactive start }(R\approx0)\text{ to a resistive target }(R>0).');

      final LMatchSolution errorSolution = LMatchSolution(
        title: "Infeasible Case",
        topologyType: LTopologyType.seriesFirst,
        values: {},
        steps: errorSteps,
        paths: const [],
        filterType: "No Solution",
      );
      return MatchingResult(solutions: [errorSolution], commonSteps: commonSteps);
    }

    // ---------- Step 3: Strategy ----------
    commonSteps.add(r'\textbf{Step 3. Strategy (two topologies):}');
    commonSteps.add(r'\text{Try both: Series}\rightarrow\text{Shunt and Shunt}\rightarrow\text{Series.}');
    commonSteps.add(r'\text{We pick an intermediate point where the real part matches, then cancel the imaginary part.}');

    // ---------- Step 4: Intermediate conditions ----------
    commonSteps.add(r'\textbf{Step 4. Intermediate conditions:}');
    commonSteps.add(r'\text{Series}\rightarrow\text{Shunt: choose } z_{\mathrm{mid}}=r_1+jx \text{ such that } \Re(1/z_{\mathrm{mid}})=\Re(y_{\mathrm{tar}}).');
    commonSteps.add(r'\text{Shunt}\rightarrow\text{Series: choose } y_{\mathrm{mid}}=g_1+jb \text{ such that } \Re(1/y_{\mathrm{mid}})=\Re(z_{\mathrm{tar}}).');

    // ---------- Step 5: Root count & feasibility ----------
    commonSteps.add(r'\textbf{Step 5. Root count (two / single / none):}');

    // We'll store temporary results with metadata, then assign titles at the end.
    final List<Map<String, dynamic>> temp = [];

    // --- Topology A: Series -> Shunt ---
    final double r1 = z1.real;
    final double g2 = y2.real;
    double discSeries = -1;
    if (g2.abs() >= _kEps) {
      discSeries = r1 / g2 - r1 * r1;
    }

    if (discSeries >= -1e-9) {
      final double xMidBase = sqrt(max(0, discSeries));
      commonSteps.add(
          xMidBase <= 1e-9
              ? (r'\text{Series}\rightarrow\text{Shunt: } \Delta_s=' + _latexNum(discSeries) + r'\Rightarrow \text{single solution.}')
              : (r'\text{Series}\rightarrow\text{Shunt: } \Delta_s=' + _latexNum(discSeries) + r'\Rightarrow \text{two solutions.}')
      );

      final solP = _calculateSingleSolution(
        data: data,
        z1: z1,
        z2: z2,
        topology: LTopologyType.seriesFirst,
        rootValue: xMidBase,
        isPositiveRoot: true,
      );
      temp.add({'sol': solP, 'root': xMidBase});

      if (xMidBase > 1e-9) {
        final solN = _calculateSingleSolution(
          data: data,
          z1: z1,
          z2: z2,
          topology: LTopologyType.seriesFirst,
          rootValue: -xMidBase,
          isPositiveRoot: false,
        );
        temp.add({'sol': solN, 'root': -xMidBase});
      }
    } else {
      commonSteps.add(r'\text{Series}\rightarrow\text{Shunt: } \Delta_s=' + _latexNum(discSeries) + r'\Rightarrow \text{no real solution.}');
    }

    // --- Topology B: Shunt -> Series ---
    final double g1 = y1.real;
    final double r2 = z2.real;
    double discShunt = -1;
    if (r2.abs() >= _kEps) {
      discShunt = g1 / r2 - g1 * g1;
    }

    if (discShunt >= -1e-9) {
      final double bMidBase = sqrt(max(0, discShunt));
      commonSteps.add(
          bMidBase <= 1e-9
              ? (r'\text{Shunt}\rightarrow\text{Series: } \Delta_p=' + _latexNum(discShunt) + r'\Rightarrow \text{single solution.}')
              : (r'\text{Shunt}\rightarrow\text{Series: } \Delta_p=' + _latexNum(discShunt) + r'\Rightarrow \text{two solutions.}')
      );

      final solP = _calculateSingleSolution(
        data: data,
        z1: z1,
        z2: z2,
        topology: LTopologyType.shuntFirst,
        rootValue: bMidBase,
        isPositiveRoot: true,
      );
      temp.add({'sol': solP, 'root': bMidBase});

      if (bMidBase > 1e-9) {
        final solN = _calculateSingleSolution(
          data: data,
          z1: z1,
          z2: z2,
          topology: LTopologyType.shuntFirst,
          rootValue: -bMidBase,
          isPositiveRoot: false,
        );
        temp.add({'sol': solN, 'root': -bMidBase});
      }
    } else {
      commonSteps.add(r'\text{Shunt}\rightarrow\text{Series: } \Delta_p=' + _latexNum(discShunt) + r'\Rightarrow \text{no real solution.}');
    }

    // ---------- No solution ----------
    if (temp.isEmpty) {
      final List<String> errorSteps = [];
      errorSteps.add(r'\textbf{Step 6. Conclusion: No Solution}');
      errorSteps.add(r'\text{Both topologies yield no real intermediate point under lossless L-network constraints.}');

      final LMatchSolution errorSolution = LMatchSolution(
        title: "Infeasible Case",
        topologyType: LTopologyType.seriesFirst,
        values: {},
        steps: errorSteps,
        paths: const [],
        filterType: "No Solution",
      );
      return MatchingResult(solutions: [errorSolution], commonSteps: commonSteps);
    }

    // ---------- Assign titles + filter types ----------
    final List<LMatchSolution> solutions = [];
    for (int i = 0; i < temp.length; i++) {
      final LMatchSolution sol = temp[i]['sol'] as LMatchSolution;
      final double root = temp[i]['root'] as double;

      final String topoName = sol.topologyType == LTopologyType.seriesFirst ? "Series→Shunt" : "Shunt→Series";
      final String rootLabel = (root.abs() <= 1e-9) ? "(single)" : (root > 0 ? "(+root)" : "(-root)");

      solutions.add(LMatchSolution(
        title: "Solution ${i + 1}: $topoName $rootLabel",
        topologyType: sol.topologyType,
        values: sol.values,
        steps: sol.steps,
        paths: sol.paths,
        filterType: _guessFilterType(sol.values),
      ));
    }

    return MatchingResult(solutions: solutions, commonSteps: commonSteps);
  }

  static LMatchSolution _calculateSingleSolution({
    required ImpedanceData data,
    required Complex z1,
    required Complex z2,
    required LTopologyType topology,
    required double rootValue, // Series-first: x_mid; Shunt-first: b_mid
    required bool isPositiveRoot,
  }) {
    final List<String> steps = [];
    final List<SmithPath> smithPaths = [];
    final Map<String, double> componentValues = {};

    // For verification (absolute impedances)
    final Complex Zinit = z1 * Complex(data.z0, 0);
    final Complex Ztar = z2 * Complex(data.z0, 0);

    double Xs_norm = 0.0; // normalized series reactance x_s
    double B_norm = 0.0; // normalized shunt susceptance b_p
    double Xs_real = 0.0; // ohms
    double Xp_real = 0.0; // ohms (equivalent shunt reactance)

    Complex zMid;

    if (topology == LTopologyType.seriesFirst) {
      // ================= Step 6 =================
      steps.add(r'\textbf{Step 6. Topology (Solution): Series}\rightarrow\text{Shunt}');
      steps.add(r'\text{Series element acts in }z\text{-domain; shunt element acts in }y\text{-domain.}');

      // Intermediate point: z_mid = r1 + j x_mid
      final double r1 = z1.real;
      final double xMid = rootValue;
      zMid = Complex(r1, xMid);
      final Complex yMid = Complex(1, 0) / zMid;
      final Complex yTar = Complex(1, 0) / z2;

      // ================= Step 7 =================
      steps.add(r'\textbf{Step 7. Intermediate point:}');
      steps.add(r'x_{\mathrm{mid}}=' + _latexNum(xMid));
      steps.add(r'z_{\mathrm{mid}}=' + _latexComplex(zMid) + r',\quad y_{\mathrm{mid}}=1/z_{\mathrm{mid}}=' + _latexComplex(yMid));
      steps.add(r'\Re(y_{\mathrm{mid}})\approx \Re(y_{\mathrm{tar}})=' + _latexNum(yTar.real));

      // ================= Step 8 =================
      steps.add(r'\textbf{Step 8. Series element (}z_{\mathrm{init}}\rightarrow z_{\mathrm{mid}}\text{):}');
      final Complex diff = zMid - z1;
      Xs_norm = diff.imaginary;
      Xs_real = Xs_norm * data.z0;

      if (Xs_norm.abs() < _kEps) {
        steps.add(r'x_s\approx 0 \Rightarrow \text{series element not required.}');
      } else {
        steps.add(r'x_s=\Im(z_{\mathrm{mid}}-z_{\mathrm{init}})=' + _latexNum(Xs_norm));
        steps.add(r'X_s=x_s Z_0=' + _latexNum(Xs_real, digits: 4) + r'\,\Omega');

        smithPaths.add(SmithPath(
          startGamma: zToGamma(z1),
          endGamma: zToGamma(zMid),
          type: PathType.series,
          label: Xs_real > 0 ? "L_ser" : "C_ser",
        ));
      }

      // ================= Step 9 =================
      steps.add(r'\textbf{Step 9. Shunt element (}z_{\mathrm{mid}}\rightarrow z_{\mathrm{tar}}\text{):}');
      final Complex yDiff = yTar - yMid;
      B_norm = yDiff.imaginary;

      if (B_norm.abs() < _kEps) {
        steps.add(r'b_p\approx 0 \Rightarrow \text{shunt element not required.}');
        Xp_real = 0.0;
      } else {
        // Xp_real = -Z0 / b_norm  (equivalent shunt reactance in ohms)
        Xp_real = -data.z0 / B_norm;
        steps.add(r'b_p=\Im(y_{\mathrm{tar}}-y_{\mathrm{mid}})=' + _latexNum(B_norm));
        steps.add(r'X_p=-Z_0/b_p=' + _latexNum(Xp_real, digits: 4) + r'\,\Omega');

        smithPaths.add(SmithPath(
          startGamma: zToGamma(zMid),
          endGamma: zToGamma(z2),
          type: PathType.shunt,
          label: Xp_real > 0 ? "L_sh" : "C_sh",
        ));
      }

      // ================= Step 11 (Smith summary) =================
      steps.add(r'\textbf{Step 11. Smith-chart actions (summary):}');
      steps.add(r'\text{(1) Series: move on constant }r\text{ circle in }z\text{-chart.}');
      steps.add(r'\text{(2) Shunt: move on constant }g\text{ circle in }y\text{-chart.}');
    } else {
      // ================= Step 6 =================
      steps.add(r'\textbf{Step 6. Topology (Solution): Shunt}\rightarrow\text{Series}');
      steps.add(r'\text{Shunt element acts in }y\text{-domain; series element acts in }z\text{-domain.}');

      final Complex yInit = Complex(1, 0) / z1;
      final double g1 = yInit.real;
      final double bMid = rootValue;

      // Intermediate point: y_mid = g1 + j b_mid, then z_mid = 1/y_mid
      final Complex yMid = Complex(g1, bMid);
      zMid = Complex(1, 0) / yMid;

      // ================= Step 7 =================
      steps.add(r'\textbf{Step 7. Intermediate point:}');
      steps.add(r'b_{\mathrm{mid}}=' + _latexNum(bMid));
      steps.add(r'y_{\mathrm{mid}}=' + _latexComplex(yMid) + r',\quad z_{\mathrm{mid}}=1/y_{\mathrm{mid}}=' + _latexComplex(zMid));
      steps.add(r'\Re(z_{\mathrm{mid}})\approx \Re(z_{\mathrm{tar}})=' + _latexNum(z2.real));

      // ================= Step 8 =================
      steps.add(r'\textbf{Step 8. Shunt element (}y_{\mathrm{init}}\rightarrow y_{\mathrm{mid}}\text{):}');
      final Complex yDiff = yMid - yInit;
      B_norm = yDiff.imaginary;

      if (B_norm.abs() < _kEps) {
        steps.add(r'b_p\approx 0 \Rightarrow \text{shunt element not required.}');
        Xp_real = 0.0;
      } else {
        Xp_real = -data.z0 / B_norm;
        steps.add(r'b_p=\Im(y_{\mathrm{mid}}-y_{\mathrm{init}})=' + _latexNum(B_norm));
        steps.add(r'X_p=-Z_0/b_p=' + _latexNum(Xp_real, digits: 4) + r'\,\Omega');

        smithPaths.add(SmithPath(
          startGamma: zToGamma(z1),
          endGamma: zToGamma(zMid),
          type: PathType.shunt,
          label: Xp_real > 0 ? "L_sh" : "C_sh",
        ));
      }

      // ================= Step 9 =================
      steps.add(r'\textbf{Step 9. Series element (}z_{\mathrm{mid}}\rightarrow z_{\mathrm{tar}}\text{):}');
      final Complex zDiff = z2 - zMid;
      Xs_norm = zDiff.imaginary;
      Xs_real = Xs_norm * data.z0;

      if (Xs_norm.abs() < _kEps) {
        steps.add(r'x_s\approx 0 \Rightarrow \text{series element not required.}');
      } else {
        steps.add(r'x_s=\Im(z_{\mathrm{tar}}-z_{\mathrm{mid}})=' + _latexNum(Xs_norm));
        steps.add(r'X_s=x_s Z_0=' + _latexNum(Xs_real, digits: 4) + r'\,\Omega');

        smithPaths.add(SmithPath(
          startGamma: zToGamma(zMid),
          endGamma: zToGamma(z2),
          type: PathType.series,
          label: Xs_real > 0 ? "L_ser" : "C_ser",
        ));
      }

      // ================= Step 11 (Smith summary) =================
      steps.add(r'\textbf{Step 11. Smith-chart actions (summary):}');
      steps.add(r'\text{(1) Shunt: move on constant }g\text{ circle in }y\text{-chart.}');
      steps.add(r'\text{(2) Series: move on constant }r\text{ circle in }z\text{-chart.}');
    }

    // ================= Step 10 =================
    steps.add(r'\textbf{Step 10. Convert reactance to L/C values:}');
    _calculateComponentValuesDetailed(steps, Xs_real, Xp_real, data.frequency, componentValues);

    // ================= Step 12 (verification) =================
    steps.add(r'\textbf{Step 12. Verification:}');
    Complex Zout;

    if (topology == LTopologyType.seriesFirst) {
      // Series then shunt
      final Complex ZmidAbs = Zinit + Complex(0, Xs_real);
      if (Xp_real.abs() < _kEps) {
        Zout = ZmidAbs;
      } else {
        final Complex YmidAbs = Complex(1, 0) / ZmidAbs;
        final double B = -1.0 / Xp_real; // since Xp = -1/B
        final Complex YoutAbs = YmidAbs + Complex(0, B);
        Zout = Complex(1, 0) / YoutAbs;
      }
    } else {
      // Shunt then series
      Complex ZmidAbs;
      if (Xp_real.abs() < _kEps) {
        ZmidAbs = Zinit;
      } else {
        final Complex YinitAbs = Complex(1, 0) / Zinit;
        final double B = -1.0 / Xp_real;
        final Complex YmidAbs = YinitAbs + Complex(0, B);
        ZmidAbs = Complex(1, 0) / YmidAbs;
      }
      Zout = ZmidAbs + Complex(0, Xs_real);
    }

    final double err = (Zout - Ztar).abs();
    steps.add(r'Z_{\mathrm{out}}=' + _latexComplex(Zout, digits: 4) + r'\,\Omega');
    steps.add(r'|Z_{\mathrm{out}}-Z_{\mathrm{tar}}|=' + _latexNum(err, digits: 3) + r'\,\Omega');

    return LMatchSolution(
      title: "Temp Title",
      topologyType: topology,
      values: componentValues,
      steps: steps,
      paths: smithPaths,
    );
  }

  static String _guessFilterType(Map<String, double> values) {
    bool hasSeriesL = values.containsKey("Series Inductance (H)");
    bool hasSeriesC = values.containsKey("Series Capacitance (F)");
    bool hasShuntL = values.containsKey("Shunt Inductance (H)");
    bool hasShuntC = values.containsKey("Shunt Capacitance (F)");

    if ((hasSeriesL || hasSeriesC) && (hasShuntL || hasShuntC)) {
      if (hasSeriesL && hasShuntC) return "Low-pass";
      if (hasSeriesC && hasShuntL) return "High-pass";
      if (hasSeriesL && hasShuntL) return "Band-stop";
      if (hasSeriesC && hasShuntC) return "Band-pass";
    }
    return "Unknown";
  }

  static void _calculateComponentValuesDetailed(
      List<String> steps, double Xs, double Xp, double f, Map<String, double> values) {
    final double omega = 2 * pi * f;
    steps.add(r'\omega=2\pi f=' + _latexNum(omega, digits: 3) + r'\,\mathrm{rad/s}');

    // ----- Series element -----
    if (Xs.abs() < 1e-9) {
      steps.add(r'\text{Series: } X_s\approx 0 \Rightarrow \text{not required.}');
    } else if (Xs > 0) {
      final double L = Xs / omega;
      values["Series Inductance (H)"] = L;
      steps.add(r'\text{Series (inductor): } L_s=X_s/\omega=' + toLatexScientific(L, digits: 3) + r'\,\mathrm{H}');
    } else {
      final double C = -1.0 / (omega * Xs);
      values["Series Capacitance (F)"] = C;
      steps.add(r'\text{Series (capacitor): } C_s=-1/(\omega X_s)=' + toLatexScientific(C, digits: 3) + r'\,\mathrm{F}');
    }

    // ----- Shunt element -----
    if (Xp.abs() < 1e-9) {
      steps.add(r'\text{Shunt: } X_p\approx 0 \Rightarrow \text{not required.}');
    } else if (Xp > 0) {
      final double L = Xp / omega;
      values["Shunt Inductance (H)"] = L;
      steps.add(r'\text{Shunt (inductor): } L_p=X_p/\omega=' + toLatexScientific(L, digits: 3) + r'\,\mathrm{H}');
    } else {
      final double C = -1.0 / (omega * Xp);
      values["Shunt Capacitance (F)"] = C;
      steps.add(r'\text{Shunt (capacitor): } C_p=-1/(\omega X_p)=' + toLatexScientific(C, digits: 3) + r'\,\mathrm{F}');
    }
  }

  static Complex zToGamma(Complex z) {
    if (z.real.isInfinite) return Complex(1, 0);
    if (z.abs() > 1e9) return Complex(1, 0);
    return (z - Complex(1, 0)) / (z + Complex(1, 0));
  }

  static Complex gammaToZ(Complex gamma, double z0) {
    if ((Complex(1, 0) - gamma).abs() < 1e-9) return Complex(1e9, 0);
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma) * Complex(z0, 0);
  }
}
