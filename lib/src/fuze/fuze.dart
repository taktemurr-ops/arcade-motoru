import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Füze savunması: gökten düşen göktaşları şehirlere iniyor. Dokunduğun
/// yere önleyici gönderilir ve orada genişleyen bir patlama olur. Şehre
/// düşen göktaşı can götürür. Dalgaları atlat.
const double kGround = 1440, kBaseX = 500, kBaseY = 1400, kInterceptorSpeed = 24, kBlastR = 110;

class Rock {
  double x, y;
  final double vx, vy, sx, sy;
  bool dead = false;
  final bool splits;
  Rock(this.x, this.y, this.vx, this.vy, this.splits)
      : sx = x,
        sy = y;
}

class Interceptor {
  double x, y;
  final double tx, ty, vx, vy;
  Interceptor(this.x, this.y, this.tx, this.ty)
      : vx = (tx - x) / dist(x, y, tx, ty) * kInterceptorSpeed,
        vy = (ty - y) / dist(x, y, tx, ty) * kInterceptorSpeed;
}

class Blast {
  final double x, y;
  final int born;
  Blast(this.x, this.y, this.born);
  double radiusAt(int now) {
    final a = now - born;
    if (a < 20) return kBlastR * a / 20;
    if (a < 40) return kBlastR;
    return kBlastR * (1 - (a - 40) / 15);
  }
}

class MissileSim extends ArcadeSim {
  final ALevel level;
  final List<Rock> rocks = [];
  final List<Interceptor> ints = [];
  final List<Blast> blasts = [];
  final List<double> cities = [130, 280, 720, 870];
  int wave = 0, toSpawn = 0, spawnIn = 0, destroyed = 0, launched = 0, lastEvent = 0, pause = 60;
  late final int waves = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 2;

  MissileSim(this.level) : super(level.meta, lives: 4);

  void _startWave() {
    wave++;
    toSpawn = 6 + wave * 2 + level.d;
    spawnIn = 0;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (pause > 0) {
      pause--;
      if (pause == 0) _startWave();
      return;
    }
    if (toSpawn > 0 && --spawnIn <= 0) {
      toSpawn--;
      final sx = 50 + rng.nextDouble() * 900;
      final tx = rng.pick(cities) + (rng.nextDouble() - 0.5) * 60;
      final sp = 1.6 + level.d * 0.22 + wave * 0.08;
      final d = dist(sx, 0, tx, kGround);
      rocks.add(Rock(sx, -20, (tx - sx) / d * sp, kGround / d * sp, level.has('split') && rng.chance(0.2)));
      spawnIn = math.max(16, 60 - level.d * 4 - wave * 2);
    }
    if (input.tap && input.hasPointer && input.y < kBaseY - 80) {
      ints.add(Interceptor(kBaseX, kBaseY, input.x, input.y));
      launched++;
      lastEvent = 1;
    }
    for (final i in [...ints]) {
      i.x += i.vx;
      i.y += i.vy;
      if (dist(i.x, i.y, i.tx, i.ty) <= kInterceptorSpeed) {
        ints.remove(i);
        blasts.add(Blast(i.tx, i.ty, ticks));
        lastEvent = 2;
      }
    }
    final born = <Rock>[];
    for (final r in rocks) {
      r.x += r.vx;
      r.y += r.vy;
      for (final b in blasts) {
        if (!r.dead && dist(r.x, r.y, b.x, b.y) < b.radiusAt(ticks) + 8) {
          r.dead = true;
          destroyed++;
          score += 25;
          lastEvent = 2;
          // Zincirleme patlama
          born.add(Rock(r.x, r.y, 0, 0, false)..dead = true);
        }
      }
      if (!r.dead && r.splits && r.y > 500 && r.y < 520) {
        r.dead = true;
        for (final dx in [-120.0, 120.0]) {
          final tx = clampD(r.x + dx * 4, 60, 940);
          final d = dist(r.x, r.y, tx, kGround);
          final sp = math.sqrt(r.vx * r.vx + r.vy * r.vy);
          born.add(Rock(r.x, r.y, (tx - r.x) / d * sp, (kGround - r.y) / d * sp, false));
        }
      }
      if (!r.dead && r.y >= kGround) {
        r.dead = true;
        lastEvent = 3;
        hit();
        if (over) return;
      }
    }
    for (final b in born) {
      if (b.dead) {
        blasts.add(Blast(b.x, b.y, ticks - 10));
      } else {
        rocks.add(b);
      }
    }
    rocks.removeWhere((r) => r.dead);
    blasts.removeWhere((b) => ticks - b.born > 55);
    if (toSpawn == 0 && rocks.isEmpty && wave > 0 && pause == 0) {
      score += 100;
      if (waves > 0 && wave >= waves) {
        win();
        return;
      }
      pause = 90;
    }
  }

  @override
  double get progress => waves == 0 ? 0 : (wave - (rocks.isEmpty && toSpawn == 0 ? 0 : 1)) / waves;
  @override
  String get goalText => waves == 0 ? '$wave' : '$wave/$waves';
  @override
  Map<String, int> get stats => {'meteors_destroyed': destroyed, 'waves_survived': math.max(0, wave - 1)};
  @override
  int get stars => lifeStars(this, 4);
}

