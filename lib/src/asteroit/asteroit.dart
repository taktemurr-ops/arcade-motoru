import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Asteroit: gemi ortada döner, parmağın yönüne ateş eder, uzaktaki
/// parmağa doğru itki verir. Kayalar büyük → orta → küçük bölünür.
class Rock {
  double x, y, vx, vy;
  int size; // 3 büyük, 2 orta, 1 küçük
  final int shape;
  Rock(this.x, this.y, this.vx, this.vy, this.size, this.shape);
  double get r => size == 3 ? 80 : (size == 2 ? 48 : 26);
}

class Shot {
  double x, y;
  final double vx, vy;
  int life = 48;
  Shot(this.x, this.y, this.vx, this.vy);
}

class AsteroidSim extends ArcadeSim {
  final ALevel level;
  double x = kWorldW / 2, y = kWorldH / 2, vx = 0, vy = 0, angle = -math.pi / 2;
  final List<Rock> rocks = [];
  final List<Shot> shots = [];
  final List<Fx> fx = [];
  int wave = 0, broken = 0, fired = 0, cooldown = 0, lastEvent = 0, nextWaveAt = 0;
  late final int waves = level.target(2, 1) == 0 ? 0 : 2 + level.d ~/ 2;
  bool thrusting = false;

  AsteroidSim(this.level) : super(level.meta) {
    _wave();
  }

  void _wave() {
    wave++;
    final n = 2 + wave ~/ 2 + level.d ~/ 3;
    for (var i = 0; i < n; i++) {
      // Kenarlardan, gemiden uzakta doğar.
      final a = rng.nextDouble() * math.pi * 2;
      final rx = x + math.cos(a) * 560, ry = y + math.sin(a) * 560;
      final sp = 1.0 + level.d * 0.12 + rng.nextDouble() * 0.8;
      final da = rng.nextDouble() * math.pi * 2;
      rocks.add(Rock(_wrapX(rx), _wrapY(ry), math.cos(da) * sp, math.sin(da) * sp, 3, rng.nextInt(1000)));
    }
  }

  double _wrapX(double v) => (v + kWorldW) % kWorldW;
  double _wrapY(double v) => (v + kWorldH) % kWorldH;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    thrusting = false;
    if (input.hasPointer && input.down) {
      angle = math.atan2(input.y - y, input.x - x);
      final d = dist(x, y, input.x, input.y);
      if (d > 320) {
        vx += math.cos(angle) * 0.32;
        vy += math.sin(angle) * 0.32;
        thrusting = true;
      }
    } else if (input.dirX != 0 || input.dirY != 0) {
      angle = math.atan2(input.dirY.toDouble(), input.dirX.toDouble());
      vx += math.cos(angle) * 0.25;
      vy += math.sin(angle) * 0.25;
      thrusting = true;
    }
    vx *= 0.985;
    vy *= 0.985;
    final sp = math.sqrt(vx * vx + vy * vy);
    if (sp > 9) {
      vx *= 9 / sp;
      vy *= 9 / sp;
    }
    x = _wrapX(x + vx);
    y = _wrapY(y + vy);
    if (cooldown > 0) cooldown--;
    if ((input.down || input.tap) && cooldown == 0) {
      shots.add(Shot(x + math.cos(angle) * 40, y + math.sin(angle) * 40, math.cos(angle) * 22 + vx, math.sin(angle) * 22 + vy));
      cooldown = 9;
      fired++;
      lastEvent = 1;
    }
    for (final s in shots) {
      s.x = _wrapX(s.x + s.vx);
      s.y = _wrapY(s.y + s.vy);
      s.life--;
    }
    for (final r in rocks) {
      r.x = _wrapX(r.x + r.vx);
      r.y = _wrapY(r.y + r.vy);
    }
    final born = <Rock>[];
    for (final s in shots) {
      for (final r in rocks) {
        if (r.size > 0 && s.life > 0 && dist(s.x, s.y, r.x, r.y) < r.r) {
          s.life = 0;
          score += (4 - r.size) * 20;
          broken++;
          fx.add(Fx(r.x, r.y, ticks, r.size));
          lastEvent = 2;
          if (r.size > 1) {
            for (final sgn in [-1.0, 1.0]) {
              final a = math.atan2(r.vy, r.vx) + sgn * 0.7;
              final v = math.sqrt(r.vx * r.vx + r.vy * r.vy) * 1.3 + 0.4;
              born.add(Rock(r.x, r.y, math.cos(a) * v, math.sin(a) * v, r.size - 1, rng.nextInt(1000)));
            }
          }
          r.size = 0;
        }
      }
    }
    rocks.removeWhere((r) => r.size == 0);
    rocks.addAll(born);
    shots.removeWhere((s) => s.life <= 0);
    for (final r in rocks) {
      if (dist(x, y, r.x, r.y) < r.r + 22) {
        hit();
        if (over) return;
        break;
      }
    }
    pruneFx(fx, ticks);
    if (rocks.isEmpty) {
      if (nextWaveAt == 0) nextWaveAt = ticks + 60;
      if (ticks >= nextWaveAt) {
        nextWaveAt = 0;
        if (waves > 0 && wave >= waves) {
          win();
          return;
        }
        _wave();
      }
    }
  }

  @override
  void onLifeLost() {
    x = kWorldW / 2;
    y = kWorldH / 2;
    vx = vy = 0;
    // Merkezi boşalt.
    for (final r in rocks) {
      if (dist(r.x, r.y, x, y) < 300) {
        r.x = _wrapX(r.x + 500);
      }
    }
  }

  @override
  double get progress => waves == 0 ? 0 : (wave - 1 + (rocks.isEmpty ? 1 : 0)) / waves;
  @override
  String get goalText => waves == 0 ? '$broken' : '$wave/$waves';
  @override
  Map<String, int> get stats => {'rocks_broken': broken, 'shots_fired': fired, 'waves_cleared': rocks.isEmpty ? wave : wave - 1};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: en tehlikeli kayaya öndelikli nişan alır; yaklaşan kayadan kaçar.
