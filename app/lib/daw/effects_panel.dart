/// Rack de efeitos da faixa escolhida (`c.effectsTrack`; −1 = master). (esqueleto)
library;

import 'package:flutter/material.dart';

import 'controller.dart';

class EffectsPanel extends StatelessWidget {
  final DawController c;
  const EffectsPanel({super.key, required this.c});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Efeitos'));
}
