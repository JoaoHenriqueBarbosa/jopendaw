#!/bin/sh
# Compila o motor para o Android (libjopendaw_engine.so nos três ABIs) e põe em
# app/android/app/src/main/jniLibs, commitado como o engine.wasm: o `flutter build apk` não precisa
# de Rust. Precisa do cargo-ndk (`cargo install cargo-ndk`), dos alvos do rustup
# (aarch64-linux-android, armv7-linux-androideabi, x86_64-linux-android) e do NDK, pelo
# ANDROID_NDK_HOME ou no lugar padrão do Android Studio no Mac.
#
# Plataforma 24: a mínima do app (a biblioteca abre no Android 7; o AAudio, da API 26, é carregado
# em tempo de execução). O NDK r28 alinha os segmentos em 16 KB, o que o Android 15 exige.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  ANDROID_NDK_HOME="$sdk/ndk/28.2.13676358"
  [ -d "$ANDROID_NDK_HOME" ] || ANDROID_NDK_HOME="$(ls -d "$sdk"/ndk/* 2>/dev/null | sort -V | tail -1)"
fi
export ANDROID_NDK_HOME
echo "NDK: $ANDROID_NDK_HOME"

out=app/android/app/src/main/jniLibs
cargo ndk -P 24 -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$out" build -p jopendaw-engine-android --profile android

# confere que cada .so exporta a superfície inteira (uma função esquecida só apareceria no Dart)
nm="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-nm | head -1)"
want="jd_start jd_stop jd_calls jd_sample_load jd_sample_drop jd_state jd_spectrum jd_decode jd_decoded_info
jd_decoded_copy jd_decoded_free jd_input_start jd_input_stop jd_input_devices jd_capture jd_recorded jd_input_level
jd_rec_notes jd_offline_new jd_offline_calls jd_offline_sample jd_offline_process jd_offline_captured jd_offline_free
jd_latency jd_loudness jd_stretch jd_detect_bpm JNI_OnLoad"
for abi in arm64-v8a armeabi-v7a x86_64; do
  so="$out/$abi/libjopendaw_engine.so"
  syms="$("$nm" -D --defined-only "$so")"
  for f in $want; do
    echo "$syms" | grep -qw "$f" || { echo "faltou $f em $so" >&2; exit 1; }
  done
  # nada de libaaudio.so ligada: ela não existe no Android 7
  if "$(dirname "$nm")/llvm-readelf" -d "$so" | grep -q 'libaaudio'; then
    echo "$so depende da libaaudio.so" >&2
    exit 1
  fi
done
ls -l "$out"/*/libjopendaw_engine.so
