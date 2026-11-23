import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Mermi yağmuru: gemini parmağınla sürükle (gemi parmağın biraz üstünde
/// durur), otomatik ateş edersin. Dev muhafızın desenli mermi yağmurunda
/// küçük çekirdeğini koru: yalnız ortadaki parlak nokta vurulabilir.
const double kHit = 7;

class Bullet {
  double x, y, vx, vy;
  final int col;
  Bullet(this.x, this.y, this.vx, this.vy, this.col);
}

class HellSim extends ArcadeSim {
  final ALevel level;
  double x = 500, y = 1350, bx = 500, by = 300;
  final List<Bullet> bullets = [];
  final List<Offset> myShots = [];
  int bossHp = 0, bossMax = 0, bosses = 0, phase = 0, grazes = 0, lastEvent = 0, pause = 0, patternT = 0;
  double spin = 0;
  late final int goalN = level.target(1, 0) == 0 ? 0 : 1 + level.d ~/ 4;

  HellSim(this.level) : super(level.meta) {
    _boss();
  }

  void _boss() {
    bossMax = 260 + level.d * 40 + bosses * 60;
    bossHp = bossMax;
    phase = 0;
  }

  double get density => 0.6 + level.d * 0.07;

  void _fire(double a, double sp, int col) => bullets.add(Bullet(bx + math.cos(a) * 60, by + math.sin(a) * 60, math.cos(a) * sp, math.sin(a) * sp, col));

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      x = moveToward(x, input.x, 26);
      y = moveToward(y, input.y - 140, 26);
    } else {
      x += input.dirX * 12;
      y += input.dirY * 12;
    }
    x = clampD(x, 20, 980);
    y = clampD(y, 500, 1560);
    if (pause > 0) {
      pause--;
      if (pause == 0) _boss();
      for (final b in bullets) {
        b.x += b.vx;
        b.y += b.vy;
      }
      bullets.removeWhere((b) => b.y > 1650 || b.y < -50 || b.x < -50 || b.x > 1050);
      return;
    }
    // patron hareketi
    bx = 500 + math.sin(ticks / 140) * 300;
    by = 300 + math.sin(ticks / 90) * 60;
    phase = bossHp > bossMax * 0.66 ? 0 : (bossHp > bossMax * 0.33 ? 1 : 2);
    patternT++;
    final every = math.max(4, (14 / density).round());
    if (patternT % every == 0) {
      switch ((phase + bosses) % 3) {
        case 0:
          // dönen spiral (2 kol)
          spin += 0.31;
          for (var k = 0; k < 2 + level.d ~/ 4; k++) {
            _fire(spin + k * math.pi * 2 / (2 + level.d ~/ 4), 4.5 + level.d * 0.15, 0);
          }
        case 1:
          // oyuncuya yelpaze
          final a = math.atan2(y - by, x - bx);
          final n = 3 + level.d ~/ 3;
          for (var k = 0; k < n; k++) {
            _fire(a + (k - (n - 1) / 2) * 0.16, 5.5 + level.d * 0.15, 1);
          }
        default:
          // halka (boşluklu)
          if (patternT % (every * 3) == 0) {
            final n = 16 + level.d * 2;
            final gap = rng.nextInt(n);
            for (var k = 0; k < n; k++) {
              if ((k - gap).abs() <= 1) continue;
              _fire(k / n * math.pi * 2 + spin, 3.8 + level.d * 0.12, 2);
            }
          }
      }
    }
    for (final b in bullets) {
      b.x += b.vx;
      b.y += b.vy;
    }
    // oyuncu atışları
    if (ticks % 5 == 0) myShots.add(Offset(x, y - 30));
    for (var i = 0; i < myShots.length; i++) {
      myShots[i] = myShots[i] - const Offset(0, 30);
    }
    myShots.removeWhere((s) {
      if (dist(s.dx, s.dy, bx, by) < 90) {
        bossHp--;
        score += 2;
        return true;
      }
      return s.dy < 0;
    });
    if (bossHp <= 0) {
      bosses++;
      score += 500;
      lastEvent = 2;
      bullets.clear();
      if (goalN > 0 && bosses >= goalN) {
        win();
        return;
      }
      pause = 90;
      return;
    }
    for (final b in bullets) {
      final d = dist(b.x, b.y, x, y);
      if (d < kHit + 9) {
        lastEvent = 3;
        hit();
        if (over) return;
        bullets.clear();
        break;
      }
      if (d < 40 && ticks % 3 == 0) {
        grazes++;
        score += 1;
      }
    }
    bullets.removeWhere((b) => b.y > 1650 || b.y < -50 || b.x < -50 || b.x > 1050);
  }

  @override
  double get progress => goalN == 0 ? 0 : (bosses + (1 - bossHp / math.max(1, bossMax))) / goalN;
  @override
  String get goalText => goalN == 0 ? '${seconds.toInt()}s' : '${bosses + 1}/$goalN · ${(bossHp * 100 / math.max(1, bossMax)).round()}%';
  @override
  Map<String, int> get stats => {'guardians_defeated': bosses, 'grazes': grazes};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: 9 aday hareketi mermilerin doğrusal izdüşümüyle puanlar; en
