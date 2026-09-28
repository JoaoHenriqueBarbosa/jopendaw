#!/bin/sh
# Compila o motor para WASM e põe no app web (app/web/engine/engine.wasm).
set -eu
cd "$(dirname "$0")/.."
cargo build -p jopendaw-engine-wasm --target wasm32-unknown-unknown --profile wasm
cp target/wasm32-unknown-unknown/wasm/jopendaw_engine_wasm.wasm app/web/engine/engine.wasm
ls -l app/web/engine/engine.wasm
