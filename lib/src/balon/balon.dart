import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Balon patlatma: yükselen balonlara dokun. Dikenli gri toplara dokunma.
/// Kaçan balon can götürür. Altın balon ×5 puan.
class Balloon {
  double x, y;
  final double vy, sway, r;
  final int color;
  final int kind; // 0 normal, 1 diken, 2 altın, 3 çift (iki dokunuş)
  int hp;
  bool done = false;
  Balloon(this.x, this.y, this.vy, this.sway, this.r, this.color, this.kind) : hp = kind == 3 ? 2 : 1;
}

class BalloonSim extends ArcadeSim {
  final ALevel level;
  final List<Balloon> balloons = [];
  final List<Fx> fx = [];
  int popped = 0, golden = 0, spawnIn = 20, combo = 0, bestCombo = 0, lastEvent = 0;
  late final int goalN = level.target(20, 6);

  BalloonSim(this.level) : super(level.meta);

  double get speed => 2.4 + level.d * 0.28 + math.min(popped, 120) * 0.01;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (--spawnIn <= 0) {
      spawnIn = math.max(14, 46 - level.d * 3 - popped ~/ 10);
      final roll = rng.nextDouble();
      final kind = level.has('spikes') && roll < 0.16
          ? 1
          : (roll > 0.95 ? 2 : (level.has('tough') && roll > 0.82 ? 3 : 0));
      final r = kind == 1 ? 52.0 : 64.0 + rng.nextDouble() * 18;
      balloons.add(Balloon(90 + rng.nextDouble() * 820, kWorldH + r, speed * (0.85 + rng.nextDouble() * 0.3),
          level.has('wind') ? 1.6 : 0.6, r, rng.nextInt(6), kind));
    }
    for (final b in balloons) {
      b.y -= b.vy;
      b.x += math.sin((ticks + b.color * 40) / 30) * b.sway;
    }
    if (input.tap && input.hasPointer) {
      Balloon? hitB;
      for (final b in balloons.reversed) {
        if (!b.done && dist(input.x, input.y, b.x, b.y) < b.r + 14) {
          hitB = b;
          break;
        }
      }
      if (hitB != null) {
        if (hitB.kind == 1) {
          hitB.done = true;
          combo = 0;
          lastEvent = 3;
          fx.add(Fx(hitB.x, hitB.y, ticks, 4));
          hit();
        } else if (--hitB.hp <= 0) {
          hitB.done = true;
          popped++;
          combo++;
          bestCombo = math.max(bestCombo, combo);
          if (hitB.kind == 2) golden++;
          score += (hitB.kind == 2 ? 50 : 10) + math.min(combo, 20);
          fx.add(Fx(hitB.x, hitB.y, ticks, hitB.color));
          lastEvent = hitB.kind == 2 ? 2 : 1;
          if (goalN > 0 && popped >= goalN) win();
        } else {
          lastEvent = 1;
        }
      } else {
        combo = 0;
      }
    }
    for (final b in balloons) {
      if (!b.done && b.y < -b.r) {
        b.done = true;
        if (b.kind != 1) {
          combo = 0;
          hit();
          lastEvent = 3;
        }
      }
    }
    balloons.removeWhere((b) => b.done);
    pruneFx(fx, ticks);
  }

  @override
  double get progress => goalN == 0 ? 0 : popped / goalN;
  @override
  String get goalText => goalN == 0 ? '$popped' : '$popped/$goalN';
  @override
  Map<String, int> get stats => {'balloons_popped': popped, 'golden_balloons': golden, 'best_combo': bestCombo};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput balloonBot(ArcadeSim sim) {
  final s = sim as BalloonSim;
  if (s.ticks.isOdd) return ArcadeInput.idle;
  final list = [...s.balloons.where((b) => b.kind != 1 && b.y < kWorldH - 40)]..sort((a, b) => a.y.compareTo(b.y));
  for (final b in list) {
    // Dikenli balona değmeyen bir dokunma noktası seç.
    for (final (ox, oy) in const [(0.0, 0.0), (0.6, 0.0), (-0.6, 0.0), (0.0, 0.6), (0.0, -0.6)]) {
      final x = b.x + ox * b.r, y = b.y - b.vy + oy * b.r;
      final safe = s.balloons.every((o) => o.kind != 1 || dist(o.x, o.y - o.vy, x, y) > o.r + 20);
      if (safe) return tapAt(x, y);
    }
  }
  return ArcadeInput.idle;
}

