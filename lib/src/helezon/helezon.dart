import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Helezon düşüş: top sürekli zıplar; parmağını yatay sürükleyerek kuleyi
/// döndür. Top boşluğa denk gelirse bir kat aşağı düşer; kırmızı dilime
/// düşerse can gider. Üç katı arka arkaya geçen top kırmızıyı da kırar.
const int kSegs = 12;
const double kRingGap = 300, kBallScreenY = 560;

class Ring {
  final List<int> segs; // 0 güvenli, 1 boşluk, 2 tehlike
  Ring(this.segs);
}

class HelixSim extends ArcadeSim {
  final ALevel level;
  final List<Ring> rings = [];
  double rot = 0; // derece
  double ballY = 220, vy = 0; // ballY: halkaya göre yükseklik (0 = halkada)
  int floor = 0, combo = 0, bestCombo = 0, lastEvent = 0, broken = 0;
  double lastPx = -1;
  late final int floors = level.target(12, 3) == 0 ? 0 : 12 + level.d * 3;

  HelixSim(this.level) : super(level.meta) {
    for (var i = 0; i < (floors == 0 ? 60 : floors); i++) {
      _addRing();
    }
  }

  void _addRing() {
    final segs = List<int>.filled(kSegs, 0);
    final gapAt = rng.nextInt(kSegs);
    segs[gapAt] = 1;
    if (level.d >= 5 && rng.chance(0.4)) segs[(gapAt + 1) % kSegs] = 1;
    final danger = math.min(1 + level.d ~/ 2, 5);
    for (var k = 0; k < danger; k++) {
      final i = rng.nextInt(kSegs);
      if (segs[i] == 0 && (i - gapAt).abs() % kSegs > 1) segs[i] = 2;
    }
    rings.add(Ring(segs));
  }

  /// Topun altındaki dilim (top ekranda önde, açı 90°).
  int segUnderBall() {
    final a = ((90 - rot) % 360 + 360) % 360;
    return (a / (360 / kSegs)).floor() % kSegs;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      if (lastPx >= 0) rot += clampD((input.x - lastPx) * 0.45, -24, 24);
      lastPx = input.x;
    } else {
      lastPx = -1;
      if (input.dirX != 0) rot += input.dirX * 5;
    }
    rot = (rot % 360 + 360) % 360;
    vy += 0.9;
    ballY -= vy; // yukarı pozitif
    if (ballY <= 0 && vy > 0) {
      // Halkaya değdi
      if (floor >= rings.length) {
        if (floors > 0) {
          win();
          return;
        }
        for (var i = 0; i < 20; i++) {
          _addRing();
        }
      }
      final seg = rings[floor].segs[segUnderBall()];
      if (seg == 1) {
        _fall();
      } else if (combo >= 3) {
        // Hızlı top halkayı kırar.
        broken++;
        score += 30;
        lastEvent = 2;
        _fall();
      } else if (seg == 2) {
        combo = 0;
        ballY = 0;
        vy = -16;
        lastEvent = 3;
        hit();
      } else {
        combo = 0;
        ballY = 0;
        vy = -16;
        lastEvent = 1;
      }
    }
  }

  void _fall() {
    floor++;
    combo++;
    bestCombo = math.max(combo, bestCombo);
    score += 10 * combo;
    ballY += kRingGap;
    if (lastEvent == 0) lastEvent = 4;
    if (floors > 0 && floor >= floors) win();
  }

  @override
  void onLifeLost() {
    combo = 0;
  }

  @override
  double get progress => floors == 0 ? 0 : floor / floors;
  @override
  String get goalText => floors == 0 ? '$floor' : '$floor/$floors';
  @override
  Map<String, int> get stats => {'floors_dropped': floor, 'best_combo': bestCombo, 'rings_smashed': broken};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: boşluk dilimini topun altına getirmek için döndürür.
