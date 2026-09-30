# 13. Publicação na VPS (Dokploy)

> Para quem mantém o servidor. O que está descrito aqui foi feito pela sessão de código em 30/09/2026 e está registrado na seção "Deploy na VPS" do [`CLAUDE.md`](../../CLAUDE.md); esta página o reorganiza como passo a passo. **Nada daqui foi executado pela sessão de documentação** `(lido do CLAUDE.md; não reproduzido)`. Identificadores internos do Dokploy (ids das aplicações, da conta de serviço e do host interno), endereço da VPS e chaves ficam **só no `CLAUDE.md` e no Dokploy**; nenhum segredo entra em `docs/`.

## O que está no ar

O jopendaw vive no projeto `jopendaw` (ambiente `production`) do Dokploy, no servidor da VPS que hospeda os outros apps do dono:

| Aplicação | O que é | Como se fala com ela |
|---|---|---|
| `jopendaw-db` | Postgres 17 | Só pela rede interna do Dokploy (`DATABASE_URL`) |
| `jopendaw-api` | O servidor Rust (`server/`, [capítulo 11](11-servidor.md)), imagem `jopendaw-api` do registry próprio; volume `jopendaw-data` em `/data` | **Sem domínio**: só o nginx da web fala com ela |
| `jopendaw-web` | nginx estático com o app Flutter web (`app/build/web`), imagem `jopendaw-web`; faz proxy de `/api/` para a API (`JOPENDAW_API_HOST`) | Domínio `jopendaw.johnenrique.tech`, porta 80, com Let's Encrypt |

Fora do projeto: o **S3 é o MinIO já existente na VPS** (bucket `jopendaw`, com uma conta de serviço restrita a esse bucket) e os e-mails saem pelo **jmail de produção** (app `jopendaw` criado lá, com remetente próprio). É o mesmo desenho do `docker-compose.yml` de desenvolvimento ([03](03-build-teste-e-depuracao.md)), trocando o MinIO local e o jmail local pelos de produção.

## Variáveis de ambiente da API

Ficam **no Dokploy, nunca no git**. Só os nomes:

| Variável | Para quê |
|---|---|
| `DATABASE_URL` | Postgres (`jopendaw-db`) |
| `JWT_SECRET` | Próprio de produção (diferente do de desenvolvimento) |
| `APP_BASE_URL` | Base dos links dos e-mails (o domínio acima) |
| `JMAIL_URL`, `JMAIL_API_KEY` | O jmail de produção e a chave do app `jopendaw` nele |
| `S3_*` | Endpoint, bucket e credenciais da conta de serviço do MinIO; com elas o servidor guarda os áudios no S3 (`storage::Store`, [11](11-servidor.md)) |
| `DATA_DIR` | `/data` (o volume `jopendaw-data`) |

**Ausentes de propósito:**

- `GOOGLE_*` e `DISCORD_*`: sem elas os botões `Entrar com Google` e `Entrar com Discord` não aparecem. Falta registrar os redirects nos dois provedores.
- `REVIEW_EMAIL` e `REVIEW_CODE`: a conta de revisão da Play Store ([09](../manual/09-configuracoes-atalhos-android.md)) não existe em produção.

## Banco: schema e migrações

Não há migrações automáticas. O schema foi aplicado uma vez, enviando o `server/schema.sql` ao `psql` dentro do container do `jopendaw-db` (`docker exec -i … psql -U jopendaw -d jopendaw -v ON_ERROR_STOP=1 < server/schema.sql`, por `ssh` na VPS). **Mudança de schema** vira um script idempotente em `db/migrations/` e roda no mesmo comando, **antes** do deploy da API nova.

## Construir e publicar as imagens

As imagens são **amd64**; o Mac de desenvolvimento é **arm64**.

**API: construir na própria VPS.** O build do servidor sob emulação QEMU no Mac dá `SIGSEGV` no compilador C durante o crate `ring`. O procedimento registrado:

1. Na VPS, clonar o repositório raso (`git clone --depth 1`) num diretório temporário.
2. `docker build` com limites de memória e de CPU (`--memory`, `--memory-swap`, `--cpu-quota`, `--cpu-shares`) para não atrapalhar os outros apps, com `-f server/Dockerfile` e a tag `…/jopendaw-api:<versão>`. Demora cerca de 5 minutos: rodar em `nohup`, porque a sessão `ssh` estoura.
3. `docker push` para o registry, apagar o clone e `docker builder prune -f`.

**Web: construir no Mac.** É só estático:

1. `flutter build web --release` ([03](03-build-teste-e-depuracao.md)).
2. Copiar `app/build/web` para um contexto limpo, **sem os `*.wav` de teste** (o `.dockerignore` do app exclui `build/`, então o contexto não pode ser o diretório do app).
3. Imagem `FROM nginx:1.27-alpine` + o `nginx.conf.template` do app, `docker build --platform linux/amd64`, `docker push`.
4. No colima só cabe uma plataforma por tag: `docker rmi` a base arm64 antes de puxar a amd64.

Depois de publicar as imagens: pedir o deploy de cada aplicação pela API do Dokploy (`POST /api/application.deploy`; a chave fica na skill `vps-deploy`, não aqui) e conferir `applicationStatus` e os logs do container. O motor de áudio não entra no servidor: o `engine.wasm` e os `.so` vão **dentro do app** (`app/web/engine/engine.wasm` e `app/android/app/src/main/jniLibs/<abi>/libjopendaw_engine.so`), por isso recompilá-los e commitá-los junto ([01](01-motor.md)) é pré-requisito do `flutter build web`.

## Verificar sem DNS

Enquanto o registro DNS não existe, dá para testar o proxy pelo IP da VPS forçando a resolução do nome: um `curl -sk --resolve jopendaw.johnenrique.tech:443:<ip-da-vps> https://jopendaw.johnenrique.tech/api/me` devolvendo **401 com JSON** prova que o nginx chegou na API.

## Pendente

- **Registro A `jopendaw.johnenrique.tech` → IP da VPS**, feito à mão no painel do provedor de DNS (o navegador automatizado não está logado lá). Sem ele o domínio e o certificado do Let's Encrypt não valem. O app (`api/client.dart`), o manifest do Android e o `assetlinks.json` já apontam para esse domínio ([10](10-app-flutter.md), [09 do manual](../manual/09-configuracoes-atalhos-android.md)).
- Registrar os redirects no Google e no Discord e acrescentar `GOOGLE_*`/`DISCORD_*` à API para os botões de login aparecerem.
- Conta de revisão da Play Store (`REVIEW_*`) quando o app for publicado.

## Armadilhas

- **Nunca** colocar segredo no git nem em `docs/`: `JWT_SECRET`, `JMAIL_API_KEY`, `S3_*` e a chave do Dokploy vivem no Dokploy e na skill.
- Mudou o schema e subiu a API antes do script de `db/migrations/`: a API nova cai na primeira consulta à coluna que ainda não existe. A ordem é script, depois deploy.
- Enviar `app/build/web` inteiro como contexto do `docker build` leva os `*.wav` de teste para a imagem de produção.
- O servidor não confere o `version` do documento do projeto (só exige um objeto JSON): a recusa de documento de versão futura é do cliente ([12](12-sincronizacao.md)); um app velho conectado à produção continua podendo regravar por cima, como descrito lá.
