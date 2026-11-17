/// A credit value as the school writes it: at most two decimals, without the trailing zeros
/// a double carries. 0.30000000000000004 reads as 0.3, and 3.0 as 3.
String formatCredits(double value) {
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