ArcadeInput helixBot(ArcadeSim sim) {
  final s = sim as HelixSim;
  if (s.floor >= s.rings.length) return ArcadeInput.idle;
  final segs = s.rings[s.floor].segs;
  final w = 360 / kSegs;
  // Topun halkaya inmesine kalan süre
  final land = (-s.vy + math.sqrt(math.max(0, s.vy * s.vy + 1.8 * math.max(0, s.ballY)))) / 0.9;
  double nearest(int kind) {
    var best = 999.0;
    for (var i = 0; i < kSegs; i++) {
      if (segs[i] != kind) continue;
      final segCenter = (i + 0.5) * w;
      // Ekranda topun açısı 90: rot + segCenter = 90 olmalı.
      var delta = ((90 - segCenter) - s.rot) % 360;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      if (delta.abs() < best.abs()) best = delta;
    }
    return best;
  }

  var bestDelta = nearest(1);
  if (bestDelta.abs() / 20 > land - 1 && segs[s.segUnderBall()] == 2) bestDelta = nearest(0);
  if (bestDelta.abs() < 2) return ArcadeInput.idle;
  // Sürükleme: lastPx tabanlı; sabit referanstan dx kadar kaydır.
  final dx = clampD(bestDelta / 0.45, -48, 48);
  final base = s.lastPx < 0 ? 500.0 : s.lastPx;
  if (s.lastPx < 0) return holdAt(base, 1200);
  final nx = base + dx;
  if (nx < 60 || nx > 940) {
    return ArcadeInput.idle; // parmağı kaldır, ortadan yeniden başla
  }
  return holdAt(nx, 1200);
}

void paintHelix(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as HelixSim;
  paintSky(c, p.piece(5).withValues(alpha: 1), Color.lerp(p.piece(5), Colors.black, 0.5)!);
  // direk
  c.drawRect(const Rect.fromLTWH(455, 0, 90, kWorldH), Paint()
    ..shader = const LinearGradient(colors: [Color(0xFFDEE2E6), Color(0xFFADB5BD), Color(0xFF6C757D)]).createShader(const Rect.fromLTWH(455, 0, 90, kWorldH)));
  final w = 360 / kSegs;
  // Görünen halkalar: floor-1 .. floor+4
  for (var k = 4; k >= -1; k--) {
    final i = s.floor + k;
    if (i < 0 || i >= s.rings.length) continue;
    final cy = kBallScreenY + 40 + k * kRingGap;
    final rect = Rect.fromCenter(center: Offset(500, cy), width: 760, height: 220);
    final segs = s.rings[i].segs;
    for (final back in [true, false]) {
      for (var j = 0; j < kSegs; j++) {
        final start = (s.rot + j * w) % 360;
        final mid = (start + w / 2) % 360;
        final isBack = mid > 180;
        if (isBack != back) continue;
        final v = segs[j];
        if (v == 1) continue;
        final col = v == 2 ? const Color(0xFFE63946) : p.piece(i % 4);
        final shade = back ? Color.lerp(col, Colors.black, 0.35)! : col;
        // kalınlık için iki kat
        c.drawArc(rect.shift(const Offset(0, 26)), start * math.pi / 180, w * math.pi / 180, true, Paint()..color = Color.lerp(shade, Colors.black, 0.3)!);
        c.drawArc(rect, start * math.pi / 180, w * math.pi / 180, true, Paint()..color = shade);
      }
      if (back) {
        c.drawOval(Rect.fromCenter(center: Offset(500, cy), width: 90, height: 30), Paint()..color = const Color(0xFFADB5BD));
      }
    }
  }
  // top (önde, 90°)
  final by = kBallScreenY + 40 + 110 - 26 - s.ballY;
  paintShadow(c, Offset(500, kBallScreenY + 40 + 110), 60);
  final ballCol = s.combo >= 3 ? const Color(0xFFFFB703) : Colors.white;
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, Offset(500, by), 28, blink ? Colors.white38 : ballCol);
}

Sfx? helixSound(ArcadeSim sim) => switch ((sim as HelixSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.combo,
      3 => Sfx.error,
      4 => Sfx.place,
      _ => null,
    };

KitRules helixRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('floors_dropped', 'İnilen kat', 'Floors dropped', scale: 500),
        GameStat('best_combo', 'En iyi seri', 'Best combo', scale: 5),
        GameStat('rings_smashed', 'Kırılan halka', 'Rings smashed', scale: 100),
      ],
      missionTemplates: const [
        MissionTemplate('floors_dropped', 'floors_dropped', [30, 60, 120]),
        MissionTemplate('rings_smashed', 'rings_smashed', [3, 6, 12]),
      ],
      make: HelixSim.new,
      botFn: helixBot,
    );
