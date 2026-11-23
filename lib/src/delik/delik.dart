import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Delik büyütme: parmağınla deliği gezdir. Delikten küçük nesneler içine
/// düşer ve delik büyür. Büyük nesneler için önce büyümen gerekir. Sarı
/// yıldızlı nesneler ekstra puan. Rakip delik (bazı bölümlerde) senden
/// büyükse sana değmesi can götürür; küçükse onu da yutarsın.
class Thing {
  final double x, y, size;
  final int kind, color;
  bool eaten = false;
  int eatenAt = 0;
  Thing(this.x, this.y, this.size, this.kind, this.color);
}

class HoleSim extends ArcadeSim {
  final ALevel level;
  final List<Thing> things = [];
  double x = 500, y = 900, r = 46;
  double rx = 0, ry = 0, rr = 0; // rakip
  double rvx = 0, rvy = 0;
  bool rival = false;
  int eaten = 0, lastEvent = 0, rivalsEaten = 0;
  late final int goalN = level.target(40, 10);

  HoleSim(this.level) : super(level.meta) {
    _fill(70);
    rival = level.has('rival') || level.d >= 6;
    if (rival) {
      rx = 200;
      ry = 300;
      rr = 60;
    }
  }

  void _fill(int n) {
    for (var i = 0; i < n; i++) {
      final roll = rng.nextDouble();
      final size = roll < 0.55 ? 22 + rng.nextDouble() * 14 : (roll < 0.85 ? 44 + rng.nextDouble() * 20 : 72 + rng.nextDouble() * 40);
      var px = 60 + rng.nextDouble() * 880, py = 200 + rng.nextDouble() * 1340;
      if (dist(px, py, x, y) < r + 80) py = (py + 600) % 1340 + 200;
      things.add(Thing(px, py, size, rng.nextInt(4), rng.nextInt(6)));
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      final d = dist(x, y, input.x, input.y);
      final sp = math.min(d, 9 + 300 / r);
      if (d > 1) {
        x += (input.x - x) / d * sp;
        y += (input.y - y) / d * sp;
      }
    } else if (input.dirX != 0 || input.dirY != 0) {
      x += input.dirX * 10;
      y += input.dirY * 10;
    }
    x = clampD(x, r * 0.5, kWorldW - r * 0.5);
    y = clampD(y, 160, kWorldH - r * 0.5);
    for (final t in things) {
      if (t.eaten) continue;
      if (t.size < r * 0.95 && dist(t.x, t.y, x, y) < r - t.size * 0.3) {
        t.eaten = true;
        t.eatenAt = ticks;
        eaten++;
        r += t.size * 0.035;
        score += (t.size / 4).round() + (t.kind == 3 ? 20 : 0);
        lastEvent = 1;
        if (goalN > 0 && eaten >= goalN) {
          win();
          return;
        }
      }
    }
    r = math.min(r, 170);
    if (rival) {
      // Rakip: en yakın küçük nesneye gider, oyuncudan büyükse kovalar.
      Thing? tgt;
      var bd = 1e9;
      for (final t in things) {
        if (t.eaten || t.size >= rr * 0.95) continue;
        final d = dist(t.x, t.y, rx, ry);
        if (d < bd) {
          bd = d;
          tgt = t;
        }
      }
      var gx = tgt?.x ?? 500.0, gy = tgt?.y ?? 800.0;
      if (rr > r * 1.1 && dist(rx, ry, x, y) < 400) {
        gx = x;
        gy = y;
      } else if (r > rr * 1.1 && dist(rx, ry, x, y) < 300) {
        gx = rx + (rx - x);
        gy = ry + (ry - y);
      }
      final d = math.max(1.0, dist(rx, ry, gx, gy));
      final sp = 3.5 + level.d * 0.25;
      rvx = (gx - rx) / d * sp;
      rvy = (gy - ry) / d * sp;
      rx = clampD(rx + rvx, 40, 960);
      ry = clampD(ry + rvy, 180, 1560);
      for (final t in things) {
        if (!t.eaten && t.size < rr * 0.95 && dist(t.x, t.y, rx, ry) < rr - t.size * 0.3) {
          t.eaten = true;
          t.eatenAt = ticks;
          rr = math.min(rr + t.size * 0.03, 160);
        }
      }
      final dd = dist(x, y, rx, ry);
      if (dd < math.max(r, rr) * 0.8) {
        if (rr > r * 1.1) {
          lastEvent = 3;
          hit();
          if (over) return;
          x = 500;
          y = 1400;
          rx = 500;
          ry = 300;
        } else if (r > rr * 1.1) {
          rivalsEaten++;
          score += 200;
          lastEvent = 2;
          rr = 50;
          rx = x < 500 ? 900 : 100;
          ry = y < 800 ? 1500 : 250;
        }
      }
    }
    things.removeWhere((t) => t.eaten && ticks - t.eatenAt > 20);
    if (things.where((t) => !t.eaten).length < 30) _fill(25);
  }

