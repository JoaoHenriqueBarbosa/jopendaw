/// Editor de notas do clipe MIDI aberto (`c.editing`). (esqueleto: implementação em andamento)
library;

import 'package:flutter/material.dart';

import 'controller.dart';

class PianoRoll extends StatelessWidget {
  final DawController c;
  const PianoRoll({super.key, required this.c});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Piano roll'));
}
