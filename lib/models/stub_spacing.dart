/// Double-stub spacing options (between Stub1 and Stub2).
///
/// This project keeps a restricted set of practical spacings:
/// - λ/8  (t = tan(βs) = +1)
/// - 3λ/8 (t = tan(βs) = -1)
///
/// (We intentionally exclude λ/4 because tan(βs) is undefined there.)
enum StubSpacing {
  lambdaOver8,
  threeLambdaOver8,
}

extension StubSpacingExt on StubSpacing {
  /// Electrical length as a fraction of wavelength.
  double get lambdaFactor {
    switch (this) {
      case StubSpacing.lambdaOver8:
        return 1.0 / 8.0;
      case StubSpacing.threeLambdaOver8:
        return 3.0 / 8.0;
    }
  }

  /// tan(βs) where β = 2π/λ.
  ///
  /// - s = λ/8  => βs = π/4  => tan = +1
  /// - s = 3λ/8 => βs = 3π/4 => tan = -1
  double get t {
    switch (this) {
      case StubSpacing.lambdaOver8:
        return 1.0;
      case StubSpacing.threeLambdaOver8:
        return -1.0;
    }
  }

  String get label {
    switch (this) {
      case StubSpacing.lambdaOver8:
        return 'λ/8';
      case StubSpacing.threeLambdaOver8:
        return '3λ/8';
    }
  }
}
