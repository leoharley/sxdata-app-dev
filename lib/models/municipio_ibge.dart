/// Município do IBGE para a escolha do município do ponto. A lista completa
/// (5.571) é baixada uma vez da API de localidades do IBGE e guardada no
/// aparelho, então a busca funciona offline.
///
/// Dart puro (sem Flutter).
class MunicipioIbge {
  final int codigo;
  final String nome;
  final String uf;

  const MunicipioIbge(this.codigo, this.nome, this.uf);

  String get rotulo => '$nome - $uf';

  /// Formato compacto guardado no aparelho: [codigo, nome, uf].
  List<dynamic> toCompact() => [codigo, nome, uf];

  static MunicipioIbge? fromCompact(dynamic v) {
    if (v is List && v.length >= 3 && v[0] is num) {
      return MunicipioIbge((v[0] as num).toInt(), v[1].toString(), v[2].toString());
    }
    return null;
  }

  /// Item de servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado
  static MunicipioIbge? fromIbgeNivelado(dynamic v) {
    if (v is! Map) return null;
    final codigo = int.tryParse('${v['municipio-id']}');
    final nome = v['municipio-nome']?.toString();
    final uf = v['UF-sigla']?.toString();
    if (codigo == null || nome == null || uf == null) return null;
    return MunicipioIbge(codigo, nome, uf);
  }

  /// Busca sem acento e sem diferença de maiúsculas; quem começa com o termo
  /// vem antes de quem só contém. "sp" ou "monte do carmo to" filtram a UF.
  static List<MunicipioIbge> buscar(List<MunicipioIbge> lista, String termo,
      {int limite = 20, bool detectarUf = true}) {
    var t = normalizar(termo);
    if (t.length < 2) return const [];

    String? uf;
    final partes = t.split(' ');
    if (detectarUf && partes.length > 1 && partes.last.length == 2) {
      uf = partes.last.toUpperCase();
      t = partes.sublist(0, partes.length - 1).join(' ').replaceAll(RegExp(r'\s*-$'), '').trim();
    }

    final comeca = <MunicipioIbge>[];
    final contem = <MunicipioIbge>[];
    for (final m in lista) {
      if (uf != null && m.uf != uf) continue;
      final n = normalizar(m.nome);
      if (n.startsWith(t)) {
        comeca.add(m);
      } else if (n.contains(t)) {
        contem.add(m);
      }
    }
    // "xx" no fim não era UF (ou não há município com ela): busca o termo inteiro
    if (uf != null && comeca.isEmpty && contem.isEmpty) {
      return buscar(lista, termo, limite: limite, detectarUf: false);
    }
    int ordem(MunicipioIbge a, MunicipioIbge b) => normalizar(a.nome).compareTo(normalizar(b.nome));
    comeca.sort(ordem);
    contem.sort(ordem);
    return [...comeca, ...contem].take(limite).toList();
  }

  static String normalizar(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    return b.toString().replaceAll(RegExp(r"[^a-z0-9' -]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