/// güvenliyi seçer, eşitlikte patronun altına yakın olanı.
ArcadeInput hellBot(ArcadeSim sim) {
  final s = sim as HellSim;
  var bestScore = -1e18, bx = s.x, by = s.y;
  final near = [for (final b in s.bullets) if ((b.y - s.y).abs() < 360 && (b.x - s.x).abs() < 360) b];
  for (final dx in [-26.0, -13.0, 0.0, 13.0, 26.0]) {
    for (final dy in [-26.0, 0.0, 26.0]) {
      final nx = clampD(s.x + dx, 20, 980), ny = clampD(s.y + dy, 500, 1560);
      var minD = 1e9;
      for (final b in near) {
        for (var k = 1; k <= 12; k++) {
          // aday konuma gidip orada kalırsa k tik sonra mermiye uzaklık
          final d = dist(b.x + b.vx * k, b.y + b.vy * k, nx, ny) + k * 1.5;
          if (d < minD) minD = d;
        }
      }
      var sc = math.min(minD, 120.0) * 10;
      sc -= (nx - s.bx).abs() * 0.4;
      sc -= (ny - 1300).abs() * 0.15;
      if (sc > bestScore) {
        bestScore = sc;
        bx = nx;
        by = ny;
      }
    }
  }
  return holdAt(bx, by + 140);
}

void paintHell(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as HellSim;
  paintSky(c, const Color(0xFF0B090A), const Color(0xFF161A1D));
  final star = Paint()..color = Colors.white24;
  for (var i = 0; i < 50; i++) {
    c.drawCircle(Offset((i * 193.0) % kWorldW, ((i * 331.0) + s.ticks * (1 + i % 3)) % kWorldH), 2, star);
  }
  if (s.pause == 0) {
    final o = Offset(s.bx, s.by);
    c.drawCircle(o, 110, Paint()..color = const Color(0xFF6A040F));
    for (var k = 0; k < 8; k++) {
      final a = k / 8 * math.pi * 2 + s.ticks * 0.02;
      paintBall(c, o + Offset(math.cos(a), math.sin(a)) * 110, 22, const Color(0xFF9D0208));
    }
    paintBall(c, o, 46, const Color(0xFFE85D04));
    c.drawCircle(o, 18, Paint()..color = const Color(0xFFFFBA08));
    // can çubuğu
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(100, 70, 800, 18), const Radius.circular(9)), Paint()..color = Colors.white12);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(100, 70, 800 * s.bossHp / math.max(1, s.bossMax), 18), const Radius.circular(9)), Paint()..color = const Color(0xFFE85D04));
  }
  for (final m in s.myShots) {
    c.drawRect(Rect.fromCenter(center: m, width: 6, height: 24), Paint()..color = p.piece(1));
  }
  const cols = [Color(0xFFFF4D6D), Color(0xFF4CC9F0), Color(0xFFFFD60A)];
  for (final b in s.bullets) {
    c.drawCircle(Offset(b.x, b.y), 12, Paint()..color = cols[b.col].withValues(alpha: 0.45));
    c.drawCircle(Offset(b.x, b.y), 6, Paint()..color = Colors.white);
  }
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  final ship = Path()
    ..moveTo(s.x, s.y - 34)
    ..lineTo(s.x + 26, s.y + 22)
    ..lineTo(s.x, s.y + 10)
    ..lineTo(s.x - 26, s.y + 22)
    ..close();
  c.drawPath(ship, Paint()..color = blink ? Colors.white38 : p.piece(0));
  c.drawCircle(Offset(s.x, s.y), kHit, Paint()..color = Colors.white);
}

Sfx? hellSound(ArcadeSim sim) => switch ((sim as HellSim).lastEvent) {
      2 => Sfx.win,
      3 => Sfx.lose,
      _ => null,
    };

KitRules hellRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('guardians_defeated', 'Yenilen muhafız', 'Guardians defeated', scale: 30),
        GameStat('grazes', 'Sıyırma', 'Grazes', scale: 500),
      ],
      missionTemplates: const [
        MissionTemplate('guardians_defeated', 'guardians_defeated', [2, 4, 8]),
        MissionTemplate('grazes', 'grazes', [50, 100, 200]),
      ],
      make: HellSim.new,
      botFn: hellBot,
    );
