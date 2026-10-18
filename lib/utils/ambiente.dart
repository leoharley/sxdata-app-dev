import 'package:flutter/material.dart';

/// Ambiente para o qual o app foi compilado, deduzido do endereço da API
/// (`--dart-define=API_BASE_URL`). Serve para distinguir, no web app, a
/// produção (painel.sxdata.com.br/app) da evolução (sxdata.online).
class Ambiente {
  final String nome;
  final Color cor;

  const Ambiente(this.nome, this.cor);

  static Ambiente daApi(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';

    if (host == 'painel.sxdata.com.br') {
      return const Ambiente('Produção', Color(0xFF8FAE5D));
    }
    if (host == 'sxdata.online' || host.endsWith('.sxdata.online')) {
      return const Ambiente('Evolução', Color(0xFFF39C12));
    }
    // Qualquer outro servidor (local, homologação): mostra o próprio endereço
    return Ambiente(host.isEmpty ? 'Ambiente desconhecido' : host, Colors.grey);
  }
}
