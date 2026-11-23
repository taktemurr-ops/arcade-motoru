import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kayak slalom: kayakçı yokuştan iner; parmağını sağa/sola tutarak yön ver.
/// İki bayrak arasından geç; ağaçlara ve kayalara çarpma. Kaçırılan kapı can
/// götürür.
const double kSkierY = 420;

class Gate {
  final double x, y, w;
  bool done = false;
  Gate(this.x, this.y, this.w);
}

class Tree {
  final double x, y, r;
  final bool rock;
  Tree(this.x, this.y, this.r, this.rock);
}

class SkiSim extends ArcadeSim {
  final ALevel level;
  double x = 500, vx = 0, travelled = 0, speed;
  final List<Gate> gates = [];
  final List<Tree> trees = [];
  int passed = 0, lastEvent = 0, perfect = 0;
  double nextY = 900, lastGateX = 500;
  late final int goalN = level.target(12, 3);

  SkiSim(this.level)
      : speed = 8 + level.d * 0.45,
        super(level.meta) {
    while (nextY < 2600) {
      _spawnGate();
    }
  }

  void _spawnGate() {
    final maxShift = 200 + level.d * 12.0;
    final gx = clampD(lastGateX + (rng.nextDouble() * 2 - 1) * maxShift, 180, 820);
    final w = math.max(170, 280 - level.d * 11).toDouble();
    gates.add(Gate(gx, nextY, w));
    // Ağaçlar: kapı koridorunun dışında.
    final n = 2 + level.d ~/ 3;
    for (var i = 0; i < n; i++) {
      final ty = nextY + 120 + rng.nextDouble() * 260;
      var tx = rng.nextDouble() * kWorldW;
      final corridorL = math.min(gx, lastGateX) - w / 2 - 90, corridorR = math.max(gx, lastGateX) + w / 2 + 90;
      if (tx > corridorL && tx < corridorR) tx = tx < (corridorL + corridorR) / 2 ? corridorL - 40 : corridorR + 40;
      if (tx > 40 && tx < kWorldW - 40) trees.add(Tree(tx, ty - 400, 46 + rng.nextDouble() * 20, rng.chance(0.25)));
    }
    lastGateX = gx;
    nextY += 400 + rng.nextDouble() * 120;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var steer = 0.0;
    if (input.down && input.hasPointer) {
      steer = clampD((input.x - x) / 160, -1, 1);
    } else if (input.dirX != 0) {
      steer = input.dirX.toDouble();
    }
    vx = vx * 0.86 + steer * 2.6;
    x = clampD(x + vx, 40, kWorldW - 40);
    final turn = vx.abs() / 20;
    final sp = speed * (1 - turn * 0.25);
    travelled += sp;
    speed = math.min(speed + 0.001, 16.0);
    for (final g in gates) {
      if (g.done) continue;
      final gy = g.y - travelled;
      if (gy <= kSkierY) {
        g.done = true;
        if ((x - g.x).abs() < g.w / 2 - 10) {
          passed++;
          final pf = (x - g.x).abs() < g.w * 0.15;
          if (pf) perfect++;
          score += pf ? 30 : 15;
          lastEvent = 1;
          if (goalN > 0 && passed >= goalN) {
            win();
            return;
          }
        } else {
          lastEvent = 3;
          hit();
          if (over) return;
        }
      }
    }
    for (final tr in trees) {
      final ty = tr.y - travelled;
      if ((ty - kSkierY).abs() < tr.r * 0.6 + 16 && (tr.x - x).abs() < tr.r * 0.6 + 22) {
        lastEvent = 3;
        hit();
        if (over) return;
        break;
      }
    }
    gates.removeWhere((g) => g.y - travelled < -200);
    trees.removeWhere((t) => t.y - travelled < -200);
    while (nextY - travelled < 2600) {
      _spawnGate();
    }
  }

  @override
  void onLifeLost() {
    final next = gates.where((g) => !g.done).toList();
    if (next.isNotEmpty) x = next.first.x;
    trees.removeWhere((t) => (t.y - travelled - kSkierY).abs() < 200);
  }

