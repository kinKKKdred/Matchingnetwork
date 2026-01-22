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

  static TMatchingResult calculateTMatching(ImpedanceData data, {double? userQ}) {
    final List<String> steps = [];
    final Map<String, double> values = {};
    final List<SmithPath> paths = [];

    // ================= 1) Data preparation =================
    final double f = data.frequency;
    final double omega = 2 * pi * f;

    // If Z is not provided, keep the existing fallback to avoid runtime crash.
    final Complex zInit = data.zInitial ?? Complex(50, 0);
    final Complex zTar = data.zTarget ?? Complex(50, 0);

    final double Rinit = zInit.real;
    final double Xinit = zInit.imaginary;
    final double Rtar = zTar.real;
    final double Xtar = zTar.imaginary;

    // ================= Step 1) Problem setup =================
    steps.add(r'\textbf{Step 1. Problem Setup (T Network):}');
    steps.add(r'\text{We design a series--shunt--series (T-type) matching network at the specified frequency.}');
    steps.add(r'Z_0=' + _latexNum(data.z0, digits: 3) + r'\,\Omega,\quad f=' + _latexNum(f, digits: 3) + r'\,\mathrm{Hz},\quad \omega=2\pi f=' + _latexNum(omega, digits: 3) + r'\,\mathrm{rad/s}.');
    steps.add(r'Z_{\mathrm{init}}=' + _latexComplex(zInit, digits: 4) + r'\,\Omega');
    steps.add(r'Z_{\mathrm{tar}}=' + _latexComplex(zTar, digits: 4) + r'\,\Omega');
    steps.add(r'\text{Unknowns: input series reactance }X_1,\ \text{middle shunt susceptance }B,\ \text{output series reactance }X_2.');

    // Feasibility guard: resistances must be positive for lossless matching prototypes.
    if (Rinit <= _kEps || Rtar <= _kEps) {
      steps.add(r'\textbf{Step 2. Conclusion: No Solution (Feasibility):}');
      steps.add(r'\text{At least one endpoint has }R\le 0\text{. A lossless T network requires positive resistance levels to define a valid matching prototype.}');
      return TMatchingResult(values: {}, steps: steps, topology: 'Infeasible', paths: const []);
    }

    // ================= Step 2) Separate R and X =================
    steps.add(r'\textbf{Step 2. Separate Resistance and Reactance:}');
    steps.add(r'Z_{\mathrm{init}}=R_{\mathrm{init}}+jX_{\mathrm{init}},\quad Z_{\mathrm{tar}}=R_{\mathrm{tar}}+jX_{\mathrm{tar}}');
    steps.add(r'R_{\mathrm{init}}=' + _latexNum(Rinit, digits: 4) + r'\,\Omega,\quad X_{\mathrm{init}}=' + _latexNum(Xinit, digits: 4) + r'\,\Omega');
    steps.add(r'R_{\mathrm{tar}}=' + _latexNum(Rtar, digits: 4) + r'\,\Omega,\quad X_{\mathrm{tar}}=' + _latexNum(Xtar, digits: 4) + r'\,\Omega');
    steps.add(r'\text{T network is the dual of the Pi network: series elements add in impedance, so we work in }Z\text{-domain first.}');

    // ================= Step 3) Choose Q and Rv =================
    final double Rhigh = max(Rinit, Rtar);
    final double Rlow = min(Rinit, Rtar);
    final double qMin = sqrt(max(0, Rhigh / Rlow - 1));

    steps.add(r'\textbf{Step 3. Choose Q and Compute the Virtual Resistance }R_v\textbf{:}');
    steps.add(r'\text{T matching can be seen as two L-sections meeting at a high intermediate resistance }R_v\text{.}');
    steps.add(r'\text{For a T network, we require }R_v>R_{\mathrm{init}}\text{ and }R_v>R_{\mathrm{tar}}\text{.}');
    steps.add(r'Q_{\min}=\sqrt{\frac{R_{\mathrm{high}}}{R_{\mathrm{low}}}-1}=' + _latexNum(qMin, digits: 3));
    steps.add(r'\text{Select }Q\ge Q_{\min}.\ \text{Higher }Q\text{ typically increases component magnitude and reduces bandwidth.}');

    double Q = userQ ?? (qMin < 1.0 ? 2.0 : qMin + 1.0);
    if (Q < qMin) {
      Q = qMin + 0.1;
      steps.add(r'\color{red}\text{User Q is too low. Adjusted to }' + _latexNum(Q, digits: 3) + r'\text{ to satisfy feasibility.}');
    }
    steps.add(r'Q=\mathbf{' + _latexNum(Q, digits: 3) + r'}');

    double Rv = Rlow * (pow(Q, 2) + 1);
    if (Rv <= Rhigh) {
      // Safety: ensure strictly larger than both resistances.
      Rv = Rhigh * 1.05;
    }
    steps.add(r'R_v=R_{\mathrm{low}}(Q^2+1)=' + _latexNum(Rv, digits: 3) + r'\,\Omega');

    // ================= Step 4) Left side L-section =================
    final double QL = sqrt(max(0, Rv / Rinit - 1));
    final double Xs1Ideal = QL * Rinit;
    final double Bp1Ideal = (Rv.abs() < _kEps) ? 0.0 : (QL / Rv); // S

    steps.add(r'\textbf{Step 4. Left Side Prototype (Init }\to R_v\textbf{):}');
    steps.add(r'\text{We first transform }R_{\mathrm{init}}\text{ up to }R_v\text{ using a single L-section.}');
    steps.add(r'Q_L=\sqrt{\frac{R_v}{R_{\mathrm{init}}}-1}=' + _latexNum(QL, digits: 3));
    steps.add(r'X_{s1,\mathrm{ideal}}=Q_L R_{\mathrm{init}}=' + _latexNum(Xs1Ideal, digits: 3) + r'\,\Omega');
    steps.add(r'B_{p1,\mathrm{ideal}}=\frac{Q_L}{R_v}=' + _latexNum(Bp1Ideal, digits: 4) + r'\,\mathrm{S}');

    // ================= Step 5) Right side L-section =================
    final double QR = sqrt(max(0, Rv / Rtar - 1));
    final double Xs2Ideal = QR * Rtar;
    final double Bp2Ideal = (Rv.abs() < _kEps) ? 0.0 : (QR / Rv); // S

    steps.add(r'\textbf{Step 5. Right Side Prototype (Tar }\to R_v\textbf{):}');
    steps.add(r'\text{Similarly, transform }R_{\mathrm{tar}}\text{ up to the same }R_v\text{.}');
    steps.add(r'Q_R=\sqrt{\frac{R_v}{R_{\mathrm{tar}}}-1}=' + _latexNum(QR, digits: 3));
    steps.add(r'X_{s2,\mathrm{ideal}}=Q_R R_{\mathrm{tar}}=' + _latexNum(Xs2Ideal, digits: 3) + r'\,\Omega');
    steps.add(r'B_{p2,\mathrm{ideal}}=\frac{Q_R}{R_v}=' + _latexNum(Bp2Ideal, digits: 4) + r'\,\mathrm{S}');

    // ================= Step 6) Combine middle shunt + de-embed endpoint reactance =================
    final double X1 = Xs1Ideal - Xinit;
    final double X2 = Xs2Ideal - Xtar;
    final double Btotal = Bp1Ideal + Bp2Ideal;

    steps.add(r'\textbf{Step 6. Combine Middle Shunt and De-embed Endpoint Reactance:}');
    steps.add(r'\text{The two L-sections share the same middle shunt node, so shunt susceptances add: }B=B_{p1}+B_{p2}.');
    steps.add(r'B=B_{p1,\mathrm{ideal}}+B_{p2,\mathrm{ideal}}=' + _latexNum(Btotal, digits: 4) + r'\,\mathrm{S}');
    steps.add(r'\text{Endpoints already include series reactance }X_{\mathrm{init}}\text{ and }X_{\mathrm{tar}}\text{. Therefore:}');
    steps.add(r'X_1=X_{s1,\mathrm{ideal}}-X_{\mathrm{init}}=' + _latexNum(X1, digits: 3) + r'\,\Omega');
    steps.add(r'X_2=X_{s2,\mathrm{ideal}}-X_{\mathrm{tar}}=' + _latexNum(X2, digits: 3) + r'\,\Omega');

    // ================= Step 7) Convert to L/C =================
    steps.add(r'\textbf{Step 7. Convert }(X_1,\,B,\,X_2)\textbf{ to Physical Components:}');
    steps.add(r'\text{Rules: for series }X,\ X>0\Rightarrow L=\frac{X}{\omega},\ X<0\Rightarrow C=\frac{-1}{X\omega}.');
    steps.add(r'\text{For shunt }B,\ B>0\Rightarrow C=\frac{B}{\omega},\ B<0\Rightarrow L=\frac{-1}{B\omega}.');

    // --- Series 1 ---
    if (X1.abs() < _kEps) {
      steps.add(r'X_1\approx 0\ \Rightarrow\ \text{No input series element required.}');
    } else if (X1 > 0) {
      final double L1 = X1 / omega;
      values['L_series1'] = L1;
      steps.add(r'L_1=\frac{X_1}{\omega}=' + _latexNum(L1, digits: 4) + r'\,\mathrm{H}');
    } else {
      final double C1 = -1 / (X1 * omega);
      values['C_series1'] = C1;
      steps.add(r'C_1=\frac{-1}{X_1\omega}=' + _latexNum(C1, digits: 4) + r'\,\mathrm{F}');
    }

    // --- Middle shunt ---
    if (Btotal.abs() < _kEps) {
      steps.add(r'B\approx 0\ \Rightarrow\ \text{No middle shunt element required.}');
    } else if (Btotal > 0) {
      final double Csh = Btotal / omega;
      values['C_shunt'] = Csh;
      steps.add(r'C_{\mathrm{shunt}}=\frac{B}{\omega}=' + _latexNum(Csh, digits: 4) + r'\,\mathrm{F}');
    } else {
      final double Lsh = -1 / (Btotal * omega);
      values['L_shunt'] = Lsh;
      steps.add(r'L_{\mathrm{shunt}}=\frac{-1}{B\omega}=' + _latexNum(Lsh, digits: 4) + r'\,\mathrm{H}');
    }

    // --- Series 2 ---
    if (X2.abs() < _kEps) {
      steps.add(r'X_2\approx 0\ \Rightarrow\ \text{No output series element required.}');
    } else if (X2 > 0) {
      final double L2 = X2 / omega;
      values['L_series2'] = L2;
      steps.add(r'L_2=\frac{X_2}{\omega}=' + _latexNum(L2, digits: 4) + r'\,\mathrm{H}');
    } else {
      final double C2 = -1 / (X2 * omega);
      values['C_series2'] = C2;
      steps.add(r'C_2=\frac{-1}{X_2\omega}=' + _latexNum(C2, digits: 4) + r'\,\mathrm{F}');
    }

    // ================= Step 8) Smith chart interpretation =================
    steps.add(r'\textbf{Step 8. Smith Chart Interpretation (How the Point Moves):}');
    steps.add(r'\text{Series elements move along constant-resistance circles in the Z-Smith chart.}');
    steps.add(r'\text{The middle shunt element is easiest to interpret in admittance: it changes susceptance and moves along constant-conductance circles.}');
    steps.add(r'\text{A correct design should land on the target point (within rounding tolerance).}');

    // ================= Smith chart paths =================
    final double z0 = data.z0;

    // Path 1: Series 1 (Z_init -> Z_mid1)
    final Complex zMid1 = zInit + Complex(0, X1);
    paths.add(SmithPath(
      startGamma: _zToGamma(zInit, z0),
      endGamma: _zToGamma(zMid1, z0),
      type: PathType.series,
      label: 'Series 1',
    ));

    // Path 2: Shunt in the middle
    final Complex yMid1 = Complex(1, 0) / zMid1;
    final Complex yMid2 = yMid1 + Complex(0, Btotal);
    final Complex zMid2 = Complex(1, 0) / yMid2;

    paths.add(SmithPath(
      startGamma: _zToGamma(zMid1, z0),
      endGamma: _zToGamma(zMid2, z0),
      type: PathType.shunt,
      label: 'Shunt',
    ));

    // Path 3: Series 2 (Z_mid2 -> Z_tar)
    paths.add(SmithPath(
      startGamma: _zToGamma(zMid2, z0),
      endGamma: _zToGamma(zTar, z0),
      type: PathType.series,
      label: 'Series 2',
    ));

    return TMatchingResult(
      values: values,
      steps: steps,
      topology: 'Low Pass (T Type)',
      paths: paths,
    );
  }

  static Complex _zToGamma(Complex z, double z0) {
    if (z.real.isInfinite || z.abs() > 1e9) return Complex(1, 0);
    return (z - Complex(z0, 0)) / (z + Complex(z0, 0));
  }
}
