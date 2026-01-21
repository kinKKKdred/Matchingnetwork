import 'dart:math';
// 隐藏 complex 包里的 pow 和 sqrt，避免与 dart:math 冲突
import 'package:complex/complex.dart' hide pow, sqrt;
import '../models/impedance_data.dart';
import '../models/smith_path.dart';
import '../utils/complex_utils.dart';

class StubSolution {
  final String title;
  final String stubType; // "Short" or "Open"
  final double dLengthMm;
  final double dLengthLambda;
  final double stubLengthMm;
  final double stubLengthLambda;
  final List<String> steps;
  final List<SmithPath> paths;

  StubSolution({
    required this.title,
    required this.stubType,
    required this.dLengthMm,
    required this.dLengthLambda,
    required this.stubLengthMm,
    required this.stubLengthLambda,
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
    List<String> commonSteps = [];
    List<StubSolution> solutions = [];

    // ================= 1. 基础参数解析 =================
    double f = data.frequency;
    double z0 = data.z0;
    double vf = 1.0;
    double lambdaMm = (299792458.0 * vf / f) * 1000.0;

    commonSteps.add(r'\textbf{Step 0. System Parameters:}');
    commonSteps.add(r'f = ' + toLatexScientific(f) + r' \text{ Hz, } Z_0 = ' + outputNum(z0) + r'\;\Omega');
    commonSteps.add(r'\lambda = ' + outputNum(lambdaMm, precision: 2) + r'\;\mathrm{mm}');

    Complex zS = data.zInitial ?? (data.gammaInitial != null ? gammaToZ(data.gammaInitial!, z0) : Complex(50, 0));
    Complex zL = data.zTarget ?? (data.gammaTarget != null ? gammaToZ(data.gammaTarget!, z0) : Complex(50, 0));

    // ================= [NEW 1] 直通检测 (Already Matched) =================
    if ((zS - zL).abs() < 0.05) {
      List<String> infoSteps = [];
      infoSteps.add(r'\textbf{Status: Already Matched}');
      infoSteps.add(r'\text{Source impedance is sufficiently close to Target impedance.}');
      infoSteps.add(r'\text{Solution: Direct Connection (No Stub required).}');

      StubSolution matchedSolution = StubSolution(
        title: "Direct Connection",
        stubType: "None",
        dLengthMm: 0, dLengthLambda: 0, stubLengthMm: 0, stubLengthLambda: 0,
        steps: infoSteps,
        paths: [],
      );
      return StubMatchingResult(solutions: [matchedSolution], commonSteps: commonSteps);
    }

    // ================= [NEW 2] 鲁棒性保护：纯虚部输入 (Pure Reactance) =================
    const double epsilon = 1e-6;
    if (zS.real.abs() < epsilon && zL.real.abs() > epsilon) {
      List<String> errorSteps = [];
      errorSteps.add(r'\textbf{Feasibility Check Failed:}');
      errorSteps.add(r'\color{red}{\text{Error: Cannot match a pure reactance (R=0) to a resistance (R>0).}}');
      errorSteps.add(r'\text{Reason: Lossless networks preserve } |\Gamma| \text{. Center } |\Gamma|=0 \text{ is unreachable.}');

      StubSolution errorSolution = StubSolution(
        title: "Infeasible Case",
        stubType: "Error",
        dLengthMm: 0, dLengthLambda: 0, stubLengthMm: 0, stubLengthLambda: 0,
        steps: errorSteps,
        paths: [],
      );
      return StubMatchingResult(solutions: [errorSolution], commonSteps: commonSteps);
    }

    // 转导纳
    Complex yS = Complex(z0, 0) / zS;
    Complex yL = Complex(z0, 0) / zL;

    commonSteps.add(r'\textbf{Step 1. Normalize Admittances:}');
    commonSteps.add(r'y_{init} = ' + outputNum(yS, precision: 3));
    commonSteps.add(r'y_{tar} = ' + outputNum(yL, precision: 3));

    // ================= 2. 几何求解 (找交点) =================
    double gTarget = yL.real;
    Complex gammaS = zToGamma(zS, z0);
    double rVSWR = gammaS.abs();

    double cx = -gTarget / (1 + gTarget);
    double rg = 1 / (1 + gTarget);

    double gMax = (1 + rVSWR) / (1 - rVSWR);
    double gMin = (1 - rVSWR) / (1 + rVSWR);

    if (gTarget > gMax + 1e-4 || gTarget < gMin - 1e-4) {
      commonSteps.add(r'\color{red}\text{No Solution: Target conductance circle does not intersect VSWR circle.}');
      return StubMatchingResult(solutions: [], commonSteps: commonSteps);
    }

    // 计算交点
    double u = (cx.abs() < 1e-9) ? 0 : ((rVSWR * rVSWR) - (rg * rg) + (cx * cx)) / (2 * cx);
    double vSq = (rVSWR * rVSWR) - (u * u);
    double v = (vSq < 0) ? 0 : sqrt(vSq);

    List<Complex> intersections = [Complex(u, v), Complex(u, -v)];

    // ================= 3. 生成解 (Short & Open) =================
    int solutionCount = 0;
    for (int i = 0; i < intersections.length; i++) {
      Complex gammaMidRaw = intersections[i];

      // --- 3.1 计算 d ---
      double angS = atan2(gammaS.imaginary, gammaS.real);
      double angM = atan2(gammaMidRaw.imaginary, gammaMidRaw.real);
      double deltaAng = angS - angM;
      while (deltaAng < 0) deltaAng += 2 * pi;

      double dLambda = deltaAng / (4 * pi);
      double dMm = dLambda * lambdaMm;

      // --- 3.2 计算中间导纳 yMid ---
      Complex zMidRaw = gammaToZ(gammaMidRaw, z0);
      Complex yMidRaw = Complex(z0, 0) / zMidRaw;
      Complex yMid = Complex(gTarget, yMidRaw.imaginary); // 强制校准实部
      Complex gammaMid = zToGamma(Complex(z0,0)/yMid, z0); // 反算精准 Gamma

      // --- 3.3 计算 Stub B ---
      Complex yDiff = yL - yMid;
      double bStub = yDiff.imaginary; // 需要并联的电纳值

      // ================= [新增] 同时计算 Short 和 Open 两种情况 =================

      // === Case A: Short Stub (短路支节) ===
      // cot(beta l) = -b  => tan(beta l) = -1/b
      double lLambdaShort = 0.0;
      if (bStub.abs() > 1e-6) {
        double theta = atan(-1.0 / bStub);
        if (theta < 0) theta += pi;
        lLambdaShort = theta / (2 * pi);
      } else {
        lLambdaShort = 0.25; // b=0 => infinite impedance => lambda/4 short stub
      }

      _addSolution(
          solutions, ++solutionCount, "Short",
          dLambda, dMm, lLambdaShort, lLambdaShort * lambdaMm,
          gammaS, gammaMid, zL, z0, gTarget, yMid, bStub, lambdaMm
      );

      // === Case B: Open Stub (开路支节) ===
      // tan(beta l) = b
      double lLambdaOpen = 0.0;
      if (bStub.abs() > 1e-6) { // b=0 => open circuit => l=0 (no stub needed)
        double theta = atan(bStub);
        if (theta < 0) theta += pi;
        lLambdaOpen = theta / (2 * pi);
      }

      _addSolution(
          solutions, ++solutionCount, "Open",
          dLambda, dMm, lLambdaOpen, lLambdaOpen * lambdaMm,
          gammaS, gammaMid, zL, z0, gTarget, yMid, bStub, lambdaMm
      );
    }

    return StubMatchingResult(solutions: solutions, commonSteps: commonSteps);
  }

  // 辅助函数：封装 Solution 添加逻辑，减少重复代码
  static void _addSolution(
      List<StubSolution> solutions,
      int index,
      String type,
      double dLambda, double dMm,
      double lLambda, double lMm,
      Complex gammaS, Complex gammaMid, Complex zL, double z0,
      double gTarget, Complex yMid, double bStub, double lambdaMm
      ) {
    List<String> steps = [];
    steps.add(r'\textbf{Solution ' + '$index' + r' (' + type + r' Stub):}');
    steps.add(r'\textbf{Step 2. Find Intersection Point:}');
    steps.add(r'\Gamma_{mid} \approx ' + outputNum(gammaMid, precision: 3));
    steps.add(r'y_{mid} \approx ' + outputNum(yMid, precision: 3));

    steps.add(r'\textbf{Step 3. Calculate Series Line Length } d:');
    steps.add(r'd = ' + outputNum(dLambda, precision: 4) + r'\lambda = ' + outputNum(dMm, precision: 2) + r'\;\mathrm{mm}');

    steps.add(r'\textbf{Step 4. Calculate Stub Length } l:');
    steps.add(r'\text{Required } jb_{stub} = j(' + outputNum(bStub, precision: 3) + r')');
    if (type == "Short") {
      steps.add(r'\text{For Short Stub: } \tan(\beta l) = -1/b');
    } else {
      steps.add(r'\text{For Open Stub: } \tan(\beta l) = b');
    }
    steps.add(r'l = ' + outputNum(lLambda, precision: 4) + r'\lambda = ' + outputNum(lMm, precision: 2) + r'\;\mathrm{mm}');

    List<SmithPath> paths = [];
    paths.add(SmithPath(
      startGamma: gammaS,
      endGamma: gammaMid,
      type: PathType.transmissionLine,
      label: "Line d",
    ));
    paths.add(SmithPath(
      startGamma: gammaMid,
      endGamma: zToGamma(zL, z0),
      type: PathType.shunt,
      label: "Stub ($type)",
    ));

    solutions.add(StubSolution(
      title: "Sol $index ($type)",
      stubType: type,
      dLengthMm: dMm,
      dLengthLambda: dLambda,
      stubLengthMm: lMm,
      stubLengthLambda: lLambda,
      steps: steps,
      paths: paths,
    ));
  }

  static Complex zToGamma(Complex z, double z0) {
    if (z.abs() > 1e9) return Complex(1,0);
    return (z - Complex(z0, 0)) / (z + Complex(z0, 0));
  }

  static Complex gammaToZ(Complex gamma, double z0) {
    if ((Complex(1,0)-gamma).abs() < 1e-9) return Complex(1e9, 0);
    return (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma) * Complex(z0, 0);
  }
}