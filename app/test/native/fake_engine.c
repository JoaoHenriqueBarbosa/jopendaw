// Motor nativo de mentira para os testes do engine_ffi.dart no computador: implementa a superfície
// jd_* com o contrato binário que o Dart assume (veja o topo de lib/audio/engine_ffi.dart), com
// respostas previsíveis, e umas funções fake_* para o teste conferir o que chegou. O teste compila
// este arquivo com o cc do sistema (sem compilador, os testes que dependem dele são pulados).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// ---------------------------------------------------------------- o que o teste confere

static double g_rate = 0;
static char *g_calls = NULL;
static size_t g_calls_len = 0;
static int g_calls_count = 0;
static intptr_t g_sample_id = -1;
static size_t g_sample_frames = 0;
static int g_sample_stereo = 0;
static double g_sample_sum = 0;
static int g_live = 0;  // handles vivos (decodificados + renders)
static float g_level = 0.25f;
static int g_input = 0;
static intptr_t g_input_device = -99;
static int g_capture = 0;
static int g_rec_blocks = 0;   // blocos na fila da captura
static int g_rec_sent = 0;     // blocos já lidos
static int g_notes_ready = 0;  // notas publicadas ao desligar a captura
static int g_state_error = 0;    // jd_state devolve este código (−5 = a thread de áudio caiu)
static int g_notes_pending = 0;  // jd_rec_notes devolve −1 (como o Rust enquanto o fim não chegou)
static int g_slow_us = 0;      // atraso por bloco do render (para dar tempo de cancelar)
static int g_offline_samples = 0;

size_t fake_last_calls(uint8_t *out, size_t max) {
  size_t n = g_calls_len < max ? g_calls_len : max;
  if (g_calls) memcpy(out, g_calls, n);
  return g_calls_len;
}
void fake_set_state_error(int code) { g_state_error = code; }
void fake_set_notes_pending(int on) { g_notes_pending = on; }
int fake_calls_count(void) { return g_calls_count; }
int fake_live(void) { return g_live; }
void fake_set_level(float level) { g_level = level; }
int fake_input_open(void) { return g_input; }
intptr_t fake_input_device(void) { return g_input_device; }
int fake_capture(void) { return g_capture; }
intptr_t fake_sample_id(void) { return g_sample_id; }
size_t fake_sample_frames(void) { return g_sample_frames; }
int fake_sample_stereo(void) { return g_sample_stereo; }
double fake_sample_sum(void) { return g_sample_sum; }
void fake_set_slow(int us) { g_slow_us = us; }
int fake_offline_samples(void) { return g_offline_samples; }

// ---------------------------------------------------------------- motor que toca

double jd_start(void) {
  if (g_rate == 0) g_rate = 48000;
  return g_rate;
}

void jd_stop(void) { g_rate = 0; }

int32_t jd_calls(const uint8_t *json, size_t len) {
  free(g_calls);
  g_calls = malloc(len + 1);
  memcpy(g_calls, json, len);
  g_calls[len] = 0;
  g_calls_len = len;
  g_calls_count++;
  return (len > 0 && json[0] == '[') ? 0 : -1;
}

void jd_sample_load(uint32_t id, const float *l, const float *r, size_t frames, double rate) {
  (void)rate;
  g_sample_id = id;
  g_sample_frames = frames;
  g_sample_stereo = r != NULL;
  g_sample_sum = 0;
  for (size_t i = 0; i < frames; i++) g_sample_sum += l[i] + (r ? r[i] : 0);
}

void jd_sample_drop(uint32_t id) { (void)id; }

// [batida, tocando, fxMeter, n, picos...] em f64, como o jd_state do Rust
int32_t jd_state(double *out, size_t max) {
  if (g_state_error) return g_state_error;
  if (max < 8) return 0;
  out[0] = 2.5;
  out[1] = 1;
  out[2] = -3;
  out[3] = 4;
  for (int i = 0; i < 4; i++) out[4 + i] = 0.5 * (double)(i + 1);
  return 8;
}

int32_t jd_spectrum(float *out, size_t n) {
  for (size_t i = 0; i < n; i++) out[i] = -60.0f;
  return (int32_t)n;
}

double jd_latency(void) { return 0.02; }

// latência do próprio motor (PDC, cadeia do master, limitador): 96 quadros = 2 ms a 48 kHz
double jd_engine_latency(void) { return 96.0; }

// loudness do master: momentâneo -20, curto prazo -21, integrado -22, true peak -1,5 e faixa 6,5
double jd_loudness(int32_t kind) {
  static const double v[5] = {-20.0, -21.0, -22.0, -1.5, 6.5};
  return kind >= 0 && kind < 5 ? v[kind] : -200.0;
}

// ---------------------------------------------------------------- decodificação
// "FAKE" + um byte por quadro; três canais (o Dart fica com dois), 44,1 kHz.

typedef struct {
  size_t frames;
  uint8_t *data;
} decoded;

