import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Köstebek vurma: deliklerden çıkan köstebeklere dokun. Kasklı olan iki
/// vuruş ister; çiçeğe (tuzak) dokunma. Kaçan köstebek can götürür.
class Mole {
  final int hole;
  final int kind; // 0 normal, 1 kasklı, 2 çiçek (dokunma), 3 altın
  int hp;
  final int born, stay;
  int hitAt = -1;
  Mole(this.hole, this.kind, this.born, this.stay) : hp = kind == 1 ? 2 : 1;
}

class MoleSim extends ArcadeSim {
  final ALevel level;
  late final int cols = level.d >= 6 ? 4 : 3;
  late final int rows = level.d >= 4 ? 4 : 3;
  final List<Mole> moles = [];
  final List<Fx> fx = [];
  int whacked = 0, golden = 0, nextIn = 30, streak = 0, bestStreak = 0, lastEvent = 0, missFlash = 0;
  late final int goalN = level.target(20, 5);

  MoleSim(this.level) : super(level.meta, lives: 5);

  Offset holePos(int i) {
    final c = i % cols, r = i ~/ cols;
    final w = kWorldW / cols;
    return Offset(w * (c + 0.5), 520 + r * (900 / rows) + (900 / rows) * 0.5);
  }

  double get holeR => cols == 4 ? 92 : 115;

  /// Köstebeğin yükselme oranı 0..1.
  double rise(Mole m) {
    final age = ticks - m.born;
    if (m.hitAt >= 0) return clampD(1 - (ticks - m.hitAt) / 12, 0, 1);
    if (age < 10) return age / 10;
    if (age > m.stay - 10) return clampD((m.stay - age) / 10, 0, 1);
    return 1;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (missFlash > 0) missFlash--;
    if (--nextIn <= 0) {
      final free = [for (var i = 0; i < cols * rows; i++) if (moles.every((m) => m.hole != i)) i];
      if (free.isNotEmpty) {
        final roll = rng.nextDouble();
        final kind = roll < 0.05 ? 3 : (level.has('decoys') && roll < 0.2 ? 2 : (level.has('helmets') && roll < 0.35 ? 1 : 0));
        final stay = math.max(48, 120 - level.d * 7 - math.min(whacked, 80) ~/ 4);
        moles.add(Mole(rng.pick(free), kind, ticks, stay));
      }
      nextIn = math.max(14, 50 - level.d * 3 - whacked ~/ 8);
    }
    if (input.tap && input.hasPointer) {
      Mole? hitM;
      for (final m in moles) {
        if (m.hitAt >= 0 || rise(m) < 0.3) continue;
        final o = holePos(m.hole);
        if (dist(input.x, input.y, o.dx, o.dy - holeR * 0.5) < holeR) hitM = m;
      }
      if (hitM != null) {
        final o = holePos(hitM.hole);
        if (hitM.kind == 2) {
          hitM.hitAt = ticks;
          streak = 0;
          lastEvent = 3;
          missFlash = 20;
          hit();
        } else if (--hitM.hp <= 0) {
          hitM.hitAt = ticks;
          whacked++;
          streak++;
          bestStreak = math.max(streak, bestStreak);
          if (hitM.kind == 3) golden++;
          score += (hitM.kind == 3 ? 60 : (hitM.kind == 1 ? 25 : 10)) + math.min(streak, 20);
          fx.add(Fx(o.dx, o.dy - holeR * 0.6, ticks, hitM.kind == 3 ? 1 : 0));
          lastEvent = hitM.kind == 3 ? 2 : 1;
          if (goalN > 0 && whacked >= goalN) win();
        } else {
          lastEvent = 1;
        }
      }
    }
    for (final m in moles) {
      if (m.hitAt < 0 && ticks - m.born >= m.stay) {
        m.hitAt = ticks - 12;
        if (m.kind != 2) {
          streak = 0;
          missFlash = 20;
          lastEvent = 3;
          hit();
        }
      }
    }
    moles.removeWhere((m) => m.hitAt >= 0 && ticks - m.hitAt >= 12);
    pruneFx(fx, ticks);
  }

  @override
  double get progress => goalN == 0 ? 0 : whacked / goalN;
  @override
  String get goalText => goalN == 0 ? '$whacked' : '$whacked/$goalN';
  @override
  Map<String, int> get stats => {'moles_whacked': whacked, 'golden_moles': golden, 'best_streak': bestStreak};
  @override
  int get stars => lifeStars(this, 5);
}

