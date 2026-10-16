import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sxdata/utils/phone_format.dart';

TextEditingValue _v(String t) =>
    TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

void main() {
  group('formatPhone', () {
    test('mascara progressivamente', () {
      expect(formatPhone(''), '');
      expect(formatPhone('9'), '(9');
      expect(formatPhone('93'), '(93');
      expect(formatPhone('939'), '(93) 9');
      expect(formatPhone('939912'), '(93) 9912');
      expect(formatPhone('9399123'), '(93) 9912-3');
      expect(formatPhone('9335231234'), '(93) 3523-1234');
      expect(formatPhone('93991234567'), '(93) 99123-4567');
    });

    test('ignora o que nao e digito e corta em 11', () {
      expect(formatPhone('(93) 99123-45678'), '(93) 99123-4567');
      expect(formatPhone('+55 93 3523 1234'), '(55) 93352-3123');
    });
  });

  group('isValidPhone', () {
    test('fixo e celular com DDD', () {
      expect(isValidPhone('(93) 3523-1234'), isTrue);
      expect(isValidPhone('(93) 99123-4567'), isTrue);
    });

    test('incompleto ou DDD invalido', () {
      expect(isValidPhone('(93) 9912-3'), isFalse);
      expect(isValidPhone('(03) 3523-1234'), isFalse);
      expect(isValidPhone('(90) 3523-1234'), isFalse);
      expect(isValidPhone(''), isFalse);
    });
  });

  group('PhoneInputFormatter', () {
    final f = PhoneInputFormatter();

    test('formata ao digitar', () {
      expect(f.formatEditUpdate(_v('(93) 9912'), _v('(93) 99123')).text, '(93) 9912-3');
    });

    test('backspace sobre o hifen apaga o digito anterior', () {
      // "(93) 9912-3" -> apagar o "3" deixa "(93) 9912-"
      expect(f.formatEditUpdate(_v('(93) 9912-3'), _v('(93) 9912-')).text, '(93) 9912');
      // apagar so o "-" nao pode travar: remove o digito anterior
      expect(f.formatEditUpdate(_v('(93) 9912-3'), _v('(93) 99123')).text, '(93) 9912');
      expect(f.formatEditUpdate(_v('(93) 9'), _v('(93) ')).text, '(93');
    });
  });
}
