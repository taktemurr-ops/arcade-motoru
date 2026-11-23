import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Tank savaşı: tankını parmağınla sürükle; namlu görüş hattındaki en
/// yakın düşmana kendiliğinden döner ve ateş eder. Duvarların arkasına
/// saklan, mermilerden kaç. Tüm düşman tanklarını yok et.
const int kGX = 10, kGY = 14;
const double kCell = 100, kTop = 150, kTankR = 30;

class Tank {
  double x, y, angle = -math.pi / 2, turret = -math.pi / 2;
  int hp, cool = 0, wanderT = 0;
  double tx, ty;
  final bool enemy;
  Tank(this.x, this.y, this.hp, this.enemy)
      : tx = x,
        ty = y;
}

class Shell {
  double x, y;
  final double vx, vy;
  final bool mine;
  int bounces = 0;
  Shell(this.x, this.y, this.vx, this.vy, this.mine);
}

class TankSim extends ArcadeSim {
  final ALevel level;
  late List<List<bool>> wall;
  late Tank me;
  final List<Tank> foes = [];
  final List<Shell> shells = [];
  final List<Fx> fx = [];
  int destroyed = 0, toSpawn = 0, spawnIn = 0, fired = 0, lastEvent = 0;
  late final int goalN = level.target(6, 2);

  TankSim(this.level) : super(level.meta) {
    wall = List.generate(kGX, (_) => List<bool>.filled(kGY, false));
    final n = 10 + level.d * 2;
    for (var i = 0; i < n; i++) {
      final cx = rng.nextInt(kGX), cy = 2 + rng.nextInt(kGY - 4);
      if (cy >= kGY - 3) continue;
      wall[cx][cy] = true;
      if (rng.chance(0.5) && cx + 1 < kGX) wall[cx + 1][cy] = true;
    }
    me = Tank(500, kTop + (kGY - 1.5) * kCell, 1, false);
    toSpawn = goalN == 0 ? 1 << 30 : goalN;
  }

  Offset cellC(int cx, int cy) => Offset((cx + 0.5) * kCell, kTop + (cy + 0.5) * kCell);
  bool blocked(double x, double y) {
    if (x < 0 || x >= kGX * kCell || y < kTop || y >= kTop + kGY * kCell) return true;
    return wall[(x / kCell).floor()][((y - kTop) / kCell).floor()];
  }

  bool los(double ax, double ay, double bx, double by) {
    final d = dist(ax, ay, bx, by);
    final n = (d / 20).ceil();
    for (var i = 1; i < n; i++) {
      if (blocked(ax + (bx - ax) * i / n, ay + (by - ay) * i / n)) return false;
    }
    return true;
  }

  void _moveTank(Tank t, double gx, double gy, double speed) {
    final d = dist(t.x, t.y, gx, gy);
    if (d < 4) return;
    final vx = (gx - t.x) / d * math.min(speed, d), vy = (gy - t.y) / d * math.min(speed, d);
    t.angle = math.atan2(vy, vx);
    if (!_hitsWall(t.x + vx, t.y)) t.x += vx;
    if (!_hitsWall(t.x, t.y + vy)) t.y += vy;
  }

