import 'dart:math';
// 隐藏 complex 包里的 pow 和 sqrt，避免与 dart:math 冲突
import 'package:complex/complex.dart' hide pow, sqrt;
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart';

class StubSolution {
  final String title;
  final String stubType; // "Short" or "Open" or "None"
  final double dLengthMm;
  final double dLengthLambda;
  final double stubLengthMm;
  final double stubLengthLambda;

  /// Optional fields used by multi-stub implementations.
  ///
  /// - For Double-Stub: stubLength* is Stub1, stub2Length* is Stub2, and spacing* is the distance between them.
  /// - For Balanced-Stub: these remain null (the UI uses stubMode to interpret stubLength as "each").
  final double? stub2LengthMm;
  final double? stub2LengthLambda;
  final double? spacingLengthMm;
  final double? spacingLengthLambda;

  final List<String> steps;
  final List<SmithPath> paths;

  StubSolution({
    required this.title,
    required this.stubType,
    required this.dLengthMm,
    required this.dLengthLambda,
    required this.stubLengthMm,
    required this.stubLengthLambda,
    this.stub2LengthMm,
    this.stub2LengthLambda,
    this.spacingLengthMm,
    this.spacingLengthLambda,
    required this.steps,
    required this.paths,
  });
}

class StubMatchingResult {
  final List<StubSolution> solutions;
  final List<String> commonSteps;

  StubMatchingResult({
    required this.solutions,
    this.commonSteps = const [],
  });
}

class SingleStubMatchingCalculator {
  
