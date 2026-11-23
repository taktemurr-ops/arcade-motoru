import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kâğıt uçak: basılı tut = burnu kaldır (yükselir ama yavaşlar), bırak =
/// süzül / dal (hızlanır). Raflar arasındaki boşluklardan geç, yıldız topla.
/// Sıcak hava akımları (yukarı oklar) uçağı kaldırır.
const double kPlaneX = 260;

class Shelf {
  double x;
  final double gapY, gap;
  bool passed = false, star;
  Shelf(this.x, this.gapY, this.gap, this.star);
}

class PlaneSim extends ArcadeSim {
  final ALevel level;
  double y = 700, pitch = 0, speed = 10;
  final List<Shelf> shelves = [];
  final List<double> thermals = [];
  int passed = 0, starsGot = 0, lastEvent = 0;
  double lastGap = 800, travelled = 0;
  late final int goalN = level.target(10, 3);

  PlaneSim(this.level) : super(level.meta) {
    var x = 1200.0;
    while (shelves.length < 4) {
      _spawn(x);
      x += 700;
    }
  }

  void _spawn(double x) {
    final up = 180 + level.d * 8.0, down = 260 + level.d * 14.0;
    final gy = clampD(lastGap + (rng.chance(0.5) ? -rng.nextDouble() * up : rng.nextDouble() * down), 380, 1250);
    lastGap = gy;
    shelves.add(Shelf(x, gy, math.max(300, 430 - level.d * 12).toDouble(), rng.chance(0.5)));
    if (level.has('thermals') && rng.chance(0.4)) thermals.add(x + 300);
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    final up = input.down || input.dirY < 0;
    pitch = moveToward(pitch, up ? -0.55 : 0.35, 0.05);
    // Hız: dalış hızlandırır, tırmanış yavaşlatır.
    speed = clampD(speed + pitch * 0.12 - 0.005, 6, 16);
    var vy = vyFor(pitch, speed);
    for (final th in thermals) {
      if ((th - kPlaneX).abs() < 90) vy -= 5;
    }
    y += vy;
    final adv = 7 + speed * 0.4;
    travelled += adv;
    for (final s in shelves) {
      s.x -= adv;
    }
    for (var i = 0; i < thermals.length; i++) {
      thermals[i] -= adv;
    }
    thermals.removeWhere((t) => t < -200);
    if (y < 120) {
      y = 120;
      pitch = math.max(pitch, 0.0);
    }
    if (y > 1480) {
      lastEvent = 3;
      hit();
      if (over) return;
    }
    for (final s in shelves) {
      if (!s.passed && s.x + 60 < kPlaneX - 40) {
        s.passed = true;
        passed++;
        score += 10;
        lastEvent = 1;
        if (goalN > 0 && passed >= goalN) {
          win();
          return;
        }
      }
      if (s.star && (s.x + 30 - kPlaneX).abs() < 50 && (s.gapY - y).abs() < 70) {
        s.star = false;
        starsGot++;
        score += 25;
        lastEvent = 2;
      }
      if (kPlaneX + 50 > s.x && kPlaneX - 50 < s.x + 60 && (y - s.gapY).abs() > s.gap / 2 - 18) {
        lastEvent = 3;
        hit();
        if (over) return;
        break;
      }
    }
    shelves.removeWhere((s) => s.x < -200);
    while (shelves.length < 4) {
      _spawn(shelves.last.x + 700);
    }
  }

  static double vyFor(double pitch, double speed) => math.sin(pitch) * speed * 1.2 + 2.0 - (speed - 6) * 0.25;

  Shelf? get next {
    for (final s in shelves) {
      if (s.x + 60 > kPlaneX - 50) return s;
    }
    return null;
  }

  @override
  void onLifeLost() {
    final n = next;
    y = n == null ? 700 : n.gapY;
    pitch = 0;
    speed = 10;
  }