ArcadeInput asteroidBot(ArcadeSim sim) {
  final s = sim as AsteroidSim;
  if (s.rocks.isEmpty) return ArcadeInput.idle;
  Rock? best;
  var bestT = 1e9;
  for (final r in s.rocks) {
    final d = dist(s.x, s.y, r.x, r.y) - r.r;
    if (d < bestT) {
      bestT = d;
      best = r;
    }
  }
  final r = best!;
  // Kaçış: çok yakınsa ters yöne it.
  if (bestT < 150 && s.shield == 0) {
    final a = math.atan2(s.y - r.y, s.x - r.x);
    return holdAt(s.x + math.cos(a) * 400, s.y + math.sin(a) * 400);
  }
  // Öndelikli nişan.
  final d = dist(s.x, s.y, r.x, r.y);
  final t = d / 22;
  final tx = r.x + r.vx * t, ty = r.y + r.vy * t;
  final a = math.atan2(ty - s.y, tx - s.x);
  // Yavaşla: itki gerekmez (parmak 320 içinde).
  return holdAt(s.x + math.cos(a) * 200, s.y + math.sin(a) * 200);
}

void paintAsteroids(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as AsteroidSim;
  paintSky(c, const Color(0xFF0B1026), const Color(0xFF1B1446));
  final star = Paint()..color = Colors.white54;
  for (var i = 0; i < 70; i++) {
    c.drawCircle(Offset((i * 137.0) % kWorldW, (i * 311.0) % kWorldH), (i % 3) + 1.0, star);
  }
  for (final r in s.rocks) {
    final path = Path();
    for (var i = 0; i < 11; i++) {
      final a = i / 11 * math.pi * 2 + s.ticks * 0.004 * (r.shape.isEven ? 1 : -1);
      final rr = r.r * (0.78 + ((r.shape * (i + 3)) % 7) / 25);
      final o = Offset(r.x + math.cos(a) * rr, r.y + math.sin(a) * rr);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    path.close();
    c.drawPath(path.shift(const Offset(6, 8)), Paint()..color = Colors.black38);
    c.drawPath(path, Paint()..shader = RadialGradient(colors: [const Color(0xFF9C8F84), const Color(0xFF5B5049)]).createShader(Rect.fromCircle(center: Offset(r.x - r.r * 0.3, r.y - r.r * 0.3), radius: r.r * 1.4)));
    c.drawCircle(Offset(r.x + r.r * 0.2, r.y - r.r * 0.1), r.r * 0.18, Paint()..color = Colors.black26);
  }
  for (final sh in s.shots) {
    c.drawCircle(Offset(sh.x, sh.y), 7, Paint()..color = p.piece(1));
    c.drawCircle(Offset(sh.x, sh.y), 3, Paint()..color = Colors.white);
  }
  paintFxList(c, s.fx, s.ticks, p);
  // gemi
  c.save();
  c.translate(s.x, s.y);
  c.rotate(s.angle);
  if (s.thrusting) {
    final f = Path()
      ..moveTo(-24, -10)
      ..lineTo(-48 - (s.ticks % 6) * 3.0, 0)
      ..lineTo(-24, 10)
      ..close();
    c.drawPath(f, Paint()..color = const Color(0xFFFFB703));
  }
  final ship = Path()
    ..moveTo(36, 0)
    ..lineTo(-24, -24)
    ..lineTo(-14, 0)
    ..lineTo(-24, 24)
    ..close();
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  c.drawPath(ship, Paint()..color = blink ? Colors.white38 : p.piece(0));
  c.drawPath(
      ship,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white70);
  c.restore();
}

Sfx? asteroidSound(ArcadeSim sim) => switch ((sim as AsteroidSim).lastEvent) {
      1 => null,
      2 => Sfx.clear,
      _ => null,
    };

KitRules asteroidRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('rocks_broken', 'Kırılan kaya', 'Rocks broken', scale: 200),
        GameStat('shots_fired', 'Atış', 'Shots fired', scale: 1000),
        GameStat('waves_cleared', 'Temizlenen dalga', 'Waves cleared', scale: 20),
      ],
      missionTemplates: const [
        MissionTemplate('rocks_broken', 'rocks_broken', [30, 60, 120]),
        MissionTemplate('waves_cleared', 'waves_cleared', [2, 4, 6]),
      ],
      make: AsteroidSim.new,
      botFn: asteroidBot,
    );
