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
  // LaTeX-safe helpers (Math.tex)
  static const double _kEps = 1e-12;

  static String _latexNum(num v, {int digits = 3}) {
    if (v.abs() < 1e-12) return '0';
    return toLatexScientific(v, digits: digits);
  }

  static String _latexComplex(Complex c, {int digits = 4}) {
    final double re = c.real;
    final double im = c.imaginary;
    if (im.abs() < 1e-12) return _latexNum(re, digits: digits);
    if (re.abs() < 1e-12) {
      return '${_latexNum(im, digits: digits)}\\,\\mathrm{j}';
    }
    final String sign = im >= 0 ? '+' : '-';
    return '${_latexNum(re, digits: digits)} $sign ${_latexNum(im.abs(), digits: digits)}\\,\\mathrm{j}';
  }

  static PiMatchingResult calculatePiMatching(ImpedanceData data, {double? userQ}) {
    final List<String> steps = [];
    final Map<String, double> values = {};
    final List<SmithPath> paths = [];

    // ================= 1) Data preparation =================
    final double f = data.frequency;
    final double omega = 2 * pi * f;

    // If Z is not provided, keep the existing fallback to avoid runtime crash.
    // (The UI summary still displays the user's input.)
    final Complex zInit = data.zInitial ?? Complex(50, 0);
    final Complex zTar = data.zTarget ?? Complex(50, 0);

    final Complex yInit = Complex(1, 0) / zInit;
    final Complex yTar = Complex(1, 0) / zTar;

    // ================= Step 1) Problem setup =================
    steps.add(r'\textbf{Step 1. Problem Setup (Pi Network):}');
    steps.add(r'\text{We design a shunt--series--shunt (}\pi\text{-type) matching network at the specified frequency.}');
    steps.add(r'Z_0=' + _latexNum(data.z0, digits: 3) + r'\,\Omega,\quad f=' + _latexNum(f, digits: 3) + r'\,\mathrm{Hz},\quad \omega=2\pi f=' + _latexNum(omega, digits: 3) + r'\,\mathrm{rad/s}.');
    steps.add(r'Z_{\mathrm{init}}=' + _latexComplex(zInit, digits: 4) + r'\,\Omega');
    steps.add(r'Z_{\mathrm{tar}}=' + _latexComplex(zTar, digits: 4) + r'\,\Omega');
    steps.add(r'\text{Unknowns: input shunt }B_1,\ \text{series reactance }X_s,\ \text{output shunt }B_2.');
    steps.add(r'\text{Finally convert }(B_1,\,X_s,\,B_2)\text{ to physical }L/C\text{ values at the design frequency.}');

    // ================= Step 2) Convert to Y =================
    steps.add(r'\textbf{Step 2. Convert to Admittance Domain (Y):}');
    steps.add(r'\text{Shunt elements add directly in admittance, so we compute }Y=1/Z\text{.}');
    steps.add(r'Y_{\mathrm{init}}=\frac{1}{Z_{\mathrm{init}}}=' + _latexComplex(yInit, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'Y_{\mathrm{tar}}=\frac{1}{Z_{\mathrm{tar}}}=' + _latexComplex(yTar, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'\text{Write }Y=G+jB\text{ where }G\text{ is conductance and }B\text{ is susceptance.}');

    // ================= Step 3) Extract Rp levels =================
    final double Ginit = yInit.real;
    final double Binit = yInit.imaginary;
    final double Gtar = yTar.real;
    final double Btar = yTar.imaginary;

    // Guard against impossible cases (purely reactive Y => G=0)
    if (Ginit.abs() < _kEps || Gtar.abs() < _kEps) {
      steps.add(r'\textbf{Step 3. Conclusion: No Solution (Feasibility):}');
      steps.add(r'\text{At least one endpoint has }G\approx 0\text{ in }Y=G+jB. A lossless Pi network needs a finite conductance level to define }R_p=1/G\text{.}');
      return PiMatchingResult(values: {}, steps: steps, topology: 'Infeasible', paths: const []);
    }

    final double RpInit = 1 / Ginit;
    final double RpTar = 1 / Gtar;
    final double Rhigh = max(RpInit, RpTar);
    final double Rlow = min(RpInit, RpTar);

    steps.add(r'\textbf{Step 3. Extract Parallel Resistance Levels:}');
    steps.add(r'G_{\mathrm{init}}=' + _latexNum(Ginit, digits: 4) + r'\,\mathrm{S},\quad B_{\mathrm{init}}=' + _latexNum(Binit, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'G_{\mathrm{tar}}=' + _latexNum(Gtar, digits: 4) + r'\,\mathrm{S},\quad B_{\mathrm{tar}}=' + _latexNum(Btar, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'R_{p,\mathrm{init}}=\frac{1}{G_{\mathrm{init}}}=' + _latexNum(RpInit, digits: 3) + r'\,\Omega');
    steps.add(r'R_{p,\mathrm{tar}}=\frac{1}{G_{\mathrm{tar}}}=' + _latexNum(RpTar, digits: 3) + r'\,\Omega');
    steps.add(r'R_{\mathrm{high}}=' + _latexNum(Rhigh, digits: 3) + r'\,\Omega,\quad R_{\mathrm{low}}=' + _latexNum(Rlow, digits: 3) + r'\,\Omega');

    // ================= Step 4) Choose Q and Rv =================
    final double qMin = sqrt(max(0, Rhigh / Rlow - 1));

    steps.add(r'\textbf{Step 4. Choose Q and Compute the Virtual Resistor }R_v\textbf{:}');
    steps.add(r'\text{Pi matching can be seen as two L-sections back-to-back meeting at an intermediate (virtual) resistance }R_v\text{.}');
    steps.add(r'\text{For a Pi network, we require }R_v<R_{p,\mathrm{init}}\text{ and }R_v<R_{p,\mathrm{tar}}\text{.}');
    steps.add(r'Q_{\min}=\sqrt{\frac{R_{\mathrm{high}}}{R_{\mathrm{low}}}-1}=' + _latexNum(qMin, digits: 3));
    steps.add(r'\text{Select }Q\ge Q_{\min}.\ \text{Higher }Q\text{ typically increases component magnitude and reduces bandwidth.}');

    double Q = userQ ?? (qMin < 1.0 ? 2.0 : qMin + 1.0);
    if (Q < qMin) {
      Q = qMin + 0.1;
      steps.add(r'\color{red}\text{User Q is too low. Adjusted to }' + _latexNum(Q, digits: 3) + r'\text{ to satisfy feasibility.}');
    }
    steps.add(r'Q=\mathbf{' + _latexNum(Q, digits: 3) + r'}');

    final double Rv = Rhigh / (pow(Q, 2) + 1);
    steps.add(r'R_v=\frac{R_{\mathrm{high}}}{Q^2+1}=' + _latexNum(Rv, digits: 3) + r'\,\Omega');

    // ================= Step 5) Ideal prototype values =================
    final double QL = sqrt(max(0, RpInit / Rv - 1));
    final double QR = sqrt(max(0, RpTar / Rv - 1));

    final double Bp1Ideal = QL / RpInit;
    final double Bp2Ideal = QR / RpTar;

    final double Xs1Ideal = QL * Rv;
    final double Xs2Ideal = QR * Rv;
    final double Xseries = Xs1Ideal + Xs2Ideal;

    steps.add(r'\textbf{Step 5. Ideal Pi Prototype (Before De-embedding):}');
    steps.add(r'\text{Left side (init) and right side (tar) each forms one L-section to the same }R_v\text{.}');
    steps.add(r'Q_L=\sqrt{\frac{R_{p,\mathrm{init}}}{R_v}-1}=' + _latexNum(QL, digits: 3));
    steps.add(r'B_{p1,\mathrm{ideal}}=\frac{Q_L}{R_{p,\mathrm{init}}}=' + _latexNum(Bp1Ideal, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'X_{s1,\mathrm{ideal}}=Q_L R_v=' + _latexNum(Xs1Ideal, digits: 3) + r'\,\Omega');
    steps.add(r'Q_R=\sqrt{\frac{R_{p,\mathrm{tar}}}{R_v}-1}=' + _latexNum(QR, digits: 3));
    steps.add(r'B_{p2,\mathrm{ideal}}=\frac{Q_R}{R_{p,\mathrm{tar}}}=' + _latexNum(Bp2Ideal, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'X_{s2,\mathrm{ideal}}=Q_R R_v=' + _latexNum(Xs2Ideal, digits: 3) + r'\,\Omega');
    steps.add(r'X_s=X_{s1,\mathrm{ideal}}+X_{s2,\mathrm{ideal}}=' + _latexNum(Xseries, digits: 3) + r'\,\Omega');

    // ================= Step 6) De-embedding =================
    final double B1 = Bp1Ideal - Binit;
    final double B2 = Bp2Ideal - Btar;

    steps.add(r'\textbf{Step 6. De-embedding Endpoint Susceptance:}');
    steps.add(r'\text{The endpoints already contain susceptance }B_{\mathrm{init}}\text{ and }B_{\mathrm{tar}}\text{ in their admittances.}');
    steps.add(r'\text{Therefore the shunt elements should supply only the remaining part:}');
    steps.add(r'B_1=B_{p1,\mathrm{ideal}}-B_{\mathrm{init}}=' + _latexNum(B1, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'B_2=B_{p2,\mathrm{ideal}}-B_{\mathrm{tar}}=' + _latexNum(B2, digits: 4) + r'\,\mathrm{S}');

    // ================= Step 7) Convert to L/C =================
    steps.add(r'\textbf{Step 7. Convert }(B_1,\,X_s,\,B_2)\textbf{ to Physical Components:}');
    steps.add(r'\text{Rules: for shunt }B,\ B>0\Rightarrow C=\frac{B}{\omega},\ B<0\Rightarrow L=\frac{-1}{B\omega}.');
    steps.add(r'\text{For series }X_s,\ X_s>0\Rightarrow L=\frac{X_s}{\omega},\ X_s<0\Rightarrow C=\frac{-1}{X_s\omega}.');

    // --- Input shunt element ---
    if (B1.abs() < _kEps) {
      steps.add(r'B_1\approx 0\ \Rightarrow\ \text{No input shunt element required.}');
    } else if (B1 > 0) {
      final double C1 = B1 / omega;
      values['C_shunt1'] = C1;
      steps.add(r'C_1=\frac{B_1}{\omega}=' + _latexNum(C1, digits: 4) + r'\,\mathrm{F}');
    } else {
      final double L1 = -1 / (B1 * omega);
      values['L_shunt1'] = L1;
      steps.add(r'L_1=\frac{-1}{B_1\omega}=' + _latexNum(L1, digits: 4) + r'\,\mathrm{H}');
    }

    // --- Series element ---
    if (Xseries.abs() < _kEps) {
      steps.add(r'X_s\approx 0\ \Rightarrow\ \text{No series element required.}');
    } else if (Xseries > 0) {
      final double Ls = Xseries / omega;
      values['L_series'] = Ls;
      steps.add(r'L_{\mathrm{series}}=\frac{X_s}{\omega}=' + _latexNum(Ls, digits: 4) + r'\,\mathrm{H}');
    } else {
      final double Cs = -1 / (Xseries * omega);
      values['C_series'] = Cs;
      steps.add(r'C_{\mathrm{series}}=\frac{-1}{X_s\omega}=' + _latexNum(Cs, digits: 4) + r'\,\mathrm{F}');
    }

    // --- Output shunt element ---
    if (B2.abs() < _kEps) {
      steps.add(r'B_2\approx 0\ \Rightarrow\ \text{No output shunt element required.}');
    } else if (B2 > 0) {
      final double C2 = B2 / omega;
      values['C_shunt2'] = C2;
      steps.add(r'C_2=\frac{B_2}{\omega}=' + _latexNum(C2, digits: 4) + r'\,\mathrm{F}');
    } else {
      final double L2 = -1 / (B2 * omega);
      values['L_shunt2'] = L2;
      steps.add(r'L_2=\frac{-1}{B_2\omega}=' + _latexNum(L2, digits: 4) + r'\,\mathrm{H}');
    }

    // ================= Step 8) Smith chart interpretation =================
    steps.add(r'\textbf{Step 8. Smith Chart Interpretation (How the Point Moves):}');
    steps.add(r'\text{Input shunt changes admittance, moving along a constant-conductance circle in the Y-Smith chart.}');
    steps.add(r'\text{The series element changes impedance, moving along a constant-resistance circle in the Z-Smith chart.}');
    steps.add(r'\text{The output shunt then adjusts the final susceptance so the trajectory lands on the target point.}');

    // ================= Smith chart paths =================
    // Use z0 from user input to ensure the Smith chart trajectory is consistent.
    final double z0 = data.z0;

    // After input shunt: Y_mid1 = Y_init + jB1
    final Complex yMid1 = yInit + Complex(0, B1);
    final Complex zMid1 = Complex(1, 0) / yMid1;
    paths.add(SmithPath(
      startGamma: _zToGamma(zInit, z0),
      endGamma: _zToGamma(zMid1, z0),
      type: PathType.shunt,
      label: 'Input Shunt',
    ));

    // After series: Z_mid2 = Z_mid1 + jX_s
    final Complex zMid2 = zMid1 + Complex(0, Xseries);
    paths.add(SmithPath(
      startGamma: _zToGamma(zMid1, z0),
      endGamma: _zToGamma(zMid2, z0),
      type: PathType.series,
      label: 'Series',
    ));

    // Output shunt shown as shunt path to target (conceptual)
    paths.add(SmithPath(
      startGamma: _zToGamma(zMid2, z0),
      endGamma: _zToGamma(zTar, z0),
      type: PathType.shunt,
      label: 'Output Shunt',
    ));

    return PiMatchingResult(
      values: values,
      steps: steps,
      topology: 'Low Pass (Pi Type)',
      paths: paths,
    );
  }

  static Complex _zToGamma(Complex z, double z0) {
    if (z.real.isInfinite || z.abs() > 1e9) return Complex(1, 0);
    return (z - Complex(z0, 0)) / (z + Complex(z0, 0));
  }
}
