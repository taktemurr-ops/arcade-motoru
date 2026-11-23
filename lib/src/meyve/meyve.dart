import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Meyve kesme: aşağıdan fırlayan meyveleri parmağını kaydırarak kes.
/// Bombaya değme; yere düşen meyve can götürür.
class Fruit {
  double x, y, vx, vy, rot;
  final double r;
  final int kind; // 0..5 meyve, 9 bomba
  bool cut = false, gone = false;
  int cutAt = 0;
  double cutAngle = 0;
  Fruit(this.x, this.y, this.vx, this.vy, this.r, this.kind) : rot = 0;
  bool get bomb => kind == 9;
}

class FruitSim extends ArcadeSim {
  final ALevel level;
  final List<Fruit> fruits = [];
  final List<Offset> trail = [];
  int sliced = 0, bombsAvoided = 0, spawnIn = 40, bestMulti = 0, lastEvent = 0;
  double lx = -1, ly = -1;
  late final int goalN = level.target(20, 6);

  FruitSim(this.level) : super(level.meta);

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (--spawnIn <= 0) {
      final n = 1 + rng.nextInt(1 + level.d ~/ 3);
      for (var i = 0; i < n; i++) {
        final bomb = level.has('bombs') && rng.chance(0.12 + level.d * 0.01) && i == 0;
        final x = 150 + rng.nextDouble() * 700;
        final vx = (500 - x) / 90 + (rng.nextDouble() - 0.5) * 3;
        final vy = -(30 + rng.nextDouble() * 6);
        fruits.add(Fruit(x, kWorldH + 60, vx, vy, bomb ? 56 : 58 + rng.nextDouble() * 16, bomb ? 9 : rng.nextInt(6)));
      }
      spawnIn = math.max(36, 90 - level.d * 5);
    }
    final g = 0.48 + level.d * 0.01;
    for (final f in fruits) {
      f.vy += g;
      f.x += f.vx;
      f.y += f.vy;
      f.rot += 0.05;
    }
    // Kesme çizgisi
    if (input.down && input.hasPointer) {
      trail.add(Offset(input.x, input.y));
      if (trail.length > 8) trail.removeAt(0);
      if (lx >= 0) {
        final len = dist(lx, ly, input.x, input.y);
        if (len > 18) {
          var multi = 0;
          for (final f in fruits) {
            if (f.cut || f.gone) continue;
            if (segDist(f.x, f.y, lx, ly, input.x, input.y) < f.r) {
              if (f.bomb) {
                f.gone = true;
                lastEvent = 3;
                hit();
                if (over) return;
              } else {
                f.cut = true;
                f.cutAt = ticks;
                f.cutAngle = math.atan2(input.y - ly, input.x - lx);
                sliced++;
                multi++;
                score += 10;
                lastEvent = 1;
              }
            }
          }
          if (multi >= 2) {
            score += multi * 10;
            lastEvent = 2;
          }
          bestMulti = math.max(bestMulti, multi);
          if (goalN > 0 && sliced >= goalN) win();
        }
      }
      lx = input.x;
      ly = input.y;
    } else {
      lx = ly = -1;
      trail.clear();
    }
    for (final f in fruits) {
      if (!f.gone && f.vy > 0 && f.y > kWorldH + 80) {
        f.gone = true;
        if (f.bomb) {
          bombsAvoided++;
        } else if (!f.cut) {
          lastEvent = 3;
          hit();
        }
      }
    }
    fruits.removeWhere((f) => f.gone || (f.cut && ticks - f.cutAt > 50));
  }

  @override
  double get progress => goalN == 0 ? 0 : sliced / goalN;
  @override
  String get goalText => goalN == 0 ? '$sliced' : '$sliced/$goalN';
  @override
  Map<String, int> get stats => {'fruits_sliced': sliced, 'bombs_avoided': bombsAvoided, 'best_multi': bestMulti};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: kesilmemiş en alçak (düşmekte olan) meyveye yatay kısa bir kesik atar;
/// kesik bombaya değecekse dikey dener.
class _FruitBotState {
  int phase = 0;
  double x1 = 0, y1 = 0;
}

final _fruitBot = Expando<_FruitBotState>();

