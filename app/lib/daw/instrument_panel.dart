/// Painel do instrumento da faixa selecionada. (esqueleto: implementação em andamento)
library;

import 'package:flutter/material.dart';

import 'controller.dart';

class InstrumentPanel extends StatelessWidget {
  final DawController c;
  const InstrumentPanel({super.key, required this.c});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Instrumento'));
}
