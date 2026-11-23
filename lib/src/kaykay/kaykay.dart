import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kaykay koşusu: üç şeritli sokak, perspektif görünüm. Sağa/sola kaydır =
/// şerit değiştir, yukarı = zıpla, aşağı = eğil. Alçak bariyerin üstünden
/// zıpla, yüksek tabelanın altından eğil, kamyonetten şerit değiştir.
class Thing {
  double z; // oyuncudan uzaklık (0 = oyuncu hizası)
  final int lane, kind; // 0 bariyer (zıpla), 1 tabela (eğil), 2 kamyonet (kaç), 3 jeton
  bool taken = false;
  Thing(this.z, this.lane, this.kind);
  double get len => kind == 2 ? 260 : 40;
}

class SkateSim extends ArcadeSim {
  final ALevel level;
  int lane = 1, jumps = 0, coins = 0, lastEvent = 0, slideT = 0;
  double laneX = 1, h = 0, vh = 0, speed, travelled = 0;
  final List<Thing> things = [];
  double nextZ = 900;
  late final int goalM = level.target(500, 150);

  SkateSim(this.level)
      : speed = 9 + level.d * 0.5,
        super(level.meta);

  int get meters => travelled ~/ 10;
  bool get sliding => slideT > 0;

  void _row(double z) {
    // Her satırda en az bir güvenli şerit kalır.
    final free = rng.nextInt(3);
    for (var l = 0; l < 3; l++) {
      if (l == free) {
        if (rng.chance(0.5)) things.add(Thing(z, l, 3));
        continue;
      }
      final r = rng.nextDouble();
      if (r < 0.35) continue;
      final kind = r < 0.6 ? 0 : (r < 0.8 ? 1 : 2);
      things.add(Thing(z, l, kind));
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var sw = input.swipe;
    if (sw < 0 && input.dirX != 0) sw = input.dirX > 0 ? 1 : 3;
    if (sw == 1 && lane < 2) lane++;
    if (sw == 3 && lane > 0) lane--;
    if ((sw == 0 || (input.tap && input.swipe < 0 && input.hasPointer && input.y < 1100)) && h == 0) {
      vh = 21;
      jumps++;
      lastEvent = 1;
    }
    if (sw == 2) {
      slideT = 40;
      if (h > 0) vh = -24;
    }
    if (slideT > 0) slideT--;
    laneX = moveToward(laneX, lane.toDouble(), 0.16);
    vh -= 1.1;
    h = math.max(0.0, h + vh);
    if (h == 0) vh = 0;
    speed = math.min(speed + 0.0015, 22.0);
    travelled += speed;
    for (final t in things) {
      t.z -= speed;
    }
    nextZ -= speed;
    if (nextZ < 1800) {
      _row(nextZ + 600);
      nextZ += speed * (42 + rng.nextInt(20)) + 120;
    }
    for (final t in things) {
      if (t.taken || t.z > 30 || t.z + t.len < -30) continue;
      if ((laneX - t.lane).abs() > 0.45) continue;
      switch (t.kind) {
        case 3:
          t.taken = true;
          coins++;
          score += 5;
          lastEvent = 2;
        case 0:
          if (h < 70) {
            t.taken = true;
            lastEvent = 3;
            hit();
          }
        case 1:
          if (!sliding) {
            t.taken = true;
            lastEvent = 3;
            hit();
          }
        default:
          t.taken = true;
          lastEvent = 3;
          hit();
      }
      if (over) return;
    }
    things.removeWhere((t) => t.z + t.len < -200);
    if (goalM > 0 && meters >= goalM) win();
  }

  @override
  void onLifeLost() {
    things.removeWhere((t) => t.z < 700 && t.kind != 3);
  }

  @override
  double get progress => goalM == 0 ? 0 : meters / goalM;
  @override
  String get goalText => goalM == 0 ? '${meters}m' : '$meters/${goalM}m';
  @override
  Map<String, int> get stats => {'meters_run': meters, 'coins_collected': coins, 'jumps': jumps};
  @override
  int get stars => lifeStars(this, 3);
}

bool _laneBlocked(SkateSim s, int lane, double zMin, double zMax, {bool hard = false}) {
  for (final t in s.things) {
    if (t.lane != lane || t.taken || t.kind == 3) continue;
    if (hard && t.kind != 2) continue;
    if (t.z < zMax && t.z + t.len > zMin) return true;
  }
  return false;
}

ArcadeInput skateBot(ArcadeSim sim) {
  final s = sim as SkateSim;
  // Şerit hareket ederken bekle.
  if ((s.laneX - s.lane).abs() > 0.05) return ArcadeInput.idle;
  final look = s.speed * 26;
  Thing? next;
  for (final t in s.things) {
    if (t.lane != s.lane || t.taken || t.kind == 3 || t.z + t.len < -10) continue;
    if (next == null || t.z < next.z) next = t;
  }
  if (next != null && next.z < look) {
    // Önce şerit değiştirmeyi dene (en güvenli).
    for (final d in [-1, 1]) {
      final l = s.lane + d;
      if (l < 0 || l > 2) continue;
      if (!_laneBlocked(s, l, -60, look + 80)) return ArcadeInput(swipe: d > 0 ? 1 : 3);
    }
    final t = next.z / s.speed;
    if (next.kind == 0 && t < 9 && s.h == 0) return const ArcadeInput(swipe: 0);
    if (next.kind == 1 && t < 14 && !s.sliding) return const ArcadeInput(swipe: 2);
    if (next.kind == 2) {
      for (final d in [-1, 1]) {
        final l = s.lane + d;
        if (l >= 0 && l <= 2 && !_laneBlocked(s, l, -60, 120, hard: true)) return ArcadeInput(swipe: d > 0 ? 1 : 3);
      }
    }
  }
  return ArcadeInput.idle;
}

/// Perspektif: z (0..2400) → ekran y ve ölçek.
(double, double) _proj(double z) {
  final sc = 1 / (1 + math.max(z, -150) / 520);
  return (480 + 920 * sc, sc);
}

double _laneScreenX(double lane, double sc) => 500 + (lane - 1) * 300 * sc;

void paintSkate(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SkateSim;
  paintSky(c, const Color(0xFF4CC9F0), const Color(0xFFB8F2E6));
  // binalar
  for (var i = 0; i < 8; i++) {
    final h = 180.0 + (i * 53) % 160;
    final x = i * 130.0 - 20;
    paintBox(c, Rect.fromLTWH(x, 480 - h, 120, h), p.piece(i), radius: 6, shade: false);
  }
  // yol
  final road = Path()
    ..moveTo(500 - 470, kWorldH)
    ..lineTo(500 - 40, 480)
    ..lineTo(500 + 40, 480)
    ..lineTo(500 + 470, kWorldH)
    ..close();
  c.drawPath(road, Paint()..color = const Color(0xFF495057));
  final stripe = Paint()..color = Colors.white54;
  for (var k = 0; k < 14; k++) {
    final z = (k * 200 - s.travelled % 200);
    final (y1, s1) = _proj(z);
    final (y2, s2) = _proj(z + 90);
    for (final l in [0.5, 1.5]) {
      c.drawLine(Offset(_laneScreenX(l, s1), y1), Offset(_laneScreenX(l, s2), y2), stripe..strokeWidth = 10 * s1);
    }
  }
  final sorted = [...s.things]..sort((a, b) => b.z.compareTo(a.z));
  for (final th in sorted) {
    if (th.taken || th.z > 2400) continue;
    final (y, sc) = _proj(th.z);
    final x = _laneScreenX(th.lane.toDouble(), sc);
    switch (th.kind) {
      case 0:
        paintBox(c, Rect.fromCenter(center: Offset(x, y - 40 * sc), width: 220 * sc, height: 80 * sc), const Color(0xFFF77F00), radius: 8 * sc);
        for (var k = 0; k < 3; k++) {
          c.drawRect(Rect.fromLTWH(x - 100 * sc + k * 70 * sc, y - 70 * sc, 34 * sc, 60 * sc), Paint()..color = Colors.white70);
        }
      case 1:
        c.drawRect(Rect.fromLTWH(x - 100 * sc, y - 200 * sc, 12 * sc, 200 * sc), Paint()..color = Colors.black54);
        c.drawRect(Rect.fromLTWH(x + 88 * sc, y - 200 * sc, 12 * sc, 200 * sc), Paint()..color = Colors.black54);
        paintBox(c, Rect.fromLTWH(x - 110 * sc, y - 260 * sc, 220 * sc, 90 * sc), const Color(0xFF2A9D8F), radius: 10 * sc);
      case 2:
        final (yb, scb) = _proj(th.z + th.len);
        final xb = _laneScreenX(th.lane.toDouble(), scb);
        final side = Path()
          ..moveTo(x - 120 * sc, y)
          ..lineTo(xb - 120 * scb, yb)
          ..lineTo(xb - 120 * scb, yb - 240 * scb)
          ..lineTo(x - 120 * sc, y - 240 * sc)
          ..close();
        c.drawPath(side, Paint()..color = const Color(0xFF8D99AE));
        paintBox(c, Rect.fromLTWH(x - 120 * sc, y - 240 * sc, 240 * sc, 240 * sc), const Color(0xFFEDF2F4), radius: 14 * sc);
        c.drawRect(Rect.fromLTWH(x - 90 * sc, y - 210 * sc, 180 * sc, 80 * sc), Paint()..color = const Color(0xFF2B2D42));
      default:
        paintBall(c, Offset(x, y - 70 * sc + math.sin(s.ticks / 8 + th.z) * 8 * sc), 34 * sc, const Color(0xFFFFC300));
    }
  }
  // oyuncu
  final (py, psc) = _proj(0);
  final px = _laneScreenX(s.laneX, psc);
  paintShadow(c, Offset(px, py), 160);
  final body = s.shield > 0 && (s.ticks ~/ 5).isOdd ? Colors.white54 : p.piece(0);
  final top = py - s.h - (s.sliding ? 90 : 190);
  paintBox(c, Rect.fromLTWH(px - 90, py - s.h - 26, 180, 22), const Color(0xFF6A4C93), radius: 11);
  c.drawCircle(Offset(px - 60, py - s.h), 12, Paint()..color = Colors.black87);
  c.drawCircle(Offset(px + 60, py - s.h), 12, Paint()..color = Colors.black87);
  paintBox(c, Rect.fromLTRB(px - 40, top + 40, px + 40, py - s.h - 30), body, radius: 22, shade: false);
  c.drawCircle(Offset(px, top + 18), 34, Paint()..color = const Color(0xFFFFD6A5));
  c.drawArc(Rect.fromCircle(center: Offset(px, top + 14), radius: 36), math.pi, math.pi, true, Paint()..color = p.piece(3));
}

Sfx? skateSound(ArcadeSim sim) => switch ((sim as SkateSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules skateRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('meters_run', 'Kayılan metre', 'Meters skated', scale: 5000),
        GameStat('coins_collected', 'Jeton', 'Coins', scale: 300),
        GameStat('jumps', 'Zıplama', 'Jumps', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('meters_run', 'meters_run', [500, 1000, 2000]),
        MissionTemplate('coins_collected', 'coins_collected', [20, 50, 100]),
      ],
      make: SkateSim.new,
      botFn: skateBot,
    );
