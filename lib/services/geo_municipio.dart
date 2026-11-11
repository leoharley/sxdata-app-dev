import 'dart:convert';
import 'dart:math' as math;

/// "Esta coordenada cai dentro do município?" — mesma regra da classe
/// Geo_municipio do painel (ray casting, MultiPolygon, buracos, borda conta
/// como dentro). O app usa para avisar o aplicador na hora, mesmo offline,
/// quando a malha do município já está guardada no aparelho.
///
/// Dart puro (sem Flutter). Coordenadas GeoJSON: [longitude, latitude].
class GeoMunicipio {
  GeoMunicipio._();

  /// Tolerância da borda, em graus (~1 cm no equador).
  static const double eps = 1e-7;

  /// true dentro, false fora, null se a malha não tem polígono.
  static bool? contem(dynamic geojson, double lat, double lng) {
    final poligonos = poligonosDe(geojson);
    if (poligonos.isEmpty) return null;
    for (final aneis in poligonos) {
      if (_noPoligono(aneis, lng, lat)) return true;
    }
    return false;
  }

  /// Anéis externos de cada polígono, como [[lat, lng], ...], para desenhar
  /// o contorno no flutter_map.
  static List<List<List<double>>> contornos(dynamic geojson) => [
        for (final aneis in poligonosDe(geojson))
          [for (final p in aneis.first) [p[1], p[0]]],
      ];

  /// Lista de polígonos; cada um é uma lista de anéis (o primeiro é o
  /// externo); cada anel é uma lista de [x, y].
  static List<List<List<List<double>>>> poligonosDe(dynamic geojson) {
    if (geojson is String) {
      try {
        geojson = jsonDecode(geojson);
      } catch (_) {
        return const [];
      }
    }
    if (geojson is! Map) return const [];

    switch (geojson['type']) {
      case 'FeatureCollection':
        return [
          for (final f in (geojson['features'] as List? ?? const [])) ...poligonosDe(f),
        ];
      case 'Feature':
        return poligonosDe(geojson['geometry']);
      case 'GeometryCollection':
        return [
          for (final g in (geojson['geometries'] as List? ?? const [])) ...poligonosDe(g),
        ];
      case 'Polygon':
        final p = _aneis(geojson['coordinates']);
        return p == null ? const [] : [p];
      case 'MultiPolygon':
        return [
          for (final c in (geojson['coordinates'] as List? ?? const []))
            if (_aneis(c) case final p?) p,
        ];
    }
    return const [];
  }

  static bool _noPoligono(List<List<List<double>>> aneis, double x, double y) {
    final externo = aneis.first;
    if (_naBorda(externo, x, y)) return true;
    if (!_noAnel(externo, x, y)) return false;
    for (var i = 1; i < aneis.length; i++) {
      if (_naBorda(aneis[i], x, y)) return true; // borda do buraco ainda é divisa
      if (_noAnel(aneis[i], x, y)) return false;
    }
    return true;
  }

  static bool _noAnel(List<List<double>> anel, double x, double y) {
    var dentro = false;
    for (var i = 0, j = anel.length - 1; i < anel.length; j = i++) {
      final xi = anel[i][0], yi = anel[i][1];
      final xj = anel[j][0], yj = anel[j][1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        dentro = !dentro;
      }
    }
    return dentro;
  }

  static bool _naBorda(List<List<double>> anel, double x, double y) {
    for (var i = 0, j = anel.length - 1; i < anel.length; j = i++) {
      if (_noSegmento(anel[j], anel[i], x, y)) return true;
    }
    return false;
  }

  static bool _noSegmento(List<double> a, List<double> b, double x, double y) {
    if (x < math.min(a[0], b[0]) - eps || x > math.max(a[0], b[0]) + eps ||
        y < math.min(a[1], b[1]) - eps || y > math.max(a[1], b[1]) + eps) {
      return false;
    }
    final dx = b[0] - a[0], dy = b[1] - a[1];
    final comp = math.sqrt(dx * dx + dy * dy);
    if (comp == 0) return (x - a[0]).abs() <= eps && (y - a[1]).abs() <= eps;
    return (dy * (x - a[0]) - dx * (y - a[1])).abs() / comp <= eps;
  }

  static List<List<List<double>>>? _aneis(dynamic coords) {
    if (coords is! List) return null;
    final aneis = <List<List<double>>>[];
    for (final anel in coords) {
      final pontos = <List<double>>[];
      if (anel is List) {
        for (final p in anel) {
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
            pontos.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
          }
        }
      }
      if (pontos.length >= 3) {
        aneis.add(pontos);
      } else if (aneis.isEmpty) {
        return null; // sem anel externo não há polígono
      }
    }
    return aneis.isEmpty ? null : aneis;
  }
}
