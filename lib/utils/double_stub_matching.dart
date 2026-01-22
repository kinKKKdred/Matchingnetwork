import 'dart:math';

// Hide pow/sqrt from complex to avoid conflicts with dart:math.
import 'package:complex/complex.dart' hide pow, sqrt;

import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../models/stub_spacing.dart';
import '../utils/complex_utils.dart';

import './single_stub_matching.dart';

/// Double-stub matching (two shunt stubs separated by a fixed spacing s).
///
/// Implementation scheme:
/// - d = 0 (Stub1 is placed at the input/reference plane).
/// - s is selectable: λ/8 (t=+1) or 3λ/8 (t=-1).
///
/// Notes:
/// - We solve in the **normalized admittance** domain.
/// - Let y_init = g + jb, y_tar = g_t + jb_t.
/// - After Stub1: y_1' = g + jB, where B = b + b1.
/// - Transmission line of length s (t = tan(βs)) transforms:
///     y_2 = (y_1' + jt) / (1 + j y_1' t)
/// - We enforce Re(y_2) = g_t, leading to a quadratic in B:
///     B^2 + 2tB + (t^2 - 2g/g_t + g^2) = 0
///   For t=±1:
///     Δ = 2g/g_t - g^2
///     t=+1: B = 1 ± sqrt(Δ)
///     t=-1: B = -1 ± sqrt(Δ)
/// - Then b1 = B - b, and b2 = b_t - Im(y_2).
class DoubleStubMatchingCalculator {
  static const double _eps = 1e-9;

