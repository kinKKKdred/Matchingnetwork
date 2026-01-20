import 'package:flutter/material.dart';
import 'package:complex/complex.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../models/impedance_data.dart';
import '../utils/complex_utils.dart';
import '../utils/matching_calculator.dart';
import '../utils/single_stub_matching.dart';
import '../utils/Pi_matching_network.dart'; // Ensure correct import
import '../utils/T_matching_network.dart'; // Ensure correct import

import '../widgets/l_match_topology.dart';
import '../widgets/single_stub_topology.dart';
import '../widgets/Pi_match_topology.dart';
import '../widgets/T_match_topology.dart';
import '../widgets/smithchart.dart';
import '../widgets/step_card_display.dart';

class ResultPage extends StatefulWidget {
  final ImpedanceData data;
  final String matchType;

  ResultPage({required this.data, required this.matchType});

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
      if (widget.data.zOriginal != null) return widget.data.zOriginal!;
      if (widget.data.gammaOriginal != null) {
        return MatchingCalculator.gammaToZ(widget.data.gammaOriginal!, widget.data.z0);
      }
    }
    return Complex(widget.data.z0, 0); // Fallback
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
        return Scaffold(appBar: AppBar(title: Text('Result')), body: Center(child: Text('No solution found.')));
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
      final result = SingleStubMatchingCalculator.calculateStubMatch(widget.data);

      if (result.solutions.isEmpty) {
        return Scaffold(appBar: AppBar(title: Text('No Solution')), body: Center(child: Text('No solution found.')));
      }

      return DefaultTabController(
        length: result.solutions.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Single Stub Result'),
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
    String zOriStr = data.zOriginal != null ? "Z_ori = ${outputNum(data.zOriginal!)}Ω" : "Source";
    String zTarStr = data.zTarget != null ? "Z_tar = ${outputNum(data.zTarget!)}Ω" : "Load";

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
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
                zOriginal: _getZValue(false), // Pass Start Z
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
              zOriginalStr: zOriStr,
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
    String zOriStr = data.zOriginal != null ? "Z_ori = ${outputNum(data.zOriginal!)}Ω" : "Source";
    String zTarStr = data.zTarget != null ? "Z_tar = ${outputNum(data.zTarget!)}Ω" : "Load";

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
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
                zOriginal: _getZValue(false),
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
              zOriginalStr: zOriStr,
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
    String mode = (data.zOriginal != null) ? 'Z' : 'Gamma';

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            children: [
              Icon(Icons.electrical_services, color: Colors.blue[800]),
              SizedBox(width: 8),
              Text('${solution.title}: ${solution.stubType} Stub',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[900])),
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
                zOriginal: _getZValue(false),
                zTarget: _getZValue(true),
                z0: widget.data.z0,
              ),
            ),
          ),
          SizedBox(height: 24),

          Text("Circuit Topology:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Center(
            child: SingleStubTopology(
              mainLineLengthLambda: solution.dLengthLambda,
              stubLengthLambda: solution.stubLengthLambda,
              isShortStub: solution.stubType == 'Short',
              mode: mode,
              zTarget: data.zTarget,
              zOriginal: data.zOriginal,
              gammaTarget: data.gammaTarget,
              gammaOriginal: data.gammaOriginal,
              width: 340,
              height: 200,
            ),
          ),
          Divider(),

          Text("Physical Dimensions:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          latexDimensionEntry("d", solution.dLengthMm),
          latexDimensionEntry("l", solution.stubLengthMm),

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
    String zOriginalValue = data.zOriginal != null
        ? outputNum(data.zOriginal!, precision: 2) + ' Ω'
        : (data.gammaOriginal != null ? 'Γ=' + outputNum(data.gammaOriginal!, precision: 2) : '');
    String zTargetValue = data.zTarget != null
        ? outputNum(data.zTarget!, precision: 2) + ' Ω'
        : (data.gammaTarget != null ? 'Γ=' + outputNum(data.gammaTarget!, precision: 2) : '');

    // Check if this is an "Infeasible Case" (has steps but no values)
    bool isInfeasible = solution.values.isEmpty && solution.steps.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(16),
      child: ListView(
        children: [
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
                zOriginal: _getZValue(false), // Pass Start Z
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
                zOriginalValue: zOriginalValue,
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