import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Dinozor koşusu: çölde koşan küçük dinozor. Dokun = zıpla, aşağı kaydır
/// (ya da ekranın alt üçte birine basılı tut) = eğil. Kaktüslerin üstünden
/// atla, alçak uçan kuşların altından geç.
const double kGroundY = 1100, kDinoX = 220;

class Obstacle {
  double x;
  final int kind; // 0 kaktüs, 1 çift kaktüs, 2 alçak kuş, 3 yüksek kuş
  bool passed = false;
  Obstacle(this.x, this.kind);
  double get w => kind == 1 ? 110 : (kind >= 2 ? 90 : 60);
  double get top => switch (kind) { 0 => kGroundY - 110, 1 => kGroundY - 90, 2 => kGroundY - 175, _ => kGroundY - 290 };
  double get bottom => switch (kind) { 2 => kGroundY - 105, 3 => kGroundY - 220, _ => kGroundY };
}

class DinoSim extends ArcadeSim {
  final ALevel level;
  double y = kGroundY, vy = 0, speed, dist0 = 0;
  bool ducking = false;
  int jumps = 0, passed = 0, lastEvent = 0;
  final List<Obstacle> obs = [];
  late final int goalM = level.target(400, 120); // metre

  DinoSim(this.level)
      : speed = 9 + level.d * 0.5,
        super(level.meta) {
    _spawn(1100);
  }

  bool get onGround => y >= kGroundY;
  int get meters => dist0 ~/ 10;

  void _spawn(double x) {
    final roll = rng.nextDouble();
    final birds = level.has('birds') || level.d >= 3;
    final kind = birds && roll < 0.3 ? (rng.chance(0.5) ? 2 : 3) : (roll < 0.6 ? 0 : 1);
    obs.add(Obstacle(x, kind));
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    final jump = input.tap && !(input.hasPointer && input.y > 1200) || input.swipe == 0;
    ducking = input.swipe == 2 || (input.down && input.hasPointer && input.y > 1200) || input.dirY > 0;
    if (jump && onGround) {
      vy = -24;
      jumps++;
      lastEvent = 1;
    }
    vy += ducking && !onGround ? 2.4 : 1.15;
    y = math.min(kGroundY, y + vy);
    if (onGround) vy = 0;
    speed = math.min(speed + 0.002, 22.0);
    dist0 += speed;
    for (final o in obs) {
      o.x -= speed;
      if (!o.passed && o.x + o.w < kDinoX - 40) {
        o.passed = true;
        passed++;
        score += 10;
      }
    }
    obs.removeWhere((o) => o.x < -200);
    final last = obs.isEmpty ? 0.0 : obs.last.x;
    if (last < kWorldW + 200) {
      final gapMin = speed * 46; // zıplama süresi ~ 42 tik + eğilme payı
      _spawn(math.max(last, kWorldW) + gapMin + rng.nextDouble() * (520 - level.d * 25));
    }
    // çarpışma
    final h = ducking && onGround ? 70.0 : 130.0;
    final dl = kDinoX - 40, dr = kDinoX + 40, dt = y - h, db = y;
    if (obs.any((o) => dr > o.x + 8 && dl < o.x + o.w - 8 && db > o.top + 8 && dt < o.bottom - 8)) {
      hit();
      lastEvent = 3;
      if (over) return;
    }
    if (goalM > 0 && meters >= goalM) win();
    if (meters > 0 && meters % 100 == 0 && lastEvent == 0 && (dist0 - speed) ~/ 1000 != dist0 ~/ 1000) lastEvent = 2;
  }

  @override
  void onLifeLost() {
    obs.removeWhere((o) => o.x < kDinoX + 400);
  }

  @override
  double get progress => goalM == 0 ? 0 : meters / goalM;
  @override
  String get goalText => goalM == 0 ? '${meters}m' : '$meters/${goalM}m';
  @override
  Map<String, int> get stats => {'meters_run': meters, 'jumps': jumps, 'obstacles_passed': passed};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput dinoBot(ArcadeSim sim) {
  final s = sim as DinoSim;
  Obstacle? next;
  for (final o in s.obs) {
    if (o.x + o.w > kDinoX - 40) {
      next = o;
      break;
    }
  }
  if (next == null) return ArcadeInput.idle;
  final gap = next.x - (kDinoX + 40);
  if (next.kind == 2) {
    // alçak kuş: eğil
    if (gap < s.speed * 12) return holdAt(500, 1400);
    return ArcadeInput.idle;
  }
  if (next.kind == 3) return ArcadeInput.idle;
  if (s.onGround && gap < s.speed * 7 + 20 && gap > -next.w) return tapAt(500, 600);
  return ArcadeInput.idle;
}

void paintDino(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as DinoSim;
  paintSky(c, const Color(0xFFFFE8D6), const Color(0xFFFFB4A2));
  c.drawCircle(const Offset(780, 360), 110, Paint()..color = const Color(0xFFFFF3B0));
  // tepeler
  final hill = Paint()..color = const Color(0xFFE5989B);
  for (var i = 0; i < 4; i++) {
    final x = ((i * 380) - s.dist0 * 0.2) % 1520 - 260;
    c.drawOval(Rect.fromLTWH(x, kGroundY - 220, 520, 400), hill);
  }
  c.drawRect(const Rect.fromLTWH(0, kGroundY, kWorldW, kWorldH - kGroundY), Paint()..color = const Color(0xFFDDA15E));
  final pebble = Paint()..color = const Color(0xFFBC6C25);
  for (var i = 0; i < 20; i++) {
    final x = ((i * 97) - s.dist0) % 1100 - 50;
    c.drawCircle(Offset(x, kGroundY + 20 + (i % 4) * 30), 5, pebble);
  }
  for (final o in s.obs) {
    if (o.kind <= 1) {
      final n = o.kind == 0 ? 1 : 2;
      for (var k = 0; k < n; k++) {
        final cx = o.x + 30 + k * 55;
        final top = o.top + k * 20;
        paintBox(c, Rect.fromLTWH(cx - 18, top, 36, kGroundY - top), const Color(0xFF2D6A4F), radius: 16, shade: false);
        paintBox(c, Rect.fromLTWH(cx - 46, top + 40, 22, 40), const Color(0xFF2D6A4F), radius: 10, shade: false);
        paintBox(c, Rect.fromLTWH(cx + 24, top + 26, 22, 44), const Color(0xFF2D6A4F), radius: 10, shade: false);
      }
    } else {
      final cy = (o.top + o.bottom) / 2;
      final flap = (s.ticks ~/ 8).isEven ? -24.0 : 18.0;
      c.drawOval(Rect.fromCenter(center: Offset(o.x + 45, cy), width: 80, height: 34), Paint()..color = const Color(0xFF6D597A));
      c.drawPath(Path()..moveTo(o.x + 30, cy)..lineTo(o.x + 55, cy + flap)..lineTo(o.x + 70, cy)..close(), Paint()..color = const Color(0xFF355070));
      c.drawPath(Path()..moveTo(o.x + 6, cy - 4)..lineTo(o.x - 16, cy)..lineTo(o.x + 6, cy + 6)..close(), Paint()..color = const Color(0xFFFFB703));
    }
  }
  // dinozor
  final duck = s.ducking && s.onGround;
  final body = s.shield > 0 && (s.ticks ~/ 5).isOdd ? Colors.white54 : p.piece(2);
  final base = Offset(kDinoX, s.y);
  paintShadow(c, Offset(kDinoX, kGroundY + 6), 100);
  if (duck) {
    paintBox(c, Rect.fromLTWH(base.dx - 60, base.dy - 66, 130, 56), body, radius: 26, shade: false);
    c.drawCircle(base + const Offset(48, -48), 8, Paint()..color = Colors.white);
  } else {
    paintBox(c, Rect.fromLTWH(base.dx - 36, base.dy - 120, 70, 90), body, radius: 26, shade: false);
    paintBox(c, Rect.fromLTWH(base.dx + 4, base.dy - 160, 70, 52), body, radius: 22, shade: false);
    c.drawCircle(base + const Offset(48, -142), 9, Paint()..color = Colors.white);
    c.drawCircle(base + const Offset(51, -142), 4, Paint()..color = Colors.black);
    c.drawPath(Path()..moveTo(base.dx - 34, base.dy - 90)..lineTo(base.dx - 80, base.dy - 60)..lineTo(base.dx - 34, base.dy - 56)..close(), Paint()..color = body);
  }
  final step = s.onGround ? ((s.ticks ~/ 6).isEven ? 8.0 : -8.0) : 0.0;
  c.drawRect(Rect.fromLTWH(base.dx - 20 + step, base.dy - 34, 16, 34), Paint()..color = body);
  c.drawRect(Rect.fromLTWH(base.dx + 10 - step, base.dy - 34, 16, 34), Paint()..color = body);
}

Sfx? dinoSound(ArcadeSim sim) => switch ((sim as DinoSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules dinoRules(String id) => KitRules(
      id,
      optionalMechanics: const ['birds'],
      gameStats: const [
        GameStat('meters_run', 'Koşulan metre', 'Meters run', scale: 5000),
        GameStat('jumps', 'Zıplama', 'Jumps', scale: 300),
        GameStat('obstacles_passed', 'Geçilen engel', 'Obstacles passed', scale: 200),
      ],
      missionTemplates: const [
        MissionTemplate('meters_run', 'meters_run', [500, 1000, 2000]),
        MissionTemplate('obstacles_passed', 'obstacles_passed', [20, 40, 80]),
      ],
      make: DinoSim.new,
      botFn: dinoBot,
    );
