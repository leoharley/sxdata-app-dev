import 'package:flutter_test/flutter_test.dart';
import 'package:sxdata/utils/ambiente.dart';

void main() {
  test('painel.sxdata.com.br é Produção', () {
    expect(Ambiente.daApi('https://painel.sxdata.com.br/api').nome, 'Produção');
  });

  test('sxdata.online e subdomínios são Evolução', () {
    expect(Ambiente.daApi('https://painel.sxdata.online/api').nome, 'Evolução');
    expect(Ambiente.daApi('https://sxdata.online/api').nome, 'Evolução');
  });

  test('não confunde domínio parecido com a evolução', () {
    expect(Ambiente.daApi('https://falso-sxdata.online.exemplo.com/api').nome,
        isNot('Evolução'));
  });

  test('outro servidor mostra o próprio endereço', () {
    expect(Ambiente.daApi('http://localhost:8080/api').nome, 'localhost');
  });

  test('endereço inválido não quebra', () {
    expect(Ambiente.daApi('').nome, 'Ambiente desconhecido');
  });
}
