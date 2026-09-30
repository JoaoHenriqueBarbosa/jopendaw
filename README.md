# jopendaw

Um DAW completo que roda no navegador e no Android. O áudio é processado no próprio aparelho
(motor em Rust, compilado para WASM na web e nativo no Android); o servidor guarda a conta, a
sincronização dos projetos entre aparelhos e as tarefas pesadas.

- `engine/`: motor de áudio (Rust puro).
- `server/`: API (Rust, axum + SeaORM sobre Postgres).
- `app/`: interface (Flutter, o mesmo código para web e Android).

## Como subir

```bash
docker-compose up -d db                                          # Postgres
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < server/schema.sql   # schema, na primeira vez
cp server/.env.example server/.env                               # preencha JWT_SECRET e JMAIL_API_KEY
cd app && flutter build web --release                            # gera o app web
cd ../server && cargo run                                        # API e app em http://localhost:8080
```

Para tudo de uma vez em containers (API em :8080, app web em :8081): `docker-compose up --build`.
Para iterar no backend sem reiniciar, use `./hot.sh`. Testes: `cd app && flutter test` e
`cargo test -p jopendaw-engine`.

## Documentação

Tudo está em [`docs/`](docs/README.md): o manual de uso, os guias passo a passo e a documentação
técnica (arquitetura, motor, servidor, sincronização). As convenções de trabalho no repositório
estão no [`CLAUDE.md`](CLAUDE.md).