uint64_t jd_decode(const uint8_t *bytes, size_t len) {
  if (len < 5 || memcmp(bytes, "FAKE", 4) != 0) return 0;
  decoded *d = malloc(sizeof(decoded));
  d->frames = len - 4;
  d->data = malloc(d->frames);
  memcpy(d->data, bytes + 4, d->frames);
  g_live++;
  return (uint64_t)(uintptr_t)d;
}

// como o Rust: handles u64 (em 32 bits ocupam um par de registradores), frames i64 e canais i32
void jd_decoded_info(uint64_t h, int64_t *frames, int32_t *channels, double *rate) {
  decoded *d = (decoded *)(uintptr_t)h;
  *frames = d->frames;
  *channels = 3;
  *rate = 44100;
}

void jd_decoded_copy(uint64_t h, int32_t channel, float *out) {
  decoded *d = (decoded *)(uintptr_t)h;
  for (size_t i = 0; i < d->frames; i++) out[i] = (float)d->data[i] / 100.0f * (float)(channel + 1);
}

void jd_decoded_free(uint64_t h) {
  decoded *d = (decoded *)(uintptr_t)h;
  free(d->data);
  free(d);
  g_live--;
}

// ---------------------------------------------------------------- entrada e captura

double jd_input_start(int32_t device) {
  if (device == 7) return -2;  // a entrada 7 existe mas não abre
  g_input = 1;
  g_input_device = device;
  return 0.012;
}

void jd_input_stop(void) { g_input = 0; }

int32_t jd_input_devices(uint8_t *out, size_t max) {
  const char *s = "[{\"id\":-1,\"name\":\"Padrão\"},{\"id\":3,\"name\":\"Microfone\"},{\"id\":7,\"name\":\"USB\"}]";
  size_t n = strlen(s);
  if (n <= max) memcpy(out, s, n);
  return (int32_t)n;
}

float jd_input_level(void) { return g_level; }

// ligar põe três blocos de 100 quadros na fila (batidas 4, 5 e 6); desligar publica uma nota
void jd_capture(int32_t on) {
  g_capture = on;
  if (on) {
    g_rec_blocks = 3;
    g_rec_sent = 0;
    g_notes_ready = 0;
  } else {
    g_notes_ready = 1;
  }
}

int32_t jd_recorded(float *l, float *r, size_t max, double *out_beat) {
  if (g_rec_sent >= g_rec_blocks) return 0;
  size_t n = 100 < max ? 100 : max;
  int k = g_rec_sent++;
  for (size_t i = 0; i < n; i++) {
    l[i] = (float)(k + 1);
    r[i] = -(float)(k + 1);
  }
  *out_beat = 4.0 + k;
  return (int32_t)n;
}

int32_t jd_rec_notes(float *out, size_t max) {
  if (g_notes_pending) return -1;  // o fim da captura ainda não chegou à thread de áudio
  if (!g_notes_ready || max < 5) return 0;
  g_notes_ready = 0;
  out[0] = 1;
  out[1] = 60;
  out[2] = 4.0f;
  out[3] = 5.5f;
  out[4] = 0.8f;
  return 5;
}

// ---------------------------------------------------------------- render fora de tempo real
// Cada captura devolve, no canal esquerdo, a faixa dela e, no direito, o índice absoluto do quadro
// (para o teste conferir que os blocos foram montados no lugar certo).

typedef struct {
  double rate;
  int tracks[64];
  int count;
  size_t pos;   // quadros processados antes do último bloco
  size_t last;  // tamanho do último bloco
} offline;

uint64_t jd_offline_new(double rate) {
  offline *o = calloc(1, sizeof(offline));
  o->rate = rate;
  g_live++;
  return (uint64_t)(uintptr_t)o;
}

// entende só capture_clear e capture_add, o que o teste precisa
void jd_offline_calls(uint64_t h, const uint8_t *json, size_t len) {
  offline *o = (offline *)(uintptr_t)h;
  char *s = malloc(len + 1);
  memcpy(s, json, len);
  s[len] = 0;
  if (strstr(s, "\"capture_clear\"")) o->count = 0;
  const char *p = s;
  while ((p = strstr(p, "[\"capture_add\",")) != NULL) {
    p += strlen("[\"capture_add\",");
    if (o->count < 64) o->tracks[o->count++] = atoi(p);
  }
  free(s);
}

void jd_offline_sample(uint64_t h, uint32_t id, const float *l, const float *r, size_t frames, double rate) {
  (void)h, (void)id, (void)l, (void)r, (void)frames, (void)rate;
  g_offline_samples++;
}

void jd_offline_process(uint64_t h, size_t frames) {
  offline *o = (offline *)(uintptr_t)h;
  o->pos += o->last;
  o->last = frames;
  if (g_slow_us > 0) usleep(g_slow_us);
}

void jd_offline_captured(uint64_t h, int32_t index, float *l, float *r, size_t n) {
  offline *o = (offline *)(uintptr_t)h;
  for (size_t i = 0; i < n; i++) {
    int valid = index >= 0 && index < o->count && i < o->last;
    l[i] = valid ? (float)o->tracks[index] : 0;
    r[i] = valid ? (float)(o->pos + i) : 0;
  }
}

void jd_offline_free(uint64_t h) {
  free((offline *)(uintptr_t)h);
  g_live--;
}