  static StubMatchingResult calculateStubMatch(
    ImpedanceData data, {
    StubSpacing spacing = StubSpacing.lambdaOver8,
  }) {
    final List<String> commonSteps = [];
    final List<StubSolution> solutions = [];

    // ================= 1) System parameters =================
    final double f = data.frequency;
    final double z0 = data.z0;
    final double vf = 1.0;
    final double lambdaMm = (299792458.0 * vf / f) * 1000.0;

    commonSteps.add(r'\textbf{Step 0. System Parameters:}');
    commonSteps.add(r'f = ' + toLatexScientific(f, digits: 3) + r'\,\mathrm{Hz},\quad Z_0 = ' + outputNum(z0) + r'\,\Omega');
    commonSteps.add(r'\lambda = ' + outputNum(lambdaMm, precision: 2) + r'\,\mathrm{mm}');

    // Resolve Z_initial / Z_target (supports Z or Γ input)
    final Complex zInit = data.zInitial ?? (data.gammaInitial != null ? gammaToZ(data.gammaInitial!, z0) : Complex(z0, 0));
    final Complex zTar = data.zTarget ?? (data.gammaTarget != null ? gammaToZ(data.gammaTarget!, z0) : Complex(z0, 0));

    commonSteps.add(r'Z_{\mathrm{init}} = ' + outputNum(zInit, precision: 4) + r'\,\Omega');
    commonSteps.add(r'Z_{\mathrm{tar}} = ' + outputNum(zTar, precision: 4) + r'\,\Omega');

    // ================= 2) Quick checks =================
    if ((zInit - zTar).abs() < 0.05) {
      final List<String> infoSteps = [];
      infoSteps.add(r'\textbf{Status: Already Matched}');
      infoSteps.add(r'Z_{\mathrm{init}} \approx Z_{\mathrm{tar}} \Rightarrow \text{Direct connection.}');

      solutions.add(
        StubSolution(
          title: 'Direct Connection',
          stubType: 'None',
          dLengthMm: 0,
          dLengthLambda: 0,
          stubLengthMm: 0,
          stubLengthLambda: 0,
          steps: infoSteps,
          paths: const [],
        ),
      );
      return StubMatchingResult(solutions: solutions, commonSteps: commonSteps);
    }

    // Pure reactance -> resistance is infeasible for lossless matching (robustness)
    if (zInit.real.abs() < _eps && zTar.real.abs() > _eps) {
      final List<String> errSteps = [];
      errSteps.add(r'\textbf{Feasibility Check Failed:}');
      errSteps.add(r'\color{red}{\text{Error: Cannot match a pure reactance (R=0) to a resistance (R>0).}}');

      solutions.add(
        StubSolution(
          title: 'Infeasible Case',
          stubType: 'Error',
          dLengthMm: 0,
          dLengthLambda: 0,
          stubLengthMm: 0,
          stubLengthLambda: 0,
          steps: errSteps,
          paths: const [],
        ),
      );
      return StubMatchingResult(solutions: solutions, commonSteps: commonSteps);
    }

    // ================= 3) Normalize admittances =================
    final Complex yInit = Complex(z0, 0) / zInit; // normalized
    final Complex yTar = Complex(z0, 0) / zTar;   // normalized

    final double g = yInit.real;
    final double b = yInit.imaginary;
    final double gT = yTar.real;
    final double bT = yTar.imaginary;

    commonSteps.add(r'\textbf{Step 1. Normalize Admittances:}');
    commonSteps.add(r'y_{\mathrm{init}} = ' + outputNum(yInit, precision: 4));
    commonSteps.add(r'y_{\mathrm{tar}} = ' + outputNum(yTar, precision: 4));

    // ================= 4) Geometry constraints (d=0, fixed s) =================
    final double dLambda = 0.0;
    final double dMm = 0.0;

    final double sLambda = spacing.lambdaFactor;
    final double sMm = sLambda * lambdaMm;
    final double t = spacing.t; // tan(βs)

    commonSteps.add(r'\textbf{Step 2. Double-Stub Geometry (Scheme 1):}');
    commonSteps.add(r'd = 0\,\lambda\quad (\text{Stub1 at the input plane})');
    commonSteps.add(r's = ' + outputNum(sLambda, precision: 4) + r'\,\lambda = ' + outputNum(sMm, precision: 2) + r'\,\mathrm{mm}');
    commonSteps.add(r't = \tan(\beta s) = ' + outputNum(t, precision: 2));

    // ================= 5) Solve for Stub1 susceptance (B solutions) =================
    commonSteps.add(r'\textbf{Step 3. Feasibility \& Quadratic in } B:');
    if (gT.abs() < _eps) {
      commonSteps.add(r'\color{red}{\text{No solution: } \Re(y_{\mathrm{tar}}) \approx 0 \text{ is not supported by this solver.}}');
      return StubMatchingResult(solutions: const [], commonSteps: commonSteps);
    }

    // Δ = 2g/gT - g^2
    final double delta = (2.0 * g / gT) - (g * g);
    commonSteps.add(r'\Delta = \frac{2g}{g_t} - g^2 = ' + outputNum(delta, precision: 4));

    if (delta < -1e-8) {
      commonSteps.add(r'\color{red}{\text{No real solution: } \Delta < 0.}');
      return StubMatchingResult(solutions: const [], commonSteps: commonSteps);
    }

    final double sqrtDelta = sqrt(max(0.0, delta));
    commonSteps.add(r'\sqrt{\Delta} = ' + outputNum(sqrtDelta, precision: 4));

    // Candidate B values depend on t
    final List<double> bCandidates = [];
    if (t > 0) {
      // t = +1 -> B = 1 ± sqrt(Δ)
      bCandidates.add(1.0 - sqrtDelta);
      if (sqrtDelta.abs() > 1e-12) bCandidates.add(1.0 + sqrtDelta);
    } else {
      // t = -1 -> B = -1 ± sqrt(Δ)
      bCandidates.add(-1.0 - sqrtDelta);
      if (sqrtDelta.abs() > 1e-12) bCandidates.add(-1.0 + sqrtDelta);
    }

    // Deduplicate (numerical)
    final List<double> uniqueB = [];
    for (final v in bCandidates) {
      if (uniqueB.every((u) => (u - v).abs() > 1e-10)) uniqueB.add(v);
    }

    int solCount = 0;
    final Complex gammaInit = zToGamma(zInit, z0);
    final Complex gammaTar = zToGamma(zTar, z0);

    for (int rIdx = 0; rIdx < uniqueB.length; rIdx++) {
      final double B = uniqueB[rIdx];
      final double b1 = B - b;

      // y1' = yInit + jb1 = g + jB
      final Complex y1p = Complex(g, B);

      // y2 = (y1' + jt) / (1 + j y1' t)
      final Complex jt = Complex(0, t);
      final Complex j = Complex(0, 1);
      final Complex denom = Complex(1, 0) + j * y1p * Complex(t, 0);
      final Complex y2 = (y1p + jt) / denom;

      final double b2 = bT - y2.imaginary;
      final Complex yOut = y2 + Complex(0, b2);
      final double err = (yOut - yTar).abs();

      // Intermediate impedances (absolute) for Smith paths
      final Complex z1p = Complex(z0, 0) / y1p;
      final Complex z2 = Complex(z0, 0) / y2;
      final Complex gamma1p = zToGamma(z1p, z0);
      final Complex gamma2 = zToGamma(z2, z0);

      // For each susceptance root, provide both physical realizations.
      for (final String stubType in const ['Short', 'Open']) {
        final double l1Lambda = _bToStubLambda(b1, isShort: stubType == 'Short');
        final double l2Lambda = _bToStubLambda(b2, isShort: stubType == 'Short');
        final double l1Mm = l1Lambda * lambdaMm;
        final double l2Mm = l2Lambda * lambdaMm;

        solCount += 1;
        final List<String> steps = [];

        steps.add(r'\textbf{Step 4. Solve Stub1 Susceptance } b_1:');
        steps.add(r'B = b + b_1');
        if (t > 0) {
          steps.add(r'B = 1 \pm \sqrt{\Delta}');
        } else {
          steps.add(r'B = -1 \pm \sqrt{\Delta}');
        }
        steps.add(r'B_{' + '${rIdx + 1}' + r'} = ' + outputNum(B, precision: 4));
        steps.add(r'b_1 = B - b = ' + outputNum(b1, precision: 4));

        steps.add(r'\textbf{Step 5. Transform to the 2nd Stub Plane:}');
        // IMPORTANT: avoid Dart raw-string quote issues by using LaTeX prime notation (^{\prime})
        // instead of an apostrophe (').
        steps.add(r'y_1^{\prime} = y_{\mathrm{init}} + j b_1 = ' + outputNum(y1p, precision: 4));
        steps.add(r'y_2 = \frac{y_1^{\prime} + jt}{1 + j y_1^{\prime} t},\quad t=' + outputNum(t, precision: 2));
        steps.add(r'y_2 = ' + outputNum(y2, precision: 4));

        steps.add(r'\textbf{Step 6. Solve Stub2 Susceptance } b_2:');
        steps.add(r'b_2 = b_t - \Im(y_2) = ' + outputNum(bT, precision: 4) + ' - ' + outputNum(y2.imaginary, precision: 4));
        steps.add(r'b_2 = ' + outputNum(b2, precision: 4));

        steps.add(r'\textbf{Step 7. Convert Susceptance to Stub Lengths:}');
        if (stubType == 'Short') {
          steps.add(r'\text{Short stub: } \tan(\beta l) = -1/b');
        } else {
          steps.add(r'\text{Open stub: } \tan(\beta l) = b');
        }
        steps.add(r'l_1 = ' + outputNum(l1Lambda, precision: 4) + r'\,\lambda = ' + outputNum(l1Mm, precision: 2) + r'\,\mathrm{mm}');
        steps.add(r'l_2 = ' + outputNum(l2Lambda, precision: 4) + r'\,\lambda = ' + outputNum(l2Mm, precision: 2) + r'\,\mathrm{mm}');

        steps.add(r'\textbf{Step 8. Verification (Admittance):}');
        steps.add(r'y_{\mathrm{out}} = y_2 + j b_2 = ' + outputNum(yOut, precision: 4));
        steps.add(r'|y_{\mathrm{out}} - y_{\mathrm{tar}}| = ' + outputNum(err, precision: 4));

        final List<SmithPath> paths = [
          SmithPath(
            startGamma: gammaInit,
            endGamma: gamma1p,
            type: PathType.shunt,
            label: 'Stub1 ($stubType)',
          ),
          SmithPath(
            startGamma: gamma1p,
            endGamma: gamma2,
            type: PathType.transmissionLine,
            label: 'Line s',
          ),
          SmithPath(
            startGamma: gamma2,
            endGamma: gammaTar,
            type: PathType.shunt,
            label: 'Stub2 ($stubType)',
          ),
        ];

        solutions.add(
          StubSolution(
            title: 'Sol $solCount ($stubType)',
            stubType: stubType,
            dLengthMm: dMm,
            dLengthLambda: dLambda,
            stubLengthMm: l1Mm,
            stubLengthLambda: l1Lambda,
            stub2LengthMm: l2Mm,
            stub2LengthLambda: l2Lambda,
            spacingLengthMm: sMm,
            spacingLengthLambda: sLambda,
            steps: steps,
            paths: paths,
          ),
        );
      }
    }

    return StubMatchingResult(solutions: solutions, commonSteps: commonSteps);
  }

  /// Convert normalized susceptance b to stub electrical length (fraction of λ).
  ///
  /// We keep the primary solution in [0, 0.5) λ.
  static double _bToStubLambda(double b, {required bool isShort}) {
    if (b.abs() < 1e-6) {
      // b=0: short-stub => λ/4 gives open circuit; open-stub => l=0 gives open circuit.
      return isShort ? 0.25 : 0.0;
    }

    double theta;
    if (isShort) {
      // cot(βl) = -b  => tan(βl) = -1/b
      theta = atan(-1.0 / b);
    } else {
      // tan(βl) = b
      theta = atan(b);
    }

    // Map to [0, π)
    if (theta < 0) theta += pi;
    return theta / (2 * pi);
  }
}