  static StubMatchingResult calculateStubMatch(ImpedanceData data) {
    final List<String> commonSteps = [];
    final List<StubSolution> solutions = [];

    // ---------- Basic parameters ----------
    final double f = data.frequency;
    final double z0 = data.z0;
    const double vf = 1.0; // keep consistent with existing project (can be extended later)
    final double lambdaMm = (299792458.0 * vf / f) * 1000.0;

    // ---------- Step 0: Convert Γ to Z (if needed) ----------
    Complex zInit;
    Complex zTar;
    if (data.zInitial != null && data.zTarget != null) {
      zInit = data.zInitial!;
      zTar = data.zTarget!;
    } else if (data.gammaInitial != null && data.gammaTarget != null) {
      zInit = gammaToZ(data.gammaInitial!, z0);
      zTar = gammaToZ(data.gammaTarget!, z0);

      commonSteps.add(r'\textbf{Step 0. Convert \Gamma to Z:}');
      commonSteps.add(r'Z_{\mathrm{init}} = Z_0 \frac{1+\Gamma_{\mathrm{init}}}{1-\Gamma_{\mathrm{init}}} = ' +
          outputNum(zInit, precision: 4) + r'\,\Omega');
      commonSteps.add(r'Z_{\mathrm{tar}} = Z_0 \frac{1+\Gamma_{\mathrm{tar}}}{1-\Gamma_{\mathrm{tar}}} = ' +
          outputNum(zTar, precision: 4) + r'\,\Omega');
    } else {
      throw Exception('Input incomplete: provide (Zinitial,Ztarget) or (Γinitial,Γtarget).');
    }

    // ---------- Step 1: Problem & Target ----------
    commonSteps.add(r'\textbf{Step 1. Problem \& Target:}');
    commonSteps.add(r'Z_0=' + outputNum(z0, precision: 4) + r'\,\Omega,\quad f=' + toLatexScientific(f, digits: 3) + r'\,\mathrm{Hz}');
    commonSteps.add(r'\lambda=' + outputNum(lambdaMm, precision: 2) + r'\,\mathrm{mm}');
    commonSteps.add(r'Z_{\mathrm{init}}=' + outputNum(zInit, precision: 4) + r'\,\Omega');
    commonSteps.add(r'Z_{\mathrm{tar}}=' + outputNum(zTar, precision: 4) + r'\,\Omega');

    // ---------- Step 2: Normalize (z,y,Γ) ----------
    final Complex zInitN = zInit / Complex(z0, 0);
    final Complex zTarN = zTar / Complex(z0, 0);
    final Complex yInit = Complex(1, 0) / zInitN;
    final Complex yTar = Complex(1, 0) / zTarN;

    final Complex gammaInit = zToGamma(zInit, z0);
    final Complex gammaTar = zToGamma(zTar, z0);

    commonSteps.add(r'\textbf{Step 2. Normalize (z,y,\Gamma):}');
    commonSteps.add(r'z_{\mathrm{init}}=Z_{\mathrm{init}}/Z_0=' + outputNum(zInitN, precision: 4) + r',\quad z_{\mathrm{tar}}=' +
        outputNum(zTarN, precision: 4));
    commonSteps.add(r'y_{\mathrm{init}}=1/z_{\mathrm{init}}=' + outputNum(yInit, precision: 4) + r',\quad y_{\mathrm{tar}}=1/z_{\mathrm{tar}}=' +
        outputNum(yTar, precision: 4));
    commonSteps.add(r'\Gamma_{\mathrm{init}}=' + outputNum(gammaInit, precision: 4) + r',\quad |\Gamma_{\mathrm{init}}|=' +
        outputNum(gammaInit.abs(), precision: 4));
    commonSteps.add(r'\Gamma_{\mathrm{tar}}=' + outputNum(gammaTar, precision: 4) + r',\quad |\Gamma_{\mathrm{tar}}|=' +
        outputNum(gammaTar.abs(), precision: 4));

    // ---------- Step 3: Special-case checks ----------
    // 3.1 Already matched
    if ((zInit - zTar).abs() < 0.05) {
      commonSteps.add(r'\textbf{Step 3. Conclusion: Direct connection}');
      commonSteps.add(r'\text{Because } Z_{\mathrm{init}} \approx Z_{\mathrm{tar}}, \text{ no matching elements are required.}');

      final StubSolution sol = StubSolution(
        title: "Direct Connection",
        stubType: "None",
        dLengthMm: 0,
        dLengthLambda: 0,
        stubLengthMm: 0,
        stubLengthLambda: 0,
        steps: const [],
        paths: const [],
      );
      return StubMatchingResult(solutions: [sol], commonSteps: commonSteps);
    }

    // 3.2 Pure transmission-line solution (same |Γ|)
    final double tolGamma = 1e-3;
    if ((gammaInit.abs() - gammaTar.abs()).abs() <= tolGamma) {
      commonSteps.add(r'\textbf{Step 3. Special case: Transmission line only}');
      commonSteps.add(r'\text{If } |\Gamma_{\mathrm{init}}| \approx |\Gamma_{\mathrm{tar}}|,\ \text{a lossless line can rotate }\Gamma \text{ to reach the target.}');
      commonSteps.add(r'\Gamma(l)=\Gamma(0)\,e^{-j2\beta l}');

      final double angInit = atan2(gammaInit.imaginary, gammaInit.real);
      final double angTar = atan2(gammaTar.imaginary, gammaTar.real);

      double deltaAng = angInit - angTar;
      while (deltaAng < 0) deltaAng += 2 * pi;
      while (deltaAng >= 2 * pi) deltaAng -= 2 * pi;

      final double dLambda = deltaAng / (4 * pi); // 0 ~ 0.5
      final double dMm = dLambda * lambdaMm;

      commonSteps.add(r'\angle\Gamma_{\mathrm{init}}=' + outputNum(angInit, precision: 4) + r'\ \mathrm{rad},\quad \angle\Gamma_{\mathrm{tar}}=' +
          outputNum(angTar, precision: 4) + r'\ \mathrm{rad}');
      commonSteps.add(r'd=\frac{\angle\Gamma_{\mathrm{init}}-\angle\Gamma_{\mathrm{tar}}}{4\pi}\lambda=' +
          outputNum(dLambda, precision: 4) + r'\lambda=' + outputNum(dMm, precision: 2) + r'\,\mathrm{mm}');
      commonSteps.add(r'\text{Equivalent solutions repeat every } \lambda/2.');

      final List<SmithPath> paths = [
        SmithPath(
          startGamma: gammaInit,
          endGamma: gammaTar,
          type: PathType.transmissionLine,
          label: "Line d",
        ),
      ];

      final StubSolution sol = StubSolution(
        title: "Transmission Line Only",
        stubType: "None",
        dLengthMm: dMm,
        dLengthLambda: dLambda,
        stubLengthMm: 0,
        stubLengthLambda: 0,
        steps: const [],
        paths: paths,
      );
      return StubMatchingResult(solutions: [sol], commonSteps: commonSteps);
    }

    // 3.3 Feasibility guard: purely reactive cannot become resistive using lossless stubs/lines
    if (zInit.real.abs() < 1e-9 && zTar.real.abs() > 1e-6) {
      commonSteps.add(r'\textbf{Step 3. Feasibility: No solution (pure reactance)}');
      commonSteps.add(r'\color{red}{\text{Error: } \Re(Z_{\mathrm{init}})=0 \text{ but } \Re(Z_{\mathrm{tar}})>0.}');
      commonSteps.add(r'\text{A lossless reactive network cannot generate a real part from a purely reactive driving-point impedance.}');
      return StubMatchingResult(solutions: const [], commonSteps: commonSteps);
    }

    // ---------- Step 4: Single-stub principle (line + shunt stub) ----------
    final double gTarget = yTar.real;
    commonSteps.add(r'\textbf{Step 4. Single-stub strategy (Line }\rightarrow\text{ Shunt Stub):}');
    commonSteps.add(r'\text{A lossless line rotates } \Gamma \text{ on a constant }|\Gamma| \text{ circle.}');
    commonSteps.add(r'\text{A shunt stub adds } j b \text{ in } y\text{-domain, so } g=\Re(y) \text{ is unchanged.}');
    commonSteps.add(r'\text{Therefore, at the stub location we require } \Re(y_{\mathrm{mid}})=\Re(y_{\mathrm{tar}})=g_{\mathrm{tar}}.');
    commonSteps.add(r'g_{\mathrm{tar}}=\Re(y_{\mathrm{tar}})=' + outputNum(gTarget, precision: 4));

    // ---------- Step 5: Feasibility & intersection points ----------
    final double rVSWR = gammaInit.abs(); // VSWR circle radius in Γ-plane
    final double cx = -gTarget / (1 + gTarget);
    final double rg = 1 / (1 + gTarget);

    final double gMax = (1 + rVSWR) / (1 - rVSWR);
    final double gMin = (1 - rVSWR) / (1 + rVSWR);

    commonSteps.add(r'\textbf{Step 5. Feasibility \& intersection on Smith chart:}');
    commonSteps.add(r'|\Gamma_{\mathrm{init}}|=' + outputNum(rVSWR, precision: 4) + r'\Rightarrow \text{VSWR circle radius } r=|\Gamma_{\mathrm{init}}|.');
    commonSteps.add(r'\text{Conductance circle in }\Gamma\text{-plane: } c_x=-\frac{g_{\mathrm{tar}}}{1+g_{\mathrm{tar}}},\ r_g=\frac{1}{1+g_{\mathrm{tar}}}.');
    commonSteps.add(r'g_{\min}=\frac{1-r}{1+r}=' + outputNum(gMin, precision: 4) + r',\quad g_{\max}=\frac{1+r}{1-r}=' + outputNum(gMax, precision: 4));

    if (gTarget > gMax + 1e-4 || gTarget < gMin - 1e-4) {
      commonSteps.add(r'\color{red}\text{No solution: } g_{\mathrm{tar}} \notin [g_{\min},g_{\max}] \Rightarrow \text{no intersection.}');
      return StubMatchingResult(solutions: const [], commonSteps: commonSteps);
    }

    // Intersection between the VSWR circle and the conductance circle
    final double u = (cx.abs() < 1e-9) ? 0 : ((rVSWR * rVSWR) - (rg * rg) + (cx * cx)) / (2 * cx);
    final double vSq = (rVSWR * rVSWR) - (u * u);
    final double v = (vSq < 0) ? 0 : sqrt(vSq);

    final List<Complex> intersections = [Complex(u, v), Complex(u, -v)];

    // Report intersection points (avoid duplicate text if v≈0)
    if (v.abs() < 1e-9) {
      commonSteps.add(r'\Gamma_{\mathrm{mid}}=' + outputNum(intersections[0], precision: 4) + r'\ \text{(tangent, single intersection)}');
    } else {
      commonSteps.add(r'\Gamma_{\mathrm{mid},1}=' + outputNum(intersections[0], precision: 4) + r',\quad \Gamma_{\mathrm{mid},2}=' +
          outputNum(intersections[1], precision: 4));
    }

    // ---------- Generate solutions (short/open at each intersection) ----------
    int solutionCount = 0;
    for (int i = 0; i < intersections.length; i++) {
      final Complex gammaMidRaw = intersections[i];

      // 1) Transmission-line length d (rotate Γinit -> Γmid)
      final double angS = atan2(gammaInit.imaginary, gammaInit.real);
      final double angM = atan2(gammaMidRaw.imaginary, gammaMidRaw.real);
      double deltaAng = angS - angM;
      while (deltaAng < 0) deltaAng += 2 * pi;

      final double dLambda = deltaAng / (4 * pi);
      final double dMm = dLambda * lambdaMm;

      // 2) y at stub location (enforce g=gTarget for numerical stability)
      final Complex zMidRaw = gammaToZ(gammaMidRaw, z0);
      final Complex yMidRaw = Complex(z0, 0) / zMidRaw; // normalized y
      final Complex yMid = Complex(gTarget, yMidRaw.imaginary);
      final Complex gammaMid = zToGamma(Complex(z0, 0) / yMid, z0);

      // 3) required stub susceptance to reach yTar
      final Complex yDiff = yTar - yMid;
      final double bStub = yDiff.imaginary;

      // Case A: Short stub (tan(βl) = -1/b)
      double lLambdaShort = 0.0;
      if (bStub.abs() > 1e-6) {
        double theta = atan(-1.0 / bStub);
        if (theta < 0) theta += pi;
        lLambdaShort = theta / (2 * pi);
      } else {
        lLambdaShort = 0.25; // b=0 => λ/4 short stub is open-circuit, giving 0 shunt admittance
      }

      _addSolution(
        solutions,
        ++solutionCount,
        "Short",
        dLambda,
        dMm,
        lLambdaShort,
        lLambdaShort * lambdaMm,
        gammaInit,
        gammaMid,
        zTar,
        z0,
        gTarget,
        yMid,
        bStub,
        lambdaMm,
        i + 1,
      );

      // Case B: Open stub (tan(βl) = b)
      double lLambdaOpen = 0.0;
      if (bStub.abs() > 1e-6) {
        double theta = atan(bStub);
        if (theta < 0) theta += pi;
        lLambdaOpen = theta / (2 * pi);
      } else {
        lLambdaOpen = 0.0; // b=0 => l=0 open stub (no effect)
      }

      _addSolution(
        solutions,
        ++solutionCount,
        "Open",
        dLambda,
        dMm,
        lLambdaOpen,
        lLambdaOpen * lambdaMm,
        gammaInit,
        gammaMid,
        zTar,
        z0,
        gTarget,
        yMid,
        bStub,
        lambdaMm,
        i + 1,
      );
    }

    return StubMatchingResult(solutions: solutions, commonSteps: commonSteps);
  }

