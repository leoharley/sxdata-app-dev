import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sxdata/models/field_point.dart';
import 'package:sxdata/models/form_response.dart';
import 'package:sxdata/models/municipio_ibge.dart';
import 'package:sxdata/services/geo_municipio.dart';
import 'package:sxdata/services/point_queue.dart';

/// Pontos de campo do mapa integrado: modelo, validação "dentro do
/// município" e regras da fila (docs/API_PONTOS.md do painel).
void main() {
  FieldPoint ponto({String id = 'p1', DateTime? em, String status = 'pending'}) => FieldPoint(
        clientId: id,
        projectId: 4,
        codigoIbge: 1713601,
        municipioNome: 'Monte do Carmo',
        uf: 'TO',
        nome: 'Comunidade Serra Azul',
        latitude: -10.7611,
        longitude: -48.1114,
        origemCoord: 'gps',
        syncStatus: status,
        createdAt: em ?? DateTime(2026, 11, 1, 9),
      );

  group('FieldPoint', () {
    test('gravação local volta igual, com o mesmo client_id', () {
      final volta = FieldPoint.fromJson(ponto().toJson());
      expect(volta.clientId, 'p1');
      expect(volta.isPending, isTrue);
      expect(volta.latitude, -10.7611);
      expect(volta.municipioRotulo, 'Monte do Carmo - TO');
    });

    test('corpo do envio tem o que o painel pede, sem o controle da fila', () {
      final json = ponto().toApiJson();
      expect(json['client_id'], 'p1');
      expect(json['project_id'], 4);
      expect(json['codigo_ibge'], '1713601');
      expect(json.containsKey('sync_status'), isFalse);
    });

    test('sem coordenada não manda origem', () {
      final p = ponto().copyWith(limparCoordenada: true);
      expect(p.toApiJson()['latitude'], isNull);
      expect(p.toApiJson()['origem_coord'], isNull);
    });

    test('item de GET api/points vira ponto confirmado', () {
      final p = FieldPoint.fromJson({
        'id': 9,
        'client_id': 'p2',
        'project_id': '4',
        'codigo_ibge': 1713601,
        'nome': 'X',
        'tipo': 'quilombo',
        'dentro_municipio': false,
        'criado_em': '2026-11-11 01:36:31',
        'coletas': 3,
      }, doServidor: true);
      expect(p.serverId, 9);
      expect(p.isSynced, isTrue);
      expect(p.tipo, 'outro');
      expect(p.dentroMunicipio, isFalse);
      expect(p.coletas, 3);
      expect(p.createdAt.year, 2026);
    });

    test('sem projeto não é ponto válido', () {
      expect(() => FieldPoint.fromJson({'client_id': 'x', 'codigo_ibge': 1, 'nome': 'a'}),
          throwsFormatException);
    });
  });

  group('vínculo na coleta', () {
    FormResponse coleta({String? ponto}) => FormResponse(
          questionnaireId: 6,
          appliedBy: 17,
          consentGiven: true,
          clientId: 'c1',
          pointClientId: ponto,
          startedAt: DateTime(2026, 11, 1),
        );

    test('point_client_id vai no envio e volta da gravação local', () {
      final json = coleta(ponto: 'p1').toJson();
      expect(json['point_client_id'], 'p1');
      expect(FormResponse.fromJson(json).pointClientId, 'p1');
    });

    test('sem ponto o campo é omitido (edição mantém o vínculo do painel)', () {
      expect(coleta().toJson().containsKey('point_client_id'), isFalse);
    });

    test('copyWith mantém o vínculo e clearPointClientId tira', () {
      final c = coleta(ponto: 'p1');
      expect(c.copyWith(respondentName: 'A').pointClientId, 'p1');
      expect(c.copyWith(clearPointClientId: true).pointClientId, isNull);
    });
  });

  group('GeoMunicipio', () {
    final quadrado = {
      'type': 'Polygon',
      'coordinates': [
        [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
        [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
      ],
    };

    test('dentro, fora, borda e buraco', () {
      expect(GeoMunicipio.contem(quadrado, 2, 2), isTrue);
      expect(GeoMunicipio.contem(quadrado, 5, 11), isFalse);
      expect(GeoMunicipio.contem(quadrado, 5, 0), isTrue);
      expect(GeoMunicipio.contem(quadrado, 5, 5), isFalse);
    });

    test('MultiPolygon e malha inválida', () {
      final mp = {
        'type': 'MultiPolygon',
        'coordinates': [
          [[[0, 0], [1, 0], [1, 1], [0, 0]]],
          [[[5, 5], [6, 5], [6, 6], [5, 5]]],
        ],
      };
      expect(GeoMunicipio.contem(mp, 5.2, 5.8), isTrue);
      expect(GeoMunicipio.contem('lixo', 1, 1), isNull);
    });

    test('malha real do IBGE: Monte do Carmo', () {
      final malha = File('test/fixtures/malha_1713601.geojson').readAsStringSync();
      expect(GeoMunicipio.contem(malha, -10.7611, -48.1114), isTrue);
      expect(GeoMunicipio.contem(malha, -10.184, -48.3336), isFalse); // Palmas
      expect(GeoMunicipio.contornos(malha), isNotEmpty);
    });
  });

  group('PointQueue', () {
    test('envia só pendentes, do mais antigo ao mais novo', () {
      final lista = PointQueue.paraEnviar([
        ponto(id: 'b', em: DateTime(2026, 11, 2)),
        ponto(id: 'a', em: DateTime(2026, 11, 1)),
        ponto(id: 'c', status: 'synced'),
        ponto(id: 'd', status: 'error'),
      ]);
      expect(lista.map((p) => p.clientId), ['a', 'b']);
    });

    test('resposta com id confirma; sem id ou success=false continua pendente', () {
      final ok = PointQueue.aplicarResposta(
          ponto(), {'success': true, 'id': 7, 'dentro_municipio': false, 'aviso': 'fora'});
      expect(ok.isSynced, isTrue);
      expect(ok.serverId, 7);
      expect(ok.aviso, 'fora');
      expect(PointQueue.aplicarResposta(ponto(), {'success': true}).isPending, isTrue);
      expect(PointQueue.aplicarResposta(ponto(), {'success': false, 'id': 7}).isPending, isTrue);
      expect(PointQueue.extrairId({'data': {'point_id': '5'}}), 5);
    });

    test('mesclar: pendente do aparelho vale; confirmado vem do servidor; novo entra', () {
      final pendente = ponto(id: 'a').copyWith(nome: 'Versão nova');
      final confirmado = ponto(id: 'b', status: 'synced');
      final sumiu = ponto(id: 'c', status: 'synced');
      final remotos = [
        ponto(id: 'a', status: 'synced').copyWith(nome: 'Versão velha'),
        ponto(id: 'b', status: 'synced').copyWith(coletas: 4),
        ponto(id: 'z', status: 'synced'),
      ];
      final r = {
        for (final p in PointQueue.mesclar([pendente, confirmado, sumiu], remotos)) p.clientId: p,
      };
      expect(r['a']!.nome, 'Versão nova');
      expect(r['b']!.coletas, 4);
      expect(r.containsKey('z'), isTrue);
      expect(r.containsKey('c'), isFalse);
    });

    test('mesclar por projeto não apaga confirmados de outro projeto', () {
      final outro = ponto(id: 'x', status: 'synced').copyWith(projectId: 99);
      final r = PointQueue.mesclar([outro], const [], projetosConsultados: {4});
      expect(r.single.clientId, 'x');
    });

    test('doProjeto filtra projeto e município e deixa de fora os recusados', () {
      final lista = PointQueue.doProjeto([
        ponto(id: 'a').copyWith(nome: 'b'),
        ponto(id: 'b').copyWith(nome: 'A'),
        ponto(id: 'c').copyWith(projectId: 5),
        ponto(id: 'd', status: 'error'),
      ], 4, codigoIbge: 1713601);
      expect(lista.map((p) => p.nome), ['A', 'b']);
    });
  });

  group('MunicipioIbge.buscar', () {
    const lista = [
      MunicipioIbge(1713601, 'Monte do Carmo', 'TO'),
      MunicipioIbge(3550308, 'São Paulo', 'SP'),
      MunicipioIbge(3549904, 'São José dos Campos', 'SP'),
    ];

    test('sem acento, começa antes de contém, UF no fim', () {
      expect(MunicipioIbge.buscar(lista, 'sao').length, 2);
      expect(MunicipioIbge.buscar(lista, 'paulo').single.codigo, 3550308);
      expect(MunicipioIbge.buscar(lista, 'monte do carmo - to').single.codigo, 1713601);
      expect(MunicipioIbge.buscar(lista, 'sao paulo xx'), isEmpty);
      expect(MunicipioIbge.buscar(lista, 's'), isEmpty);
    });
  });
}
