import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Yolcu yönlendirme: küçük yolcular kapıdan çıkıp yürür ve kat kat aşağı
/// iner. Uçuruma dokun = köprü kur (birkaç saniye sürer), duvara dokun =
/// kaz. Araçlar sınırlı. Yeterli yolcu çıkışa ulaşınca bölüm geçilir;
/// yetişemezse can gider ve bölüm baştan başlar.
const double kFloorH = 270, kFloor0 = 330, kGapW = 90, kWallW = 40, kBuild = 70;

class Obstacle {
  final int floor;
  final double x;
  final bool gap; // false = duvar
  int fixAt = -1; // onarım başlangıcı
  Obstacle(this.floor, this.x, this.gap);
  bool fixed(int now) => fixAt >= 0 && now - fixAt >= kBuild;
}

class Walker {
  double x, y;
  int floor, dir;
  bool done = false, dead = false, fallingDown = false;
  double fallVy = 0, fallStart = 0;
  Walker(this.x, this.y, this.floor, this.dir);
}

class LemSim extends ArcadeSim {
  final ALevel level;
  final List<Obstacle> obs = [];
  final List<Walker> ws = [];
  late int floors, total, need, bridges, digs;
  int spawned = 0, saved = 0, lost = 0, levels = 0, spawnIn = 60, lastEvent = 0, doneAt = -1, savedTotal = 0;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;

  LemSim(this.level) : super(level.meta) {
    _newLevel();
  }

  double floorY(int f) => kFloor0 + f * kFloorH;
  int dirOf(int f) => f.isEven ? 1 : -1;

  void _newLevel() {
    floors = 3 + math.min(level.d ~/ 3, 2);
    obs.clear();
    for (var f = 0; f < floors; f++) {
      final n = 1 + rng.nextInt(1 + math.min(level.d ~/ 3, 2));
      final xs = <double>[];
      for (var k = 0; k < n; k++) {
        final x = 220 + rng.nextDouble() * 560;
        if (xs.every((o) => (o - x).abs() > 170)) xs.add(x);
      }
      for (final x in xs) {
        obs.add(Obstacle(f, x, rng.chance(0.55)));
      }
    }
    bridges = obs.where((o) => o.gap).length;
    digs = obs.where((o) => !o.gap).length;
    total = 10 + level.d;
    need = (total * (0.5 + level.d * 0.03)).ceil();
    _restart();
  }

  void _restart() {
    ws.clear();
    for (final o in obs) {
      o.fixAt = -1;
    }
    spawned = saved = lost = 0;
    spawnIn = 60;
    bridges = obs.where((o) => o.gap).length;
    digs = obs.where((o) => !o.gap).length;
  }