  @override
  double get progress => goalN == 0 ? 0 : passed / goalN;
  @override
  String get goalText => goalN == 0 ? '$passed' : '$passed/$goalN';
  @override
  Map<String, int> get stats => {'gates_passed': passed, 'perfect_gates': perfect, 'meters_skied': travelled ~/ 10};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput skiBot(ArcadeSim sim) {
  final s = sim as SkiSim;
  Gate? g;
  for (final q in s.gates) {
    if (!q.done) {
      g = q;
      break;
    }
  }
  if (g == null) return ArcadeInput.idle;
  var tx = g.x;
  // Önündeki ağaçtan kaç.
  for (final tr in s.trees) {
    final dy = tr.y - s.travelled - kSkierY;
    if (dy > -40 && dy < 260 && (tr.x - s.x).abs() < tr.r + 60) {
      tx = tr.x > s.x ? tr.x - tr.r - 120 : tr.x + tr.r + 120;
    }
  }
  return holdAt(tx, 1200);
}

void paintSki(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SkiSim;
  paintSky(c, const Color(0xFFF8F9FA), const Color(0xFFDDE7F0));
  final groove = Paint()..color = const Color(0x14000000);
  for (var i = 0; i < 30; i++) {
    final y = (i * 97 - s.travelled) % 1700 - 50;
    c.drawLine(Offset((i * 151) % kWorldW, y), Offset((i * 151) % kWorldW + 60, y + 4), groove..strokeWidth = 4);
  }
  for (final g in s.gates) {
    final y = g.y - s.travelled;
    if (y < -100 || y > kWorldH + 100) continue;
    final col = g.done ? Colors.black26 : (s.gates.indexOf(g).isEven ? const Color(0xFFE63946) : const Color(0xFF1D4ED8));
    for (final sx in [-1.0, 1.0]) {
      final fx = g.x + sx * g.w / 2;
      c.drawLine(Offset(fx, y), Offset(fx, y - 110), Paint()
        ..color = Colors.black54
        ..strokeWidth = 6);
      c.drawPath(Path()..moveTo(fx, y - 110)..lineTo(fx + sx * -50, y - 90)..lineTo(fx, y - 66)..close(), Paint()..color = col);
    }
  }
  for (final tr in s.trees) {
    final y = tr.y - s.travelled;
    if (y < -150 || y > kWorldH + 150) continue;
    paintShadow(c, Offset(tr.x + 10, y + 10), tr.r * 2);
    if (tr.rock) {
      paintBall(c, Offset(tr.x, y), tr.r * 0.8, const Color(0xFF8D99AE));
    } else {
      c.drawRect(Rect.fromCenter(center: Offset(tr.x, y), width: 16, height: 30), Paint()..color = const Color(0xFF6F4518));
      for (var k = 0; k < 3; k++) {
        final w = tr.r * (2 - k * 0.45);
        c.drawPath(Path()..moveTo(tr.x - w / 2, y - 10 - k * 34)..lineTo(tr.x, y - 70 - k * 40)..lineTo(tr.x + w / 2, y - 10 - k * 34)..close(), Paint()..color = const Color(0xFF2D6A4F));
      }
    }
  }
  // iz
  c.save();
  c.translate(s.x, kSkierY);
  c.rotate(-s.vx / 30);
  final body = s.shield > 0 && (s.ticks ~/ 5).isOdd ? Colors.white54 : p.piece(0);
  for (final sx in [-14.0, 14.0]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, 10), width: 12, height: 110), const Radius.circular(6)), Paint()..color = const Color(0xFF212529));
  }
  paintBox(c, Rect.fromCenter(center: const Offset(0, -10), width: 56, height: 60), body, radius: 20, shade: false);
  c.drawCircle(const Offset(0, -52), 22, Paint()..color = const Color(0xFFFFD6A5));
  c.drawArc(Rect.fromCircle(center: const Offset(0, -56), radius: 24), math.pi, math.pi, true, Paint()..color = p.piece(1));
  c.restore();
}

Sfx? skiSound(ArcadeSim sim) => switch ((sim as SkiSim).lastEvent) {
      1 => Sfx.place,
      3 => Sfx.error,
      _ => null,
    };

KitRules skiRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('gates_passed', 'Geçilen kapı', 'Gates passed', scale: 300),
        GameStat('perfect_gates', 'Kusursuz kapı', 'Perfect gates', scale: 100),
        GameStat('meters_skied', 'Kayılan metre', 'Meters skied', scale: 5000),
      ],
      missionTemplates: const [
        MissionTemplate('gates_passed', 'gates_passed', [20, 40, 80]),
        MissionTemplate('perfect_gates', 'perfect_gates', [5, 10, 20]),
      ],
      make: SkiSim.new,
      botFn: skiBot,
    );
