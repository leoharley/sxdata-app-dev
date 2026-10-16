import 'package:flutter/services.dart';

/// Telefone brasileiro com DDD, no mesmo formato gravado pelo painel:
/// (DD) XXXX-XXXX (fixo, 10 dígitos) ou (DD) XXXXX-XXXX (celular, 11).

String phoneDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Aplica a máscara progressivamente, conforme os dígitos digitados.
String formatPhone(String value) {
  var d = phoneDigits(value);
  if (d.length > 11) d = d.substring(0, 11);
  if (d.isEmpty) return '';
  if (d.length <= 2) return '($d';
  if (d.length <= 6) return '(${d.substring(0, 2)}) ${d.substring(2)}';
  final meio = d.length == 11 ? 7 : 6;
  return '(${d.substring(0, 2)}) ${d.substring(2, meio)}-${d.substring(meio)}';
}

bool isValidPhone(String value) {
  final d = phoneDigits(value);
  return (d.length == 10 || d.length == 11) && d[0] != '0' && d[1] != '0';
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = phoneDigits(newValue.text);

    // Apagar um caractere da máscara ("-", ")", espaço) não muda os dígitos;
    // sem isto o texto voltaria igual e o backspace pareceria travado.
    final apagou = newValue.text.length < oldValue.text.length;
    if (apagou && digits == phoneDigits(oldValue.text) && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }

    final text = formatPhone(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
