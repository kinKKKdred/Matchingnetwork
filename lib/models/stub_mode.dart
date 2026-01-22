/// Stub implementation mode within the (single-)stub matching module.
///
/// - [single]: one shunt stub.
/// - [balanced]: two identical shunt stubs in parallel (balanced implementation).
/// - [double]: two shunt stubs separated by a fixed spacing on the main line.
enum StubMode {
  single,
  balanced,
  double,
}