/// Bot: en önce düşecek göktaşını, önleyicinin varış süresine göre
/// öngörülen noktada karşılar. Zaten hedeflenmiş taşları atlar.
ArcadeInput missileBot(ArcadeSim sim) {
  final s = sim as MissileSim;
  if (s.ticks % 6 != 0) return ArcadeInput.idle;
  Rock? best;
  var bestT = 1e9;
  for (final r in s.rocks) {
    // Bu taşı kapsayacak bir patlama/önleyici var mı?
    var covered = false;
    for (final i in s.ints) {
      final steps = dist(i.x, i.y, i.tx, i.ty) / kInterceptorSpeed;
      if (dist(r.x + r.vx * (steps + 20), r.y + r.vy * (steps + 20), i.tx, i.ty) < kBlastR * 0.8) covered = true;
    }
    for (final b in s.blasts) {
      if (s.ticks - b.born < 30 && dist(r.x + r.vx * 10, r.y + r.vy * 10, b.x, b.y) < kBlastR * 0.8) covered = true;
    }
    if (covered || r.y < 80) continue;
    final t = (kGround - r.y) / math.max(0.1, r.vy);
    if (t < bestT) {
      bestT = t;
      best = r;
    }
  }
  if (best == null) return ArcadeInput.idle;
  // Kesişim: n tik sonra taşın konumu, önleyicinin uçuş süresi + patlama genişleme (~12 tik).
  var n = 20.0;
  for (var it = 0; it < 6; it++) {
    final px = best.x + best.vx * n, py = best.y + best.vy * n;
    n = dist(kBaseX, kBaseY, px, py) / kInterceptorSpeed + 12;
  }
  final px = best.x + best.vx * n, py = best.y + best.vy * n;
  if (py > kBaseY - 90) {
    return tapAt(best.x + best.vx * 6, math.min(best.y + best.vy * 6, kBaseY - 100));
  }
  return tapAt(px, py);
}

void paintMissiles(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as MissileSim;
  paintSky(c, const Color(0xFF10002B), const Color(0xFF3C096C));
  c.drawRect(const Rect.fromLTWH(0, kGround, kWorldW, kWorldH - kGround), Paint()..color = const Color(0xFF5A189A));
  // şehirler
  for (final cx in s.cities) {
    for (var k = 0; k < 4; k++) {
      final h = 40.0 + (k * 23 + cx.toInt()) % 50;
      paintBox(c, Rect.fromLTWH(cx - 60 + k * 30, kGround - h, 26, h), p.piece(k), radius: 3, shade: false);
    }
  }
  // üs
  c.drawPath(Path()..moveTo(kBaseX - 80, kGround)..lineTo(kBaseX, kBaseY - 30)..lineTo(kBaseX + 80, kGround)..close(), Paint()..color = const Color(0xFFADB5BD));
  for (final r in s.rocks) {
    c.drawLine(Offset(r.sx, r.sy), Offset(r.x, r.y), Paint()
      ..shader = LinearGradient(colors: [Colors.transparent, const Color(0xFFFF6D00)]).createShader(Rect.fromPoints(Offset(r.sx, r.sy), Offset(r.x, r.y)))
      ..strokeWidth = 5);
    paintBall(c, Offset(r.x, r.y), 14, const Color(0xFFFF9E00));
  }
  for (final i in s.ints) {
    c.drawLine(const Offset(kBaseX, kBaseY), Offset(i.x, i.y), Paint()
      ..color = const Color(0xFF4CC9F0)
      ..strokeWidth = 3);
    c.drawCircle(Offset(i.tx, i.ty), 10, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white54);
  }
  for (final b in s.blasts) {
    final r = b.radiusAt(s.ticks);
    if (r <= 0) continue;
    c.drawCircle(Offset(b.x, b.y), r, Paint()
      ..shader = RadialGradient(colors: [Colors.white, const Color(0xFFFFD60A), const Color(0x00FF6D00)], stops: const [0, 0.5, 1]).createShader(Rect.fromCircle(center: Offset(b.x, b.y), radius: r)));
  }
}

Sfx? missileSound(ArcadeSim sim) => switch ((sim as MissileSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.clear,
      3 => Sfx.error,
      _ => null,
    };

KitRules missileRules(String id) => KitRules(
      id,
      optionalMechanics: const ['split'],
      gameStats: const [
        GameStat('meteors_destroyed', 'Durdurulan göktaşı', 'Meteors stopped', scale: 300),
        GameStat('waves_survived', 'Atlatılan dalga', 'Waves survived', scale: 30),
      ],
      missionTemplates: const [
        MissionTemplate('meteors_destroyed', 'meteors_destroyed', [30, 60, 120]),
        MissionTemplate('waves_survived', 'waves_survived', [3, 6, 12]),
      ],
      make: MissileSim.new,
      botFn: missileBot,
    );
