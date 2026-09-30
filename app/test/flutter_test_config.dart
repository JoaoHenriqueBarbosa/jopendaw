import 'dart:async';

import 'package:jopendaw_app/daw/snapshots.dart';

/// Configuração de todos os testes desta pasta: o relógio de parede das versões automáticas (um Timer de
/// minutos) fica desligado, senão qualquer teste de tela que edita o projeto termina com um Timer pendente.
/// Os testes do relógio (em `history_versions_test.dart`) ligam de novo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  versionClockTimers = false;
  await testMain();
}
