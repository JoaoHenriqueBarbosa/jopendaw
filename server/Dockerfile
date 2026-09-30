# Build do backend Rust em duas etapas: compila com a toolchain completa, roda numa imagem enxuta
# só com as bibliotecas de sistema necessárias. O contexto é a raiz do repositório (workspace):
#   docker build -f server/Dockerfile .
FROM rust:1-bookworm AS build
WORKDIR /src

# As dependências entram numa camada própria, para o cache sobreviver a mudanças no código.
COPY Cargo.toml Cargo.lock ./
COPY server/Cargo.toml server/Cargo.toml
# O workspace lista o motor (e seus alvos wasm e Android): o cargo precisa achar os manifestos e os
# alvos deles para carregar o workspace, mesmo compilando só o servidor.
COPY engine engine
RUN mkdir server/src && echo 'fn main() {}' > server/src/main.rs \
    && cargo build --profile server -p jopendaw-server && rm -rf server/src

COPY server/src server/src
RUN touch server/src/main.rs && cargo build --profile server -p jopendaw-server

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/target/server/jopendaw-server /usr/local/bin/jopendaw-server
COPY server/schema.sql ./schema.sql
# sem root no container: um bug no servidor não vira root no host
RUN useradd --system --no-create-home --shell /usr/sbin/nologin jopendaw \
    && mkdir -p /data && chown jopendaw /data
USER jopendaw

# Produção: os áudios vão para o S3/MinIO (S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY, S3_SECRET_KEY) e
# /data só guarda os temporários de upload, então não precisa de volume persistente.
# Sem S3_ENDPOINT o servidor cai no disco: aí os áudios moram em /data e o volume é obrigatório
# (sem ele somem a cada deploy).
ENV PORT=8080 DATA_DIR=/data
VOLUME /data
EXPOSE 8080
CMD ["jopendaw-server"]