  double get exitX => dirOf(floors - 1) > 0 ? 920 : 80;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 60) {
        doneAt = -1;
        _newLevel();
      }
      return;
    }
    if (input.tap && input.hasPointer) {
      for (final o in obs) {
        if (o.fixAt >= 0) continue;
        final y = floorY(o.floor);
        if ((input.x - o.x).abs() < 70 && input.y > y - 140 && input.y < y + 60) {
          if (o.gap && bridges > 0) {
            bridges--;
            o.fixAt = ticks;
            lastEvent = 1;
          } else if (!o.gap && digs > 0) {
            digs--;
            o.fixAt = ticks;
            lastEvent = 1;
          }
          break;
        }
      }
    }
    if (spawned < total && --spawnIn <= 0) {
      ws.add(Walker(80, floorY(0), 0, 1));
      spawned++;
      spawnIn = math.max(30, 60 - level.d * 2);
    }
    final speed = 1.3 + level.d * 0.08;
    for (final w in ws) {
      if (w.done || w.dead) continue;
      if (w.fallingDown) {
        w.fallVy += 0.5;
        w.y += w.fallVy;
        final target = floorY(w.floor);
        if (w.y >= target) {
          w.y = target;
          w.fallingDown = false;
          w.fallVy = 0;
          if (w.y - w.fallStart > kFloorH * 1.5) {
            w.dead = true;
            lost++;
          }
        }
        continue;
      }
      w.x += w.dir * speed;
      final y = floorY(w.floor);
      for (final o in obs) {
        if (o.floor != w.floor || o.fixed(ticks)) continue;
        if (o.gap && (w.x - o.x).abs() < kGapW / 2 - 6) {
          // Uçuruma düştü
          w.dead = true;
          lost++;
          lastEvent = 3;
        } else if (!o.gap && (w.x - o.x).abs() < kWallW / 2 + 10 && (w.x - o.x).sign == -w.dir.sign) {
          w.dir = -w.dir;
          w.x += w.dir * 4;
        }
      }
      if (w.dead) continue;
      // Kat sonu: aşağıdaki kata in / çıkış
      final last = w.floor == floors - 1;
      if (last && (w.x - exitX).abs() < 20) {
        w.done = true;
        saved++;
        savedTotal++;
        score += 20;
        lastEvent = 2;
        continue;
      }
      if (!last && ((dirOf(w.floor) > 0 && w.x > 930) || (dirOf(w.floor) < 0 && w.x < 70))) {
        w.floor++;
        w.fallingDown = true;
        w.fallStart = y;
        w.dir = dirOf(w.floor);
      }
      // ekran kenarında dön
      if (w.x < 40 || w.x > 960) {
        w.dir = -w.dir;
        w.x = clampD(w.x, 40, 960);
      }
    }
    if (saved >= need && ws.every((w) => w.done || w.dead) && spawned == total) {
      levels++;
      score += 100 + (saved - need) * 20;
      lastEvent = 5;
      doneAt = ticks;
      if (goalN > 0 && levels >= goalN) win();
      return;
    }
    if (total - lost < need) {
      lastEvent = 3;
      hit();
      if (!over) _restart();
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : levels / goalN;
  @override
  String get goalText => '$saved/$need';
  @override
  Map<String, int> get stats => {'walkers_saved': savedTotal, 'levels_cleared': levels};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: yolcuların önündeki en yakın engeli onarır (sırayla).
ArcadeInput lemBot(ArcadeSim sim) {
  final s = sim as LemSim;
  if (s.doneAt >= 0 || s.ticks % 4 != 0) return ArcadeInput.idle;
  Obstacle? best;
  for (final o in s.obs) {
    if (o.fixAt >= 0) continue;
    if (best == null || o.floor < best.floor) best = o;
  }
  if (best == null) return ArcadeInput.idle;
  return tapAt(best.x, s.floorY(best.floor) - 40);
}

void paintLem(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as LemSim;
  paintSky(c, const Color(0xFF1D3557), const Color(0xFF457B9D));
  for (var f = 0; f < s.floors; f++) {
    final y = s.floorY(f);
    // zemin parçaları (uçurumlar hariç)
    final cuts = <(double, double)>[];
    for (final o in s.obs.where((o) => o.floor == f && o.gap)) {
      cuts.add((o.x - kGapW / 2, o.x + kGapW / 2));
    }
    final end = s.dirOf(f) > 0 ? (f == s.floors - 1 ? 1000.0 : 940.0) : 1000.0;
    final start = s.dirOf(f) < 0 ? (f == s.floors - 1 ? 0.0 : 60.0) : 0.0;
    var x0 = start;
    cuts.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (a, b) in [...cuts, (end, end)]) {
      if (a > x0) paintBox(c, Rect.fromLTRB(x0, y, a, y + 40), const Color(0xFF8D6E63), radius: 6, shade: false);
      x0 = b;
    }
    c.drawRect(Rect.fromLTWH(start, y, end - start, 8), Paint()..color = const Color(0x5590BE6D));
  }
  for (final o in s.obs) {
    final y = s.floorY(o.floor);
    final prog = o.fixAt < 0 ? 0.0 : clampD((s.ticks - o.fixAt) / kBuild, 0, 1);
    if (o.gap) {
      if (prog > 0) {
        c.drawRect(Rect.fromLTWH(o.x - kGapW / 2, y, kGapW * prog, 16), Paint()..color = const Color(0xFFFFB703));
      } else {
        paintText(c, '⚠', Offset(o.x, y - 70), 44, const Color(0xFFFFB703));
      }
    } else {
      final h = 150 * (1 - prog);
      if (h > 2) paintBox(c, Rect.fromLTWH(o.x - kWallW / 2, y - h, kWallW, h), const Color(0xFF6C757D), radius: 4, shade: false);
    }
  }
  // giriş ve çıkış
  paintBox(c, Rect.fromLTWH(40, s.floorY(0) - 110, 80, 110), const Color(0xFF6D597A), radius: 30);
  final ey = s.floorY(s.floors - 1);
  paintBox(c, Rect.fromCenter(center: Offset(s.exitX, ey - 55), width: 90, height: 110), const Color(0xFF2A9D8F), radius: 30);
  paintText(c, '⇲', Offset(s.exitX, ey - 55), 50, Colors.white);
  for (final w in s.ws) {
    if (w.done || w.dead) continue;
    final o = Offset(w.x, w.y - 22);
    c.drawCircle(o + const Offset(0, -18), 11, Paint()..color = const Color(0xFFFFD6A5));
    paintBox(c, Rect.fromCenter(center: o, width: 20, height: 28), p.piece(1), radius: 6, shade: false);
    final step = (s.ticks ~/ 8).isEven ? 4.0 : -4.0;
    c.drawLine(o + Offset(-4, 14), o + Offset(-4 + step, 24), Paint()..strokeWidth = 4);
    c.drawLine(o + Offset(4, 14), o + Offset(4 - step, 24), Paint()..strokeWidth = 4);
  }
  paintText(c, '▭ ${s.bridges}   ⛏ ${s.digs}   ✓ ${s.saved}/${s.need}', const Offset(500, 120), 48, Colors.white);
}

Sfx? lemSound(ArcadeSim sim) => switch ((sim as LemSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.coin,
      3 => Sfx.error,
      5 => Sfx.win,
      _ => null,
    };

KitRules lemRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('walkers_saved', 'Kurtarılan yolcu', 'Walkers saved', scale: 300),
        GameStat('levels_cleared', 'Geçilen bölüm', 'Levels cleared', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('walkers_saved', 'walkers_saved', [30, 60, 120]),
      ],
      make: LemSim.new,
      botFn: lemBot,
    );