ArcadeInput fruitBot(ArcadeSim sim) {
  final s = sim as FruitSim;
  final st = _fruitBot[s] ??= _FruitBotState();
  if (st.phase == 1) {
    st.phase = 2;
    return holdAt(st.x1, st.y1);
  }
  if (st.phase == 2) {
    st.phase = 0;
    return ArcadeInput.idle;
  }
  Fruit? best;
  for (final f in s.fruits) {
    if (f.cut || f.bomb || f.y > kWorldH - 30 || f.y < 60) continue;
    if (best == null || f.vy > best.vy) best = f;
  }
  if (best == null) return ArcadeInput.idle;
  // İki tik sonraki konum
  final fx = best.x + best.vx * 2, fy = best.y + best.vy * 2 + 1;
  bool clear(double ax, double ay, double bx, double by) {
    for (final o in s.fruits) {
      if (!o.bomb || o.gone) continue;
      for (var k = 0; k <= 2; k++) {
        if (segDist(o.x + o.vx * k, o.y + o.vy * k, ax, ay, bx, by) < o.r + 40) return false;
      }
    }
    return true;
  }

  for (final (dx, dy) in const [(1.0, 0.0), (0.0, 1.0), (0.7, 0.7), (0.7, -0.7)]) {
    final ax = fx - dx * 70, ay = fy - dy * 70, bx = fx + dx * 70, by = fy + dy * 70;
    if (clear(ax, ay, bx, by)) {
      st
        ..phase = 1
        ..x1 = bx
        ..y1 = by;
      return holdAt(ax, ay);
    }
  }
  return ArcadeInput.idle;
}

const _fruitCols = [Color(0xFFE63946), Color(0xFFFFB703), Color(0xFF8AC926), Color(0xFFFF7F11), Color(0xFF9D4EDD), Color(0xFFFFD60A)];
const _fleshCols = [Color(0xFFFFCCD5), Color(0xFFFFF3B0), Color(0xFFE9F5DB), Color(0xFFFFE5B4), Color(0xFFE0C3FC), Color(0xFFFFFFE0)];

void paintFruits(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as FruitSim;
  // ahşap kesme tahtası
  paintSky(c, const Color(0xFF6F4518), const Color(0xFF432818));
  final grain = Paint()
    ..color = Colors.black12
    ..strokeWidth = 4;
  for (var y = 40.0; y < kWorldH; y += 90) {
    c.drawLine(Offset(0, y), Offset(kWorldW, y + 20), grain);
  }
  for (final f in s.fruits) {
    final o = Offset(f.x, f.y);
    if (f.bomb) {
      paintBall(c, o, f.r, const Color(0xFF212529));
      c.drawLine(o + Offset(0, -f.r), o + Offset(14, -f.r - 26), Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = 6);
      c.drawCircle(o + Offset(14, -f.r - 30), 9 + (s.ticks % 6).toDouble(), Paint()..color = const Color(0xFFFF6D00));
      continue;
    }
    final col = _fruitCols[f.kind];
    if (!f.cut) {
      paintBall(c, o, f.r, col);
      c.drawOval(Rect.fromCenter(center: o + Offset(0, -f.r * 0.95), width: 20, height: 34), Paint()..color = const Color(0xFF2D6A4F));
    } else {
      final sep = (s.ticks - f.cutAt) * 3.0;
      final nx = -math.sin(f.cutAngle), ny = math.cos(f.cutAngle);
      for (final sgn in [-1.0, 1.0]) {
        c.save();
        c.translate(f.x + nx * sep * sgn, f.y + ny * sep * sgn + sep * sep * 0.01);
        c.rotate(f.cutAngle);
        final rect = Rect.fromCircle(center: Offset.zero, radius: f.r);
        c.drawArc(rect, sgn < 0 ? math.pi : 0, math.pi, true, Paint()..color = col);
        c.drawArc(rect.deflate(8), sgn < 0 ? math.pi : 0, math.pi, true, Paint()..color = _fleshCols[f.kind]);
        c.restore();
      }
    }
  }
  if (s.trail.length >= 2) {
    for (var i = 1; i < s.trail.length; i++) {
      c.drawLine(s.trail[i - 1], s.trail[i], Paint()
        ..color = Colors.white.withValues(alpha: i / s.trail.length)
        ..strokeWidth = 4.0 + i * 2
        ..strokeCap = StrokeCap.round);
    }
  }
}

Sfx? fruitSound(ArcadeSim sim) => switch ((sim as FruitSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.combo,
      3 => Sfx.error,
      _ => null,
    };

KitRules fruitRules(String id) => KitRules(
      id,
      optionalMechanics: const ['bombs'],
      gameStats: const [
        GameStat('fruits_sliced', 'Kesilen meyve', 'Fruits sliced', scale: 300),
        GameStat('bombs_avoided', 'Atlatılan bomba', 'Bombs avoided', scale: 50),
        GameStat('best_multi', 'Tek kesikte en çok', 'Best multi-slice', scale: 3),
      ],
      missionTemplates: const [
        MissionTemplate('fruits_sliced', 'fruits_sliced', [40, 80, 150]),
        MissionTemplate('bombs_avoided', 'bombs_avoided', [5, 10, 20]),
      ],
      make: FruitSim.new,
      botFn: fruitBot,
    );