  @override
  double get progress => goalN == 0 ? 0 : eaten / goalN;
  @override
  String get goalText => goalN == 0 ? '$eaten' : '$eaten/$goalN';
  @override
  Map<String, int> get stats => {'objects_swallowed': eaten, 'rivals_swallowed': rivalsEaten, 'hole_size': r.round()};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput holeBot(ArcadeSim sim) {
  final s = sim as HoleSim;
  // Tehlike: büyük rakipten kaç.
  if (s.rival && s.rr > s.r * 1.05 && dist(s.x, s.y, s.rx, s.ry) < s.rr + 260) {
    final a = math.atan2(s.y - s.ry, s.x - s.rx);
    var tx = s.x + math.cos(a) * 300, ty = s.y + math.sin(a) * 300;
    if (tx < 80 || tx > 920) tx = 500;
    if (ty < 220 || ty > 1500) ty = 800;
    return holdAt(tx, ty);
  }
  Thing? best;
  var bd = 1e9;
  for (final t in s.things) {
    if (t.eaten || t.size >= s.r * 0.95) continue;
    var d = dist(t.x, t.y, s.x, s.y) - t.size * 2;
    if (s.rival && s.rr > s.r && dist(t.x, t.y, s.rx, s.ry) < s.rr + 200) d += 2000;
    if (d < bd) {
      bd = d;
      best = t;
    }
  }
  if (best == null) return holdAt(500, 800);
  return holdAt(best.x, best.y);
}

const _thingCols = [Color(0xFFE76F51), Color(0xFF2A9D8F), Color(0xFFE9C46A), Color(0xFF264653), Color(0xFF8AB17D), Color(0xFFB5838D)];

void paintHole(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as HoleSim;
  paintSky(c, const Color(0xFFB7E4C7), const Color(0xFF95D5B2));
  paintGrid(c, const Rect.fromLTWH(0, 0, kWorldW, kWorldH), 100, const Color(0x14000000));
  void hole(double hx, double hy, double hr, Color rim) {
    c.drawCircle(Offset(hx, hy), hr + 8, Paint()..color = rim);
    c.drawCircle(Offset(hx, hy), hr, Paint()..shader = RadialGradient(colors: [Colors.black, const Color(0xFF1B263B)]).createShader(Rect.fromCircle(center: Offset(hx, hy), radius: hr)));
  }

  hole(s.x, s.y, s.r, s.shield > 0 && (s.ticks ~/ 5).isOdd ? Colors.white : p.piece(0));
  if (s.rival) hole(s.rx, s.ry, s.rr, const Color(0xFFE63946));
  for (final th in s.things) {
    var size = th.size;
    var o = Offset(th.x, th.y);
    if (th.eaten) {
      final k = clampD((s.ticks - th.eatenAt) / 20, 0, 1);
      size *= 1 - k;
      o = Offset.lerp(o, Offset(s.x, s.y), k * 0.6)!;
      if (size < 2) continue;
    }
    final col = _thingCols[th.color];
    switch (th.kind) {
      case 0:
        paintBox(c, Rect.fromCenter(center: o, width: size, height: size), col, radius: size * 0.15);
      case 1:
        paintBall(c, o, size / 2, col);
      case 2:
        c.drawCircle(o + Offset(0, size * 0.3), size * 0.12, Paint()..color = const Color(0xFF6F4518));
        paintBall(c, o - Offset(0, size * 0.1), size * 0.45, const Color(0xFF2D6A4F));
      default:
        paintBox(c, Rect.fromCenter(center: o, width: size, height: size * 0.7), col, radius: size * 0.2);
        paintText(c, '★', o, size * 0.5, const Color(0xFFFFC300));
    }
  }
  paintText(c, '${s.r.round()}', Offset(s.x, s.y), math.max(28.0, s.r * 0.4), Colors.white54);
}

Sfx? holeSound(ArcadeSim sim) => switch ((sim as HoleSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.combo,
      3 => Sfx.lose,
      _ => null,
    };

KitRules holeRules(String id) => KitRules(
      id,
      optionalMechanics: const ['rival'],
      gameStats: const [
        GameStat('objects_swallowed', 'Yutulan nesne', 'Objects swallowed', scale: 500),
        GameStat('rivals_swallowed', 'Yutulan rakip', 'Rivals swallowed', scale: 20),
        GameStat('hole_size', 'Delik boyu', 'Hole size', scale: 1),
      ],
      missionTemplates: const [
        MissionTemplate('objects_swallowed', 'objects_swallowed', [60, 120, 250]),
        MissionTemplate('rivals_swallowed', 'rivals_swallowed', [1, 2, 4]),
      ],
      make: HoleSim.new,
      botFn: holeBot,
    );