  bool _hitsWall(double x, double y) {
    for (final (ox, oy) in const [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) {
      if (blocked(x + ox * kTankR, y + oy * kTankR)) return true;
    }
    return false;
  }

  void _fire(Tank t, double angle, double speed) {
    shells.add(Shell(t.x + math.cos(angle) * 44, t.y + math.sin(angle) * 44, math.cos(angle) * speed, math.sin(angle) * speed, !t.enemy));
    if (!t.enemy) fired++;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      _moveTank(me, input.x, input.y - 60, 6);
    } else if (input.dirX != 0 || input.dirY != 0) {
      _moveTank(me, me.x + input.dirX * 50, me.y + input.dirY * 50, 6);
    }
    // otomatik nişan ve ateş
    Tank? aim;
    var ad = 1e9;
    for (final f in foes) {
      final d = dist(me.x, me.y, f.x, f.y);
      if (d < ad && los(me.x, me.y, f.x, f.y)) {
        ad = d;
        aim = f;
      }
    }
    if (aim != null) {
      // Öndelikli nişan: düşman hedefine doğru gidiyorsa
      final moving = dist(aim.x, aim.y, aim.tx, aim.ty) > 4;
      final sp = moving ? 2 + level.d * 0.15 : 0.0;
      final tt = ad / 16;
      final want = math.atan2(aim.y + math.sin(aim.angle) * sp * tt - me.y, aim.x + math.cos(aim.angle) * sp * tt - me.x);
      me.turret = want;
      if (me.cool <= 0) {
        _fire(me, want, 16);
        me.cool = 34;
        lastEvent = 1;
      }
    }
    if (me.cool > 0) me.cool--;
    // düşman doğumu
    final alive = foes.length;
    final maxAlive = 2 + level.d ~/ 3;
    if (toSpawn > 0 && alive < maxAlive && --spawnIn <= 0) {
      final cands = [for (var cx = 0; cx < kGX; cx++) if (!wall[cx][0]) cx];
      final cx = rng.pick(cands);
      final c = cellC(cx, 0);
      foes.add(Tank(c.dx, c.dy, 1 + (level.d >= 6 && rng.chance(0.3) ? 1 : 0), true));
      toSpawn--;
      spawnIn = math.max(60, 180 - level.d * 10);
    }
    for (final f in foes) {
      if (--f.wanderT <= 0) {
        f.wanderT = 90 + rng.nextInt(90);
        // oyuncuya biraz yaklaşan rastgele bir hücre
        for (var k = 0; k < 10; k++) {
          final cx = rng.nextInt(kGX), cy = rng.nextInt(kGY ~/ 2 + 2);
          if (!wall[cx][cy]) {
            final c = cellC(cx, cy);
            f.tx = c.dx;
            f.ty = c.dy;
            break;
          }
        }
      }
      _moveTank(f, f.tx, f.ty, 2 + level.d * 0.15);
      if (f.cool > 0) f.cool--;
      if (f.cool == 0 && los(f.x, f.y, me.x, me.y) && dist(f.x, f.y, me.x, me.y) < 900) {
        final a = math.atan2(me.y - f.y, me.x - f.x) + (rng.nextDouble() - 0.5) * (0.4 - level.d * 0.02);
        f.turret = a;
        _fire(f, a, 8 + level.d * 0.4);
        f.cool = math.max(70, 160 - level.d * 8) + rng.nextInt(40);
      } else if (f.cool == 0) {
        f.cool = 10;
      }
    }
    for (final s in shells) {
      s.x += s.vx;
      s.y += s.vy;
    }
    shells.removeWhere((s) {
      if (blocked(s.x, s.y)) {
        fx.add(Fx(s.x, s.y, ticks, 4));
        return true;
      }
      if (s.mine) {
        for (final f in foes) {
          if (dist(s.x, s.y, f.x, f.y) < kTankR + 8) {
            f.hp--;
            fx.add(Fx(s.x, s.y, ticks, 1));
            return true;
          }
        }
      } else if (dist(s.x, s.y, me.x, me.y) < kTankR + 6) {
        lastEvent = 3;
        hit();
        return true;
      }
      return false;
    });
    for (final f in [...foes]) {
      if (f.hp <= 0) {
        foes.remove(f);
        destroyed++;
        score += 100;
        lastEvent = 2;
        if (goalN > 0 && destroyed >= goalN) {
          win();
          return;
        }
      }
    }
    pruneFx(fx, ticks);
  }

  @override
  void onLifeLost() {
    shells.removeWhere((s) => !s.mine);
  }

