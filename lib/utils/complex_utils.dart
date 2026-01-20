import 'package:complex/complex.dart';
import 'dart:math';
import 'package:flutter/material.dart';

/// 字符串转复数（支持常见输入格式）
Complex parseComplex(String input) {
  input = input.replaceAll(' ', '').toLowerCase();
  RegExp reg = RegExp(r'^([+-]?\d+(\.\d+)?)([+-]j\d+(\.\d+)?)?$');
  RegExp regJ = RegExp(r'^([+-]?j\d+(\.\d+)?)$');

  if (reg.hasMatch(input)) {
    var match = reg.firstMatch(input)!;
    double real = double.parse(match.group(1)!);
    double imag = 0.0;
    if (match.group(3) != null) {
      imag = double.parse(match.group(3)!.replaceAll('j', ''));
    }
    return Complex(real, imag);
  } else if (regJ.hasMatch(input)) {
    var match = regJ.firstMatch(input)!;
    double imag = double.parse(match.group(1)!.replaceAll('j', ''));
    return Complex(0, imag);
  } else {
    throw FormatException('复数格式错误（应为 30+j40 或 30-j20）');
  }
}

/// 复数转字符串，便于输入框展示
String complexToInputString(Complex c) {
  String re = c.real.toStringAsFixed(4);
  String im = c.imaginary.abs().toStringAsFixed(4);
  String sign = c.imaginary >= 0 ? "+" : "-";
  return "$re$sign" "j$im";
}

/// 阻抗转反射系数
Complex zToGamma(Complex z, double z0) =>
    (z - Complex(z0, 0)) / (z + Complex(z0, 0));

/// 反射系数转阻抗
Complex gammaToZ(Complex gamma, double z0) =>
    (Complex(1, 0) + gamma) / (Complex(1, 0) - gamma) * Complex(z0, 0);

/// 直角坐标转极坐标
List<double> rectToPolar(Complex c, {bool inDegree = true}) {
  double mag = c.abs();
  double ang = c.argument();
  if (inDegree) ang = ang * 180 / pi;
  return [mag, ang];
}

/// 极坐标转直角坐标
Complex polarToComplex(double mag, double ang, {bool inDegree = true}) {
  if (inDegree) ang = ang * pi / 180.0;
  return Complex(mag * cos(ang), mag * sin(ang));
}

/// ======= 数值优雅格式化主函数 =======
/// 支持实数、复数（代数/极坐标）、负数加括号、科学计数法等多种情况
/// [a]：输入可以是num/Complex/String
/// [withBracket]：是否需要负数/复数加括号
/// [precision]：有效数字位数
/// [isPolar]：复数是否用极坐标格式
String outputNum(
    dynamic a, {
      bool withBracket = false,
      int precision = 4,
      bool isPolar = false,
    }) {
  String numString = "";
  String realStr(double v) => v.toStringAsPrecision(precision);

  // 若是复数且虚部极小，按实数处理
  if (a is Complex && a.imaginary.abs() <= 1e-12) {
    a = a.real;
  }

  if (a is Complex) {
    // 复数模式
    if (isPolar) {
      // 极坐标格式：模∠角度°
      numString =
          scientificNotationStr(realStr(a.abs())) +
              '∠' +
              scientificNotationStr(realStr(a.argument() * 180 / pi)) +
              '°';
    } else {
      // 代数格式：实部+虚部j
      if (a.real.abs() > 1e-12) {
        numString = scientificNotationStr(realStr(a.real));
        if (a.imaginary > 0) {
          numString += '+';
        }
      }
      numString += scientificNotationStr(realStr(a.imaginary));
      numString += 'j';
    }
  } else if (a is String) {
    // 字符串直接输出
    numString = a;
  } else if (a is num) {
    // 实数
    if (a.abs() < 1e-12) {
      numString = '0';
    } else {
      numString = scientificNotationStr(a.toStringAsPrecision(precision));
    }
  } else {
    numString = a.toString();
  }

  // 括号处理
  if (withBracket) {
    if (a is num && a < 0) {
      numString = '($numString)';
    } else if (a is Complex || a is String) {
      numString = '($numString)';
    }
  }

  return numString;
}

/// ======= 科学计数法字符串美化 =======
/// 如 1.23e4 转为 1.23×10^4（只做字符串转换，不带任何富文本/Widget）
/// 可扩展为latex模式（如需）
/// 只用于字符串拼接
String scientificNotationStr(String numStr) {
  if (!(numStr.contains('e') || numStr.contains('E'))) {
    return numStr;
  }
  numStr = numStr.replaceAll('e+0', 'e');
  numStr = numStr.replaceAll('e+', 'e');
  numStr = numStr.replaceAll('e-0', 'e-');
  var strList = numStr.split(RegExp(r'[eE]'));
  return "${strList[0]}×10^${strList[1]}";
}

/// ====== UI科学计数法美化展示（保留原Widget代码） ======
/// 美观显示结果数值（支持科学计数法转为 2.65 × 10¹¹ 格式，并带单位）
Widget result_display(dynamic number, {String? unit, TextStyle? style}) {
  String str;
  if (number is num) {
    // 科学计数法时转为四位小数
    if (number.abs() < 1e-3 || number.abs() >= 1e4) {
      str = number.toStringAsExponential(4);
    } else {
      str = number.toStringAsFixed(4);
    }
  } else {
    str = number.toString();
  }

  if (str.contains('e') || str.contains('E')) {
    var parts = str.split(RegExp(r'[eE]'));
    var base = double.parse(parts[0]).toStringAsFixed(4);
    var exp = parts[1];
    if (exp.startsWith('+')) exp = exp.substring(1);
    return RichText(
      text: TextSpan(
        style: style ?? const TextStyle(color: Colors.black),
        children: [
          TextSpan(text: base),
          TextSpan(text: ' × 10'),
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Transform.translate(
              offset: const Offset(1, -6),
              child: Text(
                exp,
                textScaleFactor: 0.7,
                style: style?.copyWith(fontSize: 12) ??
                    const TextStyle(fontSize: 12, color: Colors.black),
              ),
            ),
          ),
          if (unit != null) TextSpan(text: ' $unit', style: style),
        ],
      ),
    );
  }
  // 不是科学计数法，原样保留四位小数
  return Text('$str${unit != null ? ' $unit' : ''}', style: style);
}

/// 转latex科学计数法字符串
String toLatexScientific(dynamic number, {int? digits}) {
  String str;
  if (digits != null && number is num) {
    str = number.toStringAsExponential(digits);
  } else {
    str = number.toString();
  }
  if (str.contains('e') || str.contains('E')) {
    var parts = str.split(RegExp(r'[eE]'));
    var base = parts[0];
    var exp = parts[1];
    if (exp.startsWith('+')) exp = exp.substring(1);
    return '$base \\times 10^{${exp}}';
  }
  return str;
}
