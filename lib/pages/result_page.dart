import 'package:flutter/material.dart';
import 'package:complex/complex.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../models/impedance_data.dart';
import '../models/stub_mode.dart';
import '../models/stub_spacing.dart';
import '../utils/complex_utils.dart';
import '../utils/matching_calculator.dart';
import '../utils/single_stub_matching.dart';
import '../utils/stub_matching_calculator.dart';
import '../utils/Pi_matching_network.dart'; // Ensure correct import
import '../utils/T_matching_network.dart'; // Ensure correct import

import '../widgets/l_match_topology.dart';
import '../widgets/single_stub_topology.dart';
import '../widgets/double_stub_topology.dart';
import '../widgets/Pi_match_topology.dart';
import '../widgets/T_match_topology.dart';
import '../widgets/smithchart.dart';
import '../widgets/step_card_display.dart';

class ResultPage extends StatefulWidget {
  final ImpedanceData data;
  final String matchType;
  final StubMode stubMode;
  final StubSpacing? stubSpacing;

  ResultPage({
    required this.data,
    required this.matchType,
    this.stubMode = StubMode.single,
    this.stubSpacing,
  });

  @override
  _ResultPageState createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> with TickerProviderStateMixin {

  // Helper to get Complex Z from data (handles Z or Gamma input)
  Complex _getZValue(bool isTarget) {
    if (isTarget) {
      if (widget.data.zTarget != null) return widget.data.zTarget!;
      if (widget.data.gammaTarget != null) {
        return MatchingCalculator.gammaToZ(widget.data.gammaTarget!, widget.data.z0);
      }
    } else {
      if (widget.data.zInitial != null) return widget.data.zInitial!;
      if (widget.data.gammaInitial != null) {
        return MatchingCalculator.gammaToZ(widget.data.gammaInitial!, widget.data.z0);
      }
    }
    return Complex(widget.data.z0, 0); // Fallback
  }

  // ================== Input Summary (shown on result page) ==================
  Widget _buildInputSummaryCard(ImpedanceData data) {
    final Complex zInit = _getZValue(false);
    final Complex zTar = _getZValue(true);

    // Prefer the user's initial input when available; otherwise derive it.
    final Complex gammaInit = data.gammaInitial ?? zToGamma(zInit, data.z0);
    final Complex gammaTar = data.gammaTarget ?? zToGamma(zTar, data.z0);

    final bool isZMode = (data.zInitial != null || data.zTarget != null);
    final String modeLabel = isZMode ? 'Impedance (Z)' : 'Reflection (Γ)';

    final String fLatex = r'f = ' + _latexNumAuto(data.frequency, precision: 4) + r'\,\mathrm{Hz}';
    final String z0Latex = r'Z_0 = ' + _latexNumAuto(data.z0, precision: 4) + r'\,\Omega';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                const Text('Input Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(modeLabel, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _smallMath(fLatex),
                _smallMath(z0Latex),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _endpointBlock(
                    title: 'Initial',
                    color: Colors.green,
                    z: zInit,
                    gamma: gammaInit,
                    zSymbolLatex: r'Z_{\mathrm{init}}',
                    gammaSymbolLatex: r'\Gamma_{\mathrm{init}}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _endpointBlock(
                    title: 'Target',
                    color: Colors.red,
                    z: zTar,
                    gamma: gammaTar,
                    zSymbolLatex: r'Z_{\mathrm{tar}}',
                    gammaSymbolLatex: r'\Gamma_{\mathrm{tar}}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _latexNumAuto(num v, {int precision = 4}) {
    if (v.abs() < 1e-12) return '0';

    String _normalizeExp(String s) {
      // Normalize 10^{08} -> 10^{8}, 10^{-03} -> 10^{-3}
      return s.replaceAllMapped(
        RegExp(r'10\^\{(-?)0*([0-9]+)\}'),
            (m) => '10^{${m.group(1) ?? ''}${m.group(2)}}',
      );
    }

    final a = v.abs();
    // Use scientific notation only when values are very small/large (consistent with outputNum)
    if (a < 1e-3 || a >= 1e4) {
      // toStringAsExponential(d) uses d digits AFTER decimal.
      final sci = toLatexScientific(v, digits: ((precision - 1) < 0 ? 0 : (precision - 1)));
      return _normalizeExp(sci);
    }

    final s = v.toStringAsPrecision(precision);
    if (s.contains('e') || s.contains('E')) {
      final sci = toLatexScientific(v, digits: ((precision - 1) < 0 ? 0 : (precision - 1)));
      return _normalizeExp(sci);
    }
    return s;
  }

  String _complexToLatex(Complex c, {int precision = 4}) {
    final re = c.real;
    final im = c.imaginary;

    if (im.abs() < 1e-12) {
      return _latexNumAuto(re, precision: precision);
    }
    if (re.abs() < 1e-12) {
      return '${_latexNumAuto(im, precision: precision)}\\,\\mathrm{j}';
    }

    final reStr = _latexNumAuto(re, precision: precision);
    final imStr = _latexNumAuto(im.abs(), precision: precision);
    final sign = im >= 0 ? '+' : '-';
    return '$reStr $sign $imStr\\,\\mathrm{j}';
  }

  Widget _smallMath(String tex) {
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: const TextStyle(fontSize: 12, color: Colors.black87),
    );
  }

  Widget _endpointBlock({
    required String title,
    required Color color,
    required Complex z,
    required Complex gamma,
    required String zSymbolLatex,
    required String gammaSymbolLatex,
  }) {
    final zLatex = '$zSymbolLatex = ${_complexToLatex(z, precision: 4)}\\,\\Omega';
    final gLatex = '$gammaSymbolLatex = ${_complexToLatex(gamma, precision: 4)}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Math.tex(
            zLatex,
            mathStyle: MathStyle.text,
            textStyle: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Math.tex(
            gLatex,
            mathStyle: MathStyle.text,
            textStyle: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // L-Matching Component Value Display Helper
  Widget latexComponentEntry(String key, double value) {
    String keyLatex;
    if (key.contains('Series Inductance')) keyLatex = r'L_\mathrm{series}';
    else if (key.contains('Shunt Inductance')) keyLatex = r'L_\mathrm{shunt}';
    else if (key.contains('Series Capacitance')) keyLatex = r'C_\mathrm{series}';
    else if (key.contains('Shunt Capacitance')) keyLatex = r'C_\mathrm{shunt}';

    // Pi-Matching Keys
    else if (key == 'C_shunt1') keyLatex = r'C_1';
    else if (key == 'L_shunt1') keyLatex = r'L_1';
    else if (key == 'C_series') keyLatex = r'C_{series}';
    else if (key == 'L_series') keyLatex = r'L_{series}';
    else if (key == 'C_shunt2') keyLatex = r'C_2';
    else if (key == 'L_shunt2') keyLatex = r'L_2';

    // T-Matching Keys
    else if (key == 'L_series1') keyLatex = r'L_1';
    else if (key == 'C_series1') keyLatex = r'C_1';
    else if (key == 'L_shunt') keyLatex = r'L_{shunt}';
    else if (key == 'C_shunt') keyLatex = r'C_{shunt}';
    else if (key == 'L_series2') keyLatex = r'L_2';
    else if (key == 'C_series2') keyLatex = r'C_2';

    else keyLatex = key.replaceAll('(', r'\text{(').replaceAll(')', r'\text{)}');

    String unit = key.contains('(H)') || key.startsWith('L') ? r'\;\mathrm{H}' : r'\;\mathrm{F}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Math.tex(
        '$keyLatex = ${toLatexScientific(value, digits: 4)}$unit',
        textStyle: TextStyle(fontSize: 16, color: Colors.black87),
      ),
    );
  }

  // Single Stub Dimension Display Helper
  Widget latexDimensionEntry(String symbol, double valueMm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Math.tex(
        '$symbol = ${outputNum(valueMm, precision: 2)}\\,\\mathrm{mm}',
        textStyle: TextStyle(fontSize: 16, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ==================== L-Matching ====================
    if (widget.matchType == 'L-matching') {
      final result = MatchingCalculator.calculateLMatch(widget.data);

      // Even if solutions is not empty, it might contain the "Infeasible Case".
      // We render it normally so the user sees the explanation.
      if (result.solutions.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: Text('Result')),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputSummaryCard(widget.data),
                const SizedBox(height: 16),
                const Text('No solution found.', textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }

      return DefaultTabController(
        length: result.solutions.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text('L-Matching Result'),
            centerTitle: true,
            bottom: TabBar(
              isScrollable: true,
              tabs: result.solutions.map((s) => Tab(text: s.title)).toList(),
            ),
          ),
          body: TabBarView(
            children: result.solutions.map((solution) {
              return _buildSingleLMatchView(solution, result.commonSteps, widget.data);
            }).toList(),
          ),
        ),
      );
    }

    // ==================== Single Stub ====================
    else if (widget.matchType == 'single-stub') {
      final result = StubMatchingCalculator.calculateStubMatch(
        widget.data,
        mode: widget.stubMode,
        spacing: widget.stubSpacing ?? StubSpacing.lambdaOver8,
      );

      if (result.solutions.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: Text('No Solution')),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputSummaryCard(widget.data),
                const SizedBox(height: 16),
                if (result.commonSteps.isNotEmpty) ...[
                  StepCardDisplay(steps: result.commonSteps),
                  const SizedBox(height: 12),
                ],
                const Text('No solution found.', textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }

      return DefaultTabController(
        length: result.solutions.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.stubMode == StubMode.balanced
                  ? 'Balanced Stub Result'
                  : (widget.stubMode == StubMode.double ? 'Double Stub Result' : 'Single Stub Result'),
            ),
            centerTitle: true,
            bottom: TabBar(
              labelColor: Colors.blue[800],
              indicatorColor: Colors.blue[800],
              tabs: result.solutions.map((s) => Tab(text: s.title)).toList(),
            ),
          ),
          body: TabBarView(
            children: result.solutions.map((sol) {
              return _buildSingleStubView(sol, result.commonSteps, widget.data);
            }).toList(),
          ),
        ),
      );
    }