  @override
  double get progress => goalN == 0 ? 0 : destroyed / goalN;
  @override
  String get goalText => goalN == 0 ? '$destroyed' : '$destroyed/$goalN';
  @override
  Map<String, int> get stats => {'tanks_destroyed': destroyed, 'shells_fired': fired};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: gelen mermilerden yana kaçar; yoksa hedef düşmanı görebileceği
/// bir hücreye (BFS) gider.
ArcadeInput tankBot(ArcadeSim sim) {
  final s = sim as TankSim;
  final me = s.me;
  // kaçış
  for (final sh in s.shells) {
    if (sh.mine) continue;
    for (var k = 1; k <= 30; k++) {
      if (dist(sh.x + sh.vx * k, sh.y + sh.vy * k, me.x, me.y) < kTankR + 26) {
        final sp = math.sqrt(sh.vx * sh.vx + sh.vy * sh.vy);
        var px = -sh.vy / sp, py = sh.vx / sp;
        // engelsiz yanı seç
        if (s.blocked(me.x + px * 70, me.y + py * 70)) {
          px = -px;
          py = -py;
        }
        return holdAt(me.x + px * 120, me.y + py * 120 + 60);
      }
    }
  }
  if (s.foes.isEmpty) return ArcadeInput.idle;
  Tank? t;
  for (final f in s.foes) {
    if (t == null || dist(me.x, me.y, f.x, f.y) < dist(me.x, me.y, t.x, t.y)) t = f;
  }
  final tg = t!;
  if (s.los(me.x, me.y, tg.x, tg.y) && dist(me.x, me.y, tg.x, tg.y) < 700) return ArcadeInput.idle;
  // BFS: hedefi gören en yakın hücre
  final sx = (me.x / kCell).floor(), sy = ((me.y - kTop) / kCell).floor();
  final seen = <int>{sx * 100 + sy};
  final q = <(int, int, int, int)>[(sx, sy, -1, -1)];
  var i = 0;
  while (i < q.length) {
    final (cx, cy, fx0, fy0) = q[i++];
    final c = s.cellC(cx, cy);
    if (fx0 >= 0 && s.los(c.dx, c.dy, tg.x, tg.y) && dist(c.dx, c.dy, tg.x, tg.y) < 650) {
      final first = s.cellC(fx0, fy0);
      return holdAt(first.dx, first.dy + 60);
    }
    for (final (dx, dy) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
      final nx = cx + dx, ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= kGX || ny >= kGY || s.wall[nx][ny] || !seen.add(nx * 100 + ny)) continue;
      q.add((nx, ny, fx0 < 0 ? nx : fx0, fy0 < 0 ? ny : fy0));
    }
  }
  return ArcadeInput.idle;
}

void paintTank(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as TankSim;
  paintSky(c, const Color(0xFFCCD5AE), const Color(0xFFE9EDC9));
  const field = Rect.fromLTWH(0, kTop, kGX * kCell, kGY * kCell);
  c.drawRect(field, Paint()..color = const Color(0xFFD4A373).withValues(alpha: 0.35));
  paintGrid(c, field, kCell, const Color(0x14000000));
  for (var x = 0; x < kGX; x++) {
    for (var y = 0; y < kGY; y++) {
      if (!s.wall[x][y]) continue;
      final r = Rect.fromLTWH(x * kCell, kTop + y * kCell, kCell, kCell);
      paintBox(c, r.deflate(3), const Color(0xFF8D6E63), radius: 8);
      for (var k = 0; k < 3; k++) {
        c.drawLine(Offset(r.left + 6, r.top + 25.0 + k * 25), Offset(r.right - 6, r.top + 25.0 + k * 25), Paint()
          ..color = Colors.black12
          ..strokeWidth = 3);
      }
    }
  }
  void tank(Tank tk, Color col) {
    c.save();
    c.translate(tk.x, tk.y);
    c.rotate(tk.angle);
    paintBox(c, const Rect.fromLTWH(-36, -32, 72, 14), const Color(0xFF343A40), radius: 6, shade: false);
    paintBox(c, const Rect.fromLTWH(-36, 18, 72, 14), const Color(0xFF343A40), radius: 6, shade: false);
    paintBox(c, const Rect.fromLTWH(-30, -22, 60, 44), col, radius: 10);
    c.restore();
    c.save();
    c.translate(tk.x, tk.y);
    c.rotate(tk.turret);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, -6, 48, 12), const Radius.circular(5)), Paint()..color = Color.lerp(col, Colors.black, 0.35)!);
    c.drawCircle(Offset.zero, 16, Paint()..color = Color.lerp(col, Colors.black, 0.2)!);
    c.restore();
  }

  for (final f in s.foes) {
    tank(f, f.hp > 1 ? const Color(0xFF9D0208) : const Color(0xFFE85D04));
  }
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  tank(s.me, blink ? Colors.white54 : p.piece(0));
  for (final sh in s.shells) {
    paintBall(c, Offset(sh.x, sh.y), 9, sh.mine ? const Color(0xFFFFE066) : const Color(0xFFFF006E));
  }
  paintFxList(c, s.fx, s.ticks, p);
}

Sfx? tankSound(ArcadeSim sim) => switch ((sim as TankSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.clear,
      3 => Sfx.lose,
      _ => null,
    };

KitRules tankRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('tanks_destroyed', 'Yok edilen tank', 'Tanks destroyed', scale: 200),
        GameStat('shells_fired', 'Atış', 'Shells fired', scale: 1000),
      ],
      missionTemplates: const [
        MissionTemplate('tanks_destroyed', 'tanks_destroyed', [10, 20, 40]),
      ],
      make: TankSim.new,
      botFn: tankBot,
    );
