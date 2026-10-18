import 'dart:io';

/// Corrige o service worker gerado pelo Flutter para o app abrir OFFLINE
/// quando publicado em um SUBDIRETÓRIO (ex.: /app/) em vez da raiz.
///
/// PROBLEMAS DO WORKER ORIGINAL NESTE CENÁRIO
///
/// 1. Chave do cache calculada pelo ORIGIN:
///
///        var key = request.url.substring(origin.length + 1);
///
///    Em /app/ isso dá "app/main.dart.js", e RESOURCES guarda "main.dart.js".
///    Nada bate:
///    - o fetch devolvia tudo ao navegador e, sem internet, a página ficava
///      em branco (ou "Você está off-line");
///    - o activate de cada versão nova achava que NENHUM arquivo do cache
///      existia mais e apagava todos: a cada deploy o app voltava a depender
///      da rede para abrir.
///
/// 2. Só 5 arquivos são baixados na instalação (main.dart.js, index.html,
///    flutter_bootstrap.js e dois manifestos). O motor gráfico (CanvasKit),
///    as fontes e as imagens só entravam no cache quando o app os pedia com
///    o worker já no controle — nunca no primeiro acesso. No iPhone, o app
///    da tela de início tem armazenamento separado do Safari, e o que o
///    Safari guardou não vale para ele.
///
/// 3. Abrir o app pedia o index.html à rede SEM PRAZO: com sinal fraco (rede
///    conectada sem internet de verdade) a abertura ficava em tela branca.
///
/// CORREÇÃO
/// - Chave relativa ao ESCOPO do worker, também no activate e no
///   downloadOffline do Flutter.
/// - Depois de ativado, o worker baixa o resto do app (mensagem
///   'sxdataPrecache', enviada pelo index.html a cada abertura com rede;
///   só o que falta é baixado).
/// - Navegação e version.json: rede com prazo de 4 s, depois o cache.
///
/// Exige build com --no-web-resources-cdn: sem isso o CanvasKit vem do CDN
/// do Google (gstatic.com), que o worker não guarda, e offline nada aparece.
///
/// Uso: dart run tool/patch_service_worker.dart [caminho]
/// (padrão: build/web/flutter_service_worker.js)
void main(List<String> args) {
  final caminho =
      args.isNotEmpty ? args.first : 'build/web/flutter_service_worker.js';
  final arquivo = File(caminho);

  if (!arquivo.existsSync()) {
    stderr.writeln('❌ Não encontrado: $caminho');
    stderr.writeln('   Rode o "flutter build web" antes.');
    exit(1);
  }

  // O CanvasKit tem que vir do próprio site, senão o cache offline não o tem
  final bootstrap = File('${arquivo.parent.path}/flutter_bootstrap.js');
  if (!bootstrap.existsSync() ||
      !bootstrap.readAsStringSync().contains('"useLocalCanvasKit":true')) {
    stderr.writeln('❌ Este build carrega o CanvasKit do CDN do Google '
        '(gstatic.com): sem internet o app não abre.');
    stderr.writeln('   Compile de novo com --no-web-resources-cdn.');
    exit(1);
  }

  final original = arquivo.readAsStringSync();

  if (original.contains(_marcador)) {
    print('ℹ️ Service worker já corrigido — nada a fazer.');
    return;
  }

  // O handler precisa vir ANTES do handler do Flutter: o primeiro que
  // chamar respondWith vence.
  const ancora = "self.addEventListener(\"fetch\", (event) => {";
  if (!original.contains(ancora)) {
    stderr.writeln('❌ Handler de fetch não encontrado — o formato do '
        'service worker mudou. Revise este script.');
    exit(1);
  }

  // Chave pelo origin no activate e no downloadOffline (o fetch do Flutter
  // usa "event.request.url...", que o lookbehind deixa de fora: o nosso
  // handler vem antes dele)
  final chavePeloOrigin =
      RegExp(r'(?<![.\w])request\.url\.substring\(origin\.length \+ 1\)');
  final ocorrencias = chavePeloOrigin.allMatches(original).length;
  if (ocorrencias != 2) {
    stderr.writeln('❌ Esperava 2 cálculos de chave pelo origin (activate e '
        'downloadOffline), achei $ocorrencias — o formato do service worker '
        'mudou. Revise este script.');
    exit(1);
  }

  final corrigido = original
      .replaceAll(chavePeloOrigin, 'sxChave(request.url)')
      .replaceFirst(ancora, '$_patch\n\n$ancora');
  arquivo.writeAsStringSync(corrigido);

  print('✅ Service worker corrigido para funcionar offline em subdiretório.');
  print('   Chave pelo escopo ($ocorrencias pontos), pré-carga completa e '
      'prazo de rede na abertura.');
}

const _marcador = 'SXDATA_OFFLINE_SUBDIR_FIX';