  // Helper: build one solution (keeps UI and Smith-path logic consistent)
  static void _addSolution(
      List<StubSolution> solutions,
      int index,
      String stubType, // "Short" or "Open"
      double dLambda,
      double dMm,
      double lLambda,
      double lMm,
      Complex gammaInit,
      Complex gammaMid,
      Complex zTar,
      double z0,
      double gTarget,
      Complex yMid,
      double bStub,
      double lambdaMm,
      int intersectionIndex,
      ) {
    final List<String> steps = [];

    final Complex yTar = Complex(z0, 0) / zTar; // normalized y_target
    final double bTar = yTar.imaginary;

    // --- Step 6 ---
    steps.add(r'\textbf{Step 6. Topology (Solution ' + '$index' + r'): Transmission Line }\rightarrow\text{ Shunt Stub}');
    steps.add(r'\text{Intersection }' + '$intersectionIndex' + r'\text{ on VSWR circle, stub type: }' + stubType + r'.');

    // --- Step 7 ---
    final double angInit = atan2(gammaInit.imaginary, gammaInit.real);
    final double angMid = atan2(gammaMid.imaginary, gammaMid.real);
    double deltaAng = angInit - angMid;
    while (deltaAng < 0) deltaAng += 2 * pi;
    while (deltaAng >= 2 * pi) deltaAng -= 2 * pi;

    steps.add(r'\textbf{Step 7. Choose intersection \& compute line length } d:');
    steps.add(r'\Gamma_{\mathrm{init}}=' + outputNum(gammaInit, precision: 4) + r',\quad \Gamma_{\mathrm{mid}}=' + outputNum(gammaMid, precision: 4));
    steps.add(r'd=\frac{\angle\Gamma_{\mathrm{init}}-\angle\Gamma_{\mathrm{mid}}}{4\pi}\lambda=' +
        outputNum(dLambda, precision: 4) + r'\lambda=' + outputNum(dMm, precision: 2) + r'\,\mathrm{mm}');
    steps.add(r'\text{(Equivalent solutions repeat every } \lambda/2\text{.)}');

    // --- Step 8 ---
    steps.add(r'\textbf{Step 8. Admittance at stub position:}');
    steps.add(r'y_{\mathrm{mid}}=' + outputNum(yMid, precision: 4) + r',\quad g_{\mathrm{mid}}=\Re(y_{\mathrm{mid}})=' +
        outputNum(yMid.real, precision: 4) + r'\approx g_{\mathrm{tar}}=' + outputNum(gTarget, precision: 4));

    // --- Step 9 ---
    steps.add(r'\textbf{Step 9. Solve required stub susceptance } b_{\mathrm{stub}}:');
    steps.add(r'y_{\mathrm{tar}}=' + outputNum(yTar, precision: 4));
    steps.add(r'b_{\mathrm{stub}}=\Im(y_{\mathrm{tar}})-\Im(y_{\mathrm{mid}})=' +
        outputNum(bTar, precision: 4) + r' - ' + outputNum(yMid.imaginary, precision: 4) + r'=' + outputNum(bStub, precision: 4));
    steps.add(r'y_{\mathrm{out}}=y_{\mathrm{mid}}+j b_{\mathrm{stub}}=y_{\mathrm{tar}}');

    // --- Step 10 ---
    steps.add(r'\textbf{Step 10. Convert susceptance to stub length } l:');
    if (stubType == 'Short') {
      steps.add(r'\text{Short stub: } \tan(\beta l)=-1/b_{\mathrm{stub}}');
    } else {
      steps.add(r'\text{Open stub: } \tan(\beta l)=b_{\mathrm{stub}}');
    }
    steps.add(r'l=' + outputNum(lLambda, precision: 4) + r'\lambda=' + outputNum(lMm, precision: 2) + r'\,\mathrm{mm}');

    // --- Step 11 ---
    final Complex yOut = yMid + Complex(0, bStub);
    final Complex zOut = Complex(z0, 0) / yOut;
    final double errY = (yOut - yTar).abs();
    final double errZ = (zOut - zTar).abs();

    steps.add(r'\textbf{Step 11. Verification:}');
    steps.add(r'y_{\mathrm{out}}=' + outputNum(yOut, precision: 4) + r',\quad |y_{\mathrm{out}}-y_{\mathrm{tar}}|=' + outputNum(errY, precision: 4));
    steps.add(r'Z_{\mathrm{out}}=Z_0/y_{\mathrm{out}}=' + outputNum(zOut, precision: 4) + r'\,\Omega,\quad |Z_{\mathrm{out}}-Z_{\mathrm{tar}}|=' + outputNum(errZ, precision: 4));

    // Smith-chart paths (kept as before)
    final List<SmithPath> paths = [];
    paths.add(
      SmithPath(
        startGamma: gammaInit,
        endGamma: gammaMid,
        type: PathType.transmissionLine,
        label: "Line d",
      ),
    );
    paths.add(
      SmithPath(
        startGamma: gammaMid,
        endGamma: zToGamma(zOut, z0),
        // SmithPath.PathType uses `shunt` for shunt elements.
        type: PathType.shunt,
        label: stubType + " Stub",
      ),
    );

    solutions.add(
      StubSolution(
        title: 'Sol $index ($stubType)',
        stubType: stubType,
        dLengthMm: dMm,
        dLengthLambda: dLambda,
        stubLengthMm: lMm,
        stubLengthLambda: lLambda,
        steps: steps,
        paths: paths,
      ),
    );
  }


  static Complex zToGamma(Complex z, double z0) {
    if (z.abs() > 1e9) return Complex(1, 0);
    return (z - Complex(z0, 0)) / (z + Complex(z0, 0));
  }

  static Complex gammaToZ(Complex gamma, double z0) {
    if ((Complex(1, 0) - gamma).abs() < 1e-9) return Complex(1e9, 0);
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma) * Complex(z0, 0);
  }
}
