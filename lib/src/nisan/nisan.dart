import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Nişan antrenmanı: beliren hedefler küçülür; kaybolmadan merkezine yakın
/// dokun. Merkeze yakınlık puanı artırır. Kaçan hedef can götürür.
class Target {
  double x, y, vx, vy;
  final double r0;
  final int born, life;
  bool done = false;
  Target(this.x, this.y, this.vx, this.vy, this.r0, this.born, this.life);
}

class AimSim extends ArcadeSim {
  final ALevel level;
  final List<Target> targets = [];
  final List<Fx> fx = [];
  int hits = 0, bulls = 0, shots = 0, nextIn = 20, lastEvent = 0;
  double lastX = -1, lastY = -1;
  late final int goalN = level.target(15, 5);

  AimSim(this.level) : super(level.meta);

  double radius(Target t) => t.r0 * clampD(1 - (ticks - t.born) / t.life, 0, 1);

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (--nextIn <= 0) {
      final moving = level.has('moving') && rng.chance(0.5);
      final a = rng.nextDouble() * math.pi * 2;
      final sp = moving ? 2.0 + level.d * 0.3 : 0.0;
      targets.add(Target(150 + rng.nextDouble() * 700, 350 + rng.nextDouble() * 1000, math.cos(a) * sp, math.sin(a) * sp,
          math.max(60, 110 - level.d * 4).toDouble(), ticks, math.max(70, 150 - level.d * 7)));
      nextIn = math.max(18, 55 - level.d * 3 - hits ~/ 10);
    }
    for (final t in targets) {
      t.x += t.vx;
      t.y += t.vy;
      if (t.x < 80 || t.x > 920) t.vx = -t.vx;
      if (t.y < 300 || t.y > 1450) t.vy = -t.vy;
    }
    if (input.tap && input.hasPointer) {
      shots++;
      lastX = input.x;
      lastY = input.y;
      Target? best;
      var bd = 1e9;
      for (final t in targets) {
        final d = dist(input.x, input.y, t.x, t.y);
        if (!t.done && d < radius(t) + 8 && d < bd) {
          bd = d;
          best = t;
        }
      }
      if (best != null) {
        best.done = true;
        hits++;
        final ratio = bd / math.max(1, radius(best));
        final bull = ratio < 0.3;
        if (bull) bulls++;
        score += bull ? 50 : (ratio < 0.65 ? 25 : 10);
        fx.add(Fx(best.x, best.y, ticks, bull ? 1 : 0));
        lastEvent = bull ? 2 : 1;
        if (goalN > 0 && hits >= goalN) win();
      } else if (level.has('ammo')) {
        lastEvent = 3;
        hit();
      }
    }
    for (final t in targets) {
      if (!t.done && ticks - t.born >= t.life) {
        t.done = true;
        lastEvent = 3;
        hit();
      }
    }
    targets.removeWhere((t) => t.done);
    pruneFx(fx, ticks);
  }

  @override
  double get progress => goalN == 0 ? 0 : hits / goalN;
  @override
  String get goalText => goalN == 0 ? '$hits' : '$hits/$goalN';
  @override
  Map<String, int> get stats => {'targets_hit': hits, 'bullseyes': bulls};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput aimBot(ArcadeSim sim) {
  final s = sim as AimSim;
  if (s.ticks % 4 != 0) return ArcadeInput.idle;
  Target? best;
  for (final t in s.targets) {
    if (best == null || t.born + t.life < best.born + best.life) best = t;
  }
  if (best == null || s.ticks - best.born < 6) return ArcadeInput.idle;
  return tapAt(best.x + best.vx, best.y + best.vy);
}

void paintAim(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as AimSim;
  paintSky(c, const Color(0xFF242423), const Color(0xFF333533));
  paintGrid(c, const Rect.fromLTWH(0, 0, kWorldW, kWorldH), 100, Colors.white10);
  for (final tg in s.targets) {
    final r = s.radius(tg);
    final o = Offset(tg.x, tg.y);
    c.drawCircle(o + const Offset(6, 8), r, Paint()..color = Colors.black38);
    for (var i = 0; i < 4; i++) {
      c.drawCircle(o, r * (1 - i * 0.25), Paint()..color = i.isEven ? const Color(0xFFE63946) : Colors.white);
    }
    c.drawCircle(o, r * 0.12, Paint()..color = const Color(0xFF1D3557));
  }
  paintFxList(c, s.fx, s.ticks, p);
  if (s.lastX >= 0) {
    final cross = Paint()
      ..color = p.piece(1)
      ..strokeWidth = 4;
    c.drawLine(Offset(s.lastX - 30, s.lastY), Offset(s.lastX + 30, s.lastY), cross);
    c.drawLine(Offset(s.lastX, s.lastY - 30), Offset(s.lastX, s.lastY + 30), cross);
  }
  final acc = s.shots == 0 ? 100 : (s.hits * 100 ~/ s.shots);
  paintText(c, '◎ $acc%', const Offset(500, 1530), 50, Colors.white60);
}

Sfx? aimSound(ArcadeSim sim) => switch ((sim as AimSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules aimRules(String id) => KitRules(
      id,
      optionalMechanics: const ['moving', 'ammo'],
      gameStats: const [
        GameStat('targets_hit', 'Vurulan hedef', 'Targets hit', scale: 300),
        GameStat('bullseyes', 'Tam isabet', 'Bullseyes', scale: 100),
      ],
      missionTemplates: const [
        MissionTemplate('targets_hit', 'targets_hit', [30, 60, 120]),
        MissionTemplate('bullseyes', 'bullseyes', [10, 20, 40]),
      ],
      make: AimSim.new,
      botFn: aimBot,
    );
