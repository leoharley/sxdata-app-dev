# SXData — app de coleta

App Flutter do SXData (Android e versão web/PWA). API padrão:
`https://painel.sxdata.com.br/api`; outro ambiente com
`--dart-define=API_BASE_URL=https://<servidor>/api`.

## Versão web (`https://painel.sxdata.com.br/app/`)

```bash
# No Git Bash do Windows, MSYS_NO_PATHCONV=1 impede que /app/ vire caminho do Windows
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/ --no-web-resources-cdn \
  --dart-define=API_BASE_URL=https://painel.sxdata.com.br/api
dart run tool/patch_service_worker.dart build/web/flutter_service_worker.js
```

As duas etapas são obrigatórias para o app abrir **sem internet**:

- `--no-web-resources-cdn`: o motor gráfico (CanvasKit) sai do próprio site.
  Sem isso ele vem do CDN do Google e, offline, a tela fica em branco. O patch
  recusa um build que não tenha essa opção.
- `tool/patch_service_worker.dart`: corrige o service worker para o
  subdiretório `/app/` e faz o app inteiro ficar guardado no aparelho. A
  explicação está no próprio arquivo.

Publicação: substituir a pasta `app/` do repositório do painel inteira pelo
conteúdo de `build/web` (sem o `.last_build_id`), commitar e fazer o deploy.

## APK

```bash
JAVA_HOME="C:\Program Files\Java\jdk-17" flutter build apk --release
```

Assinatura da Play Store: `android/key.properties` (modelo em
`android/key.properties.example`). Sem ele, o build sai com a chave de debug.
