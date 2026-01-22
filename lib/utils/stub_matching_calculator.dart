import '../models/impedance_data.dart';
import '../models/stub_mode.dart';
import '../models/stub_spacing.dart';

import './single_stub_matching.dart';
import './balanced_stub_matching.dart';
import './double_stub_matching.dart';

/// A small dispatcher that routes stub matching requests to the corresponding
/// solver (single / balanced). This keeps ResultPage/UI logic stable while
/// allowing new stub variants to be added later.
class StubMatchingCalculator {
  static StubMatchingResult calculateStubMatch(
    ImpedanceData data, {
    StubMode mode = StubMode.single,
    StubSpacing spacing = StubSpacing.lambdaOver8,
  }) {
    switch (mode) {
      case StubMode.single:
        return SingleStubMatchingCalculator.calculateStubMatch(data);
      case StubMode.balanced:
        return BalancedStubMatchingCalculator.calculateStubMatch(data);
      case StubMode.double:
        return DoubleStubMatchingCalculator.calculateStubMatch(
          data,
          spacing: spacing,
        );
    }
  }
}