  @override
  double get progress => goalN == 0 ? 0 : passed / goalN;
  @override
  String get goalText => goalN == 0 ? '$passed' : '$passed/$goalN';
  @override
  Map<String, int> get stats => {'gaps_passed': passed, 'stars_collected': starsGot, 'meters_flown': travelled ~/ 10};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput planeBot(ArcadeSim sim) {
  final s = sim as PlaneSim;
  final n = s.next;
  final target = n == null ? 700.0 : n.gapY;
  // Öngörü: mevcut eğimle 12 tik sonrası.
  final vyNow = PlaneSim.vyFor(s.pitch, s.speed);
  final future = s.y + vyNow * 12;
  return future > target ? holdAt(500, 800) : ArcadeInput.idle;
}

void paintPlane(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as PlaneSim;
  paintSky(c, const Color(0xFFFFD6A5), const Color(0xFFCDB4DB));
  final cloud = Paint()..color = Colors.white60;
  for (var i = 0; i < 6; i++) {
    final x = (i * 270 - s.travelled * 0.3) % 1600 - 300;
    c.drawOval(Rect.fromLTWH(x, 160.0 + i * 230, 240, 70), cloud);
  }
  for (final th in s.thermals) {
    for (var k = 0; k < 5; k++) {
      final yy = 1450 - ((s.ticks * 6 + k * 300) % 1400).toDouble();
      paintText(c, '↑', Offset(th, yy), 60, Colors.white38);
    }
  }
  for (final sh in s.shelves) {
    final top = sh.gapY - sh.gap / 2, bot = sh.gapY + sh.gap / 2;
    paintBox(c, Rect.fromLTRB(sh.x, -20, sh.x + 60, top), const Color(0xFF8D6E63), radius: 10);
    paintBox(c, Rect.fromLTRB(sh.x, bot, sh.x + 60, kWorldH + 20), const Color(0xFF8D6E63), radius: 10);
    for (var yy = 40.0; yy < top - 40; yy += 120) {
      paintBox(c, Rect.fromLTWH(sh.x + 8, yy, 44, 70), p.piece(yy ~/ 120), radius: 4, shade: false);
    }
    if (sh.star) paintText(c, '★', Offset(sh.x + 30, sh.gapY), 64, const Color(0xFFFFC300));
  }
  c.drawRect(const Rect.fromLTWH(0, 1500, kWorldW, 100), Paint()..color = const Color(0xFF6D597A));
  c.save();
  c.translate(kPlaneX, s.y);
  c.rotate(s.pitch);
  final paper = s.shield > 0 && (s.ticks ~/ 5).isOdd ? Colors.white38 : Colors.white;
  final wing = Path()
    ..moveTo(70, 0)
    ..lineTo(-60, -34)
    ..lineTo(-36, 0)
    ..close();
  final keel = Path()
    ..moveTo(70, 0)
    ..lineTo(-36, 0)
    ..lineTo(-60, 26)
    ..close();
  c.drawPath(wing.shift(const Offset(6, 10)), Paint()..color = Colors.black12);
  c.drawPath(wing, Paint()..color = paper);
  c.drawPath(keel, Paint()..color = const Color(0xFFDEE2E6));
  c.drawLine(const Offset(70, 0), const Offset(-36, 0), Paint()
    ..color = p.piece(0)
    ..strokeWidth = 3);
  c.restore();
}

Sfx? planeSound(ArcadeSim sim) => switch ((sim as PlaneSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules planeRules(String id) => KitRules(
      id,
      optionalMechanics: const ['thermals'],
      gameStats: const [
        GameStat('gaps_passed', 'Geçilen boşluk', 'Gaps passed', scale: 200),
        GameStat('stars_collected', 'Yıldız', 'Stars', scale: 50),
        GameStat('meters_flown', 'Uçulan metre', 'Meters flown', scale: 5000),
      ],
      missionTemplates: const [
        MissionTemplate('gaps_passed', 'gaps_passed', [20, 40, 80]),
        MissionTemplate('stars_collected', 'stars_collected', [5, 10, 20]),
      ],
      make: PlaneSim.new,
      botFn: planeBot,
    );