const _patch = '''
// $_marcador
// -----------------------------------------------------------------------
// Fazer o app abrir OFFLINE quando publicado em um SUBDIRETÓRIO (/app/).
// Explicação completa em tool/patch_service_worker.dart, no sxdata-app.
// -----------------------------------------------------------------------

// Chave de um recurso relativa ao ESCOPO do worker ("main.dart.js"), não ao
// origin ("app/main.dart.js"). Declaração de função: é içada, então vale
// também no activate e no downloadOffline do Flutter, onde o patch a usa.
function sxChave(url) {
  var escopo = new URL(self.registration.scope).pathname;
  var u = new URL(url);
  if (u.origin !== self.location.origin || u.pathname.indexOf(escopo) !== 0) {
    return u.href;   // fora do app: nunca casa com RESOURCES
  }
  var chave = u.pathname.substring(escopo.length);
  return chave === '' ? '/' : chave;
}

(function () {
  // Rede com prazo: sinal fraco não pode segurar a abertura do app
  const PRAZO_REDE_MS = 4000;

  function comPrazo(promessa, ms) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('prazo')), ms);
      promessa.then(
        (valor) => { clearTimeout(timer); resolve(valor); },
        (erro) => { clearTimeout(timer); reject(erro); }
      );
    });
  }

  // Rede primeiro, com prazo; se falhar, demorar ou responder com erro
  // (servidor em manutenção, 5xx), a cópia guardada em "chaveCache". Uma
  // resposta boa da rede atualiza a cópia, mesmo se chegar depois do prazo.
  function redeComPrazo(request, chaveCache, semCache) {
    const rede = fetch(request).then((response) => {
      if (response && response.ok) {
        const copia = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(chaveCache, copia));
      }
      return response;
    });
    rede.catch(() => {});   // falha depois do prazo: já respondemos do cache

    const guardado = () => caches.open(CACHE_NAME)
      .then((cache) => cache.match(chaveCache, { ignoreVary: true }));

    return comPrazo(rede, PRAZO_REDE_MS).then(
      // A rede respondeu: com erro, prefere a cópia; sem cópia, o próprio erro
      (response) => (response && response.ok)
        ? response
        : guardado().then((copia) => copia || response),
      // Sem rede ou estourou o prazo
      () => guardado().then((copia) => {
        if (copia) return copia;
        if (semCache) return semCache();
        return rede;   // nada guardado: espera a rede, sem prazo
      })
    );
  }

  self.addEventListener('fetch', (event) => {
    if (event.request.method !== 'GET') return;

    // --- Navegação: sempre o index.html ---------------------------------
    if (event.request.mode === 'navigate') {
      event.respondWith(
        redeComPrazo(event.request, 'index.html', () => {
          return new Response(
            '<h1>App indisponível offline</h1>' +
            '<p>Abra o aplicativo uma vez com internet para que ele ' +
            'fique disponível sem conexão.</p>',
            { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
          );
        })
      );
      return;
    }

    let key = sxChave(event.request.url);
    if (!RESOURCES[key]) return;              // não é recurso do app

    // --- version.json (vem com ?cachebuster=): rede com prazo -----------
    if (key === 'version.json') {
      event.respondWith(redeComPrazo(event.request, 'version.json'));
      return;
    }

    // --- Demais recursos: cache primeiro --------------------------------
    // Casa pela própria Request e, se não achar, pela chave sem a query
    // string (é assim que a pré-carga abaixo guarda).
    event.respondWith(
      caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request, { ignoreVary: true })
          .then((cached) => cached || cache.match(key, { ignoreVary: true }))
          .then((cached) => {
            if (cached) return cached;
            return fetch(event.request).then((response) => {
              if (response && response.ok) {
                cache.put(event.request, response.clone());
              }
              return response;
            });
          });
      })
    );
  });

  // --- Pré-carga do app inteiro ------------------------------------------
  // Os mapas de depuração (.symbols), o motor skwasm (só usado em build
  // --wasm) e as licenças não são necessários para abrir o app.
  const DISPENSAVEIS = /(\\.symbols\$|^canvaskit\\/skwasm|^assets\\/NOTICES\$)/;

  async function sxPrecache() {
    const cache = await caches.open(CACHE_NAME);
    const faltando = [];
    for (const chave of Object.keys(RESOURCES)) {
      if (chave === '/' || DISPENSAVEIS.test(chave)) continue;
      if (await cache.match(chave, { ignoreVary: true })) continue;
      faltando.push(chave);
    }

    // Três downloads por vez; o que falhar fica para a próxima abertura
    let i = 0;
    async function proximo() {
      while (i < faltando.length) {
        const chave = faltando[i++];
        try {
          const response = await fetch(new Request(chave, { cache: 'reload' }));
          if (response && response.ok) await cache.put(chave, response);
        } catch (e) { /* sem rede agora */ }
      }
    }
    await Promise.all([proximo(), proximo(), proximo()]);
  }

  self.addEventListener('message', (event) => {
    if (event.data === 'sxdataPrecache') {
      event.waitUntil(sxPrecache());
    }
  });
})();''';