    // ==================== Pi Matching ====================
    else if (widget.matchType == 'Pi-matching') {
      final result = PiMatchingCalculator.calculatePiMatching(widget.data);

      return Scaffold(
        appBar: AppBar(
          title: Text('Pi-Matching Result'),
          centerTitle: true,
        ),
        body: _buildPiMatchView(result, widget.data),
      );
    }

    // ==================== T Matching ====================
    else if (widget.matchType == 'T-matching') {
      final result = TMatchingCalculator.calculateTMatching(widget.data);

      return Scaffold(
        appBar: AppBar(
          title: Text('T-Matching Result'),
          centerTitle: true,
        ),
        body: _buildTMatchView(result, widget.data),
      );
    }

    else {
      return Scaffold(body: Center(child: Text("Not Implemented")));
    }
  }

  // ================== T-Matching View ==================
  Widget _buildTMatchView(TMatchingResult result, ImpedanceData data) {
    String zInitStr = data.zInitial != null ? "Zinit = ${outputNum(data.zInitial!)}Ω" : "Source";
    String zTarStr = data.zTarget != null ? "Ztar = ${outputNum(data.zTarget!)}Ω" : "Load";

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildInputSummaryCard(data),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.filter_hdr, color: Colors.blue[800]),
              SizedBox(width: 8),
              Text('Topology: ${result.topology}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
            ],
          ),
          Divider(),
          SizedBox(height: 16),

          // Smith Chart
          Text("Smith Chart Trajectory", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: SmithChart(
                paths: result.paths,
                showAdmittance: true,
                zInitial: _getZValue(false), // Pass Start Z
                zTarget: _getZValue(true),    // Pass Target Z
                z0: widget.data.z0,
              ),
            ),
          ),
          SizedBox(height: 24),

          // Circuit Topology
          Text("Circuit Topology:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Center(
            child: TMatchTopology(
              values: result.values,
              zInitialStr: zInitStr,
              zTargetStr: zTarStr,
              width: 340,
              height: 220,
            ),
          ),
          Divider(),

          // Component Values
          Text("Component Values:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (result.values.isEmpty) Text("No valid components.", style: TextStyle(color: Colors.red)),

          ...result.values.entries.map((e) => latexComponentEntry(e.key, e.value)),

          Divider(),
          SizedBox(height: 12),

          // Steps
          Text('Step-by-Step Calculation:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          StepCardDisplay(steps: result.steps),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  // ================== Pi-Matching View ==================
  Widget _buildPiMatchView(PiMatchingResult result, ImpedanceData data) {
    String zInitStr = data.zInitial != null ? "Zinit = ${outputNum(data.zInitial!)}Ω" : "Source";
    String zTarStr = data.zTarget != null ? "Ztar = ${outputNum(data.zTarget!)}Ω" : "Load";

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildInputSummaryCard(data),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.filter_hdr, color: Colors.blue[800]),
              SizedBox(width: 8),
              Text('Topology: ${result.topology}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
            ],
          ),
          Divider(),
          SizedBox(height: 16),

          // Smith Chart
          Text("Smith Chart Trajectory", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: SmithChart(
                paths: result.paths,
                showAdmittance: true,
                zInitial: _getZValue(false),
                zTarget: _getZValue(true),
                z0: widget.data.z0,
              ),
            ),
          ),
          SizedBox(height: 24),

          Text("Circuit Topology:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Center(
            child: PiMatchTopology(
              values: result.values,
              zInitialStr: zInitStr,
              zTargetStr: zTarStr,
              width: 340,
              height: 200,
            ),
          ),
          Divider(),

          Text("Component Values:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (result.values.isEmpty) Text("No valid components.", style: TextStyle(color: Colors.red)),

          ...result.values.entries.map((e) => latexComponentEntry(e.key, e.value)),

          Divider(),
          SizedBox(height: 12),

          Text('Step-by-Step Calculation:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          StepCardDisplay(steps: result.steps),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  // ================== Single Stub View ==================
  Widget _buildSingleStubView(StubSolution solution, List<String> commonSteps, ImpedanceData data) {
    String mode = (data.zInitial != null) ? 'Z' : 'Gamma';
    final bool tlOnly = solution.stubType == 'None';

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildInputSummaryCard(data),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.electrical_services, color: Colors.blue[800]),
              SizedBox(width: 8),
              Text(
                solution.title,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900]),
              ),
            ],
          ),
          Divider(),
          SizedBox(height: 16),

          Text("Smith Chart Trajectory", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: SmithChart(
                paths: solution.paths,
                showAdmittance: true,
                zInitial: _getZValue(false),
                zTarget: _getZValue(true),
                z0: widget.data.z0,
              ),
            ),
          ),
          SizedBox(height: 24),

          Text("Circuit Topology:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Center(
            child: tlOnly
                ? SingleStubTopology(
                    mainLineLengthLambda: solution.dLengthLambda,
                    stubLengthLambda: 0,
                    isShortStub: true,
                    mode: mode,
                    stubMode: StubMode.single,
                    zTarget: data.zTarget,
                    zInitial: data.zInitial,
                    gammaTarget: data.gammaTarget,
                    gammaInitial: data.gammaInitial,
                    width: 340,
                    height: 200,
                  )
                : (widget.stubMode == StubMode.double && solution.stub2LengthLambda != null)
                    ? DoubleStubTopology(
                        mainLineLengthLambda: solution.dLengthLambda,
                        spacingLengthLambda: solution.spacingLengthLambda ?? 0.0,
                        stub1LengthLambda: solution.stubLengthLambda,
                        stub2LengthLambda: solution.stub2LengthLambda ?? 0.0,
                        isShortStub: solution.stubType == 'Short',
                        zTarget: data.zTarget,
                        zInitial: data.zInitial,
                        gammaTarget: data.gammaTarget,
                        gammaInitial: data.gammaInitial,
                        width: 340,
                        height: 200,
                      )
                    : SingleStubTopology(
                        mainLineLengthLambda: solution.dLengthLambda,
                        stubLengthLambda: solution.stubLengthLambda,
                        isShortStub: solution.stubType == 'Short',
                        mode: mode,
                        stubMode: widget.stubMode,
                        zTarget: data.zTarget,
                        zInitial: data.zInitial,
                        gammaTarget: data.gammaTarget,
                        gammaInitial: data.gammaInitial,
                        width: 340,
                        height: 200,
                      ),
          ),
          Divider(),

          Text("Physical Dimensions:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          latexDimensionEntry("d", solution.dLengthMm),
          if (!tlOnly) ...[
            if (widget.stubMode == StubMode.double) ...[
              if (solution.spacingLengthMm != null)
                latexDimensionEntry("s", solution.spacingLengthMm!),
              latexDimensionEntry(r'l_1', solution.stubLengthMm),
              if (solution.stub2LengthMm != null)
                latexDimensionEntry(r'l_2', solution.stub2LengthMm!),
            ] else
              latexDimensionEntry(
                widget.stubMode == StubMode.balanced ? r'l_{\mathrm{each}}' : 'l',
                solution.stubLengthMm,
              ),
          ],

          Divider(),
          SizedBox(height: 12),

          Text('Step-by-Step Calculation:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          StepCardDisplay(steps: [...commonSteps, ...solution.steps]),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  // ================== L-Matching View ==================
  Widget _buildSingleLMatchView(LMatchSolution solution, List<String> commonSteps, ImpedanceData data) {
    String zInitialValue = data.zInitial != null
        ? outputNum(data.zInitial!, precision: 2) + ' Ω'
        : (data.gammaInitial != null ? 'Γ=' + outputNum(data.gammaInitial!, precision: 2) : '');
    String zTargetValue = data.zTarget != null
        ? outputNum(data.zTarget!, precision: 2) + ' Ω'
        : (data.gammaTarget != null ? 'Γ=' + outputNum(data.gammaTarget!, precision: 2) : '');

    // Check if this is an "Infeasible Case" (has steps but no values)
    bool isInfeasible = solution.values.isEmpty && solution.steps.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildInputSummaryCard(data),
          SizedBox(height: 12),
          Text(solution.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isInfeasible ? Colors.red : Colors.blue[800])),
          SizedBox(height: 8),
          if (!isInfeasible)
            Text('Filter Type: ${solution.filterType}', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
          Divider(),

          SizedBox(height: 16),
          // 1. Smith Chart (Always show, even if infeasible, to show start/end points)
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: SmithChart(
                paths: solution.paths,
                showAdmittance: true,
                zInitial: _getZValue(false), // Pass Start Z
                zTarget: _getZValue(true),    // Pass Target Z
                z0: widget.data.z0,
              ),
            ),
          ),
          SizedBox(height: 24),

          // 2. Circuit Topology (Hide if infeasible)
          if (!isInfeasible) ...[
            Text('Circuit Topology:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Center(
              child: LMatchTopology(
                topology: solution.topologyType,
                values: solution.values,
                zInitialValue: zInitialValue,
                zTargetValue: zTargetValue,
                width: 340,
                height: 180,
              ),
            ),
            Divider(),
            Text('Component Values:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...solution.values.entries.map((e) => latexComponentEntry(e.key, e.value)),
            Divider(),
            SizedBox(height: 12),
          ],

          // 3. Steps (Always show, especially for error explanation)
          Text(isInfeasible ? 'Feasibility Analysis:' : 'Step-by-Step Solution:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          StepCardDisplay(
            steps: [...commonSteps, ...solution.steps],
          ),
          SizedBox(height: 30),
        ],
      ),
    );
  }
}