ArcadeInput moleBot(ArcadeSim sim) {
  final s = sim as MoleSim;
  if (s.ticks % 3 != 0) return ArcadeInput.idle;
  Mole? best;
  for (final m in s.moles) {
    if (m.kind == 2 || m.hitAt >= 0 || s.rise(m) < 0.5) continue;
    if (best == null || m.born + m.stay < best.born + best.stay) best = m;
  }
  if (best == null) return ArcadeInput.idle;
  final o = s.holePos(best.hole);
  return tapAt(o.dx, o.dy - s.holeR * 0.5);
}

void paintMoles(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as MoleSim;
  paintSky(c, const Color(0xFF90BE6D), const Color(0xFF43AA8B));
  final tuft = Paint()..color = const Color(0x2F000000);
  for (var i = 0; i < 40; i++) {
    c.drawCircle(Offset((i * 173.0) % kWorldW, 300 + (i * 397.0) % 1300), 10, tuft);
  }
  if (s.missFlash > 0) {
    c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = Colors.red.withValues(alpha: s.missFlash / 80));
  }
  final r = s.holeR;
  for (var i = 0; i < s.cols * s.rows; i++) {
    final o = s.holePos(i);
    c.drawOval(Rect.fromCenter(center: o, width: r * 2.1, height: r * 0.8), Paint()..color = const Color(0xFF5C3D2E));
    c.drawOval(Rect.fromCenter(center: o + const Offset(0, 6), width: r * 1.8, height: r * 0.6), Paint()..color = const Color(0xFF2B1B12));
  }
  for (final m in s.moles) {
    final o = s.holePos(m.hole);
    final up = s.rise(m);
    c.save();
    c.clipRect(Rect.fromLTRB(o.dx - r * 1.2, o.dy - r * 2.2, o.dx + r * 1.2, o.dy + 4));
    final cy = o.dy + r * 1.1 - up * r * 1.6;
    if (m.kind == 2) {
      for (var k = 0; k < 6; k++) {
        final a = k / 6 * math.pi * 2 + s.ticks * 0.02;
        c.drawCircle(Offset(o.dx + math.cos(a) * r * 0.42, cy + math.sin(a) * r * 0.42), r * 0.32, Paint()..color = const Color(0xFFFF8FAB));
      }
      c.drawCircle(Offset(o.dx, cy), r * 0.3, Paint()..color = const Color(0xFFFFD60A));
    } else {
      final body = m.kind == 3 ? const Color(0xFFFFC300) : const Color(0xFF8D6E63);
      c.drawOval(Rect.fromCenter(center: Offset(o.dx, cy + r * 0.3), width: r * 1.5, height: r * 1.9), Paint()..color = body);
      c.drawOval(Rect.fromCenter(center: Offset(o.dx, cy + r * 0.45), width: r * 0.8, height: r * 0.7), Paint()..color = const Color(0xFFD7CCC8));
      final stunned = m.hitAt >= 0;
      for (final sx in [-1.0, 1.0]) {
        final e = Offset(o.dx + sx * r * 0.28, cy - r * 0.12);
        if (stunned) {
          c.drawLine(e + const Offset(-10, -10), e + const Offset(10, 10), Paint()..strokeWidth = 5);
          c.drawLine(e + const Offset(-10, 10), e + const Offset(10, -10), Paint()..strokeWidth = 5);
        } else {
          c.drawCircle(e, 11, Paint()..color = Colors.black);
          c.drawCircle(e + const Offset(-3, -3), 4, Paint()..color = Colors.white);
        }
      }
      c.drawOval(Rect.fromCenter(center: Offset(o.dx, cy + r * 0.15), width: 30, height: 22), Paint()..color = const Color(0xFFFF8FA3));
      if (m.kind == 1 && m.hp > 1) {
        c.drawArc(Rect.fromCenter(center: Offset(o.dx, cy - r * 0.2), width: r * 1.6, height: r * 1.3), math.pi, math.pi, true, Paint()..color = p.piece(2));
      }
    }
    c.restore();
  }
  paintFxList(c, s.fx, s.ticks, p);
}

Sfx? moleSound(ArcadeSim sim) => switch ((sim as MoleSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules moleRules(String id) => KitRules(
      id,
      optionalMechanics: const ['helmets', 'decoys'],
      gameStats: const [
        GameStat('moles_whacked', 'Vurulan köstebek', 'Moles whacked', scale: 300),
        GameStat('golden_moles', 'Altın köstebek', 'Golden moles', scale: 20),
        GameStat('best_streak', 'En iyi seri', 'Best streak', scale: 20),
      ],
      missionTemplates: const [
        MissionTemplate('moles_whacked', 'moles_whacked', [40, 80, 150]),
        MissionTemplate('best_streak', 'best_streak', [10, 20, 40]),
      ],
      make: MoleSim.new,
      botFn: moleBot,
    );