void paintBalloons(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as BalloonSim;
  paintSky(c, const Color(0xFF8ECAE6), const Color(0xFFFFF1D6));
  final cloud = Paint()..color = Colors.white70;
  for (var i = 0; i < 4; i++) {
    final x = (i * 300 + s.ticks * 0.4) % 1300 - 150;
    c.drawOval(Rect.fromLTWH(x, 200.0 + i * 320, 260, 80), cloud);
  }
  // çimen
  c.drawRect(const Rect.fromLTWH(0, 1500, kWorldW, 100), Paint()..color = const Color(0xFF6A994E));
  for (final b in s.balloons) {
    final o = Offset(b.x, b.y);
    final string = Path()
      ..moveTo(b.x, b.y + b.r)
      ..quadraticBezierTo(b.x + 14 * math.sin(s.ticks / 12), b.y + b.r + 60, b.x, b.y + b.r + 120);
    c.drawPath(
        string,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.black38);
    if (b.kind == 1) {
      final spike = Paint()..color = const Color(0xFF495057);
      for (var i = 0; i < 12; i++) {
        final a = i / 12 * math.pi * 2;
        final path = Path()
          ..moveTo(b.x + math.cos(a - 0.2) * b.r, b.y + math.sin(a - 0.2) * b.r)
          ..lineTo(b.x + math.cos(a) * (b.r + 22), b.y + math.sin(a) * (b.r + 22))
          ..lineTo(b.x + math.cos(a + 0.2) * b.r, b.y + math.sin(a + 0.2) * b.r)
          ..close();
        c.drawPath(path, spike);
      }
      paintBall(c, o, b.r, const Color(0xFF6C757D));
      continue;
    }
    final col = b.kind == 2 ? const Color(0xFFFFC300) : p.piece(b.color);
    c.drawOval(Rect.fromCenter(center: o + const Offset(8, 10), width: b.r * 2, height: b.r * 2.3), Paint()..color = Colors.black12);
    c.drawOval(
        Rect.fromCenter(center: o, width: b.r * 2, height: b.r * 2.3),
        Paint()
          ..shader = RadialGradient(center: const Alignment(-0.4, -0.5), colors: [Color.lerp(col, Colors.white, 0.6)!, col, Color.lerp(col, Colors.black, 0.25)!], stops: const [0, 0.5, 1])
              .createShader(Rect.fromCenter(center: o, width: b.r * 2, height: b.r * 2.3)));
    final knot = Path()
      ..moveTo(b.x - 10, b.y + b.r * 1.15 + 12)
      ..lineTo(b.x, b.y + b.r * 1.15 - 2)
      ..lineTo(b.x + 10, b.y + b.r * 1.15 + 12)
      ..close();
    c.drawPath(knot, Paint()..color = col);
    if (b.kind == 3) paintText(c, '${b.hp}', o, 44, Colors.white);
    if (b.kind == 2) paintText(c, '★', o, 48, Colors.white);
  }
  paintFxList(c, s.fx, s.ticks, p);
}

Sfx? balloonSound(ArcadeSim sim) => switch ((sim as BalloonSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules balloonRules(String id) => KitRules(
      id,
      optionalMechanics: const ['spikes', 'tough', 'wind'],
      gameStats: const [
        GameStat('balloons_popped', 'Patlatılan balon', 'Balloons popped', scale: 300),
        GameStat('golden_balloons', 'Altın balon', 'Golden balloons', scale: 20),
        GameStat('best_combo', 'En iyi seri', 'Best combo', scale: 10),
      ],
      missionTemplates: const [
        MissionTemplate('balloons_popped', 'balloons_popped', [40, 80, 150]),
        MissionTemplate('golden_balloons', 'golden_balloons', [2, 4, 8]),
      ],
      make: BalloonSim.new,
      botFn: balloonBot,
    );
