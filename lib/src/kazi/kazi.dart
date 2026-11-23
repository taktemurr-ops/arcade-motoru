import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kazı kazı: toprağın içinde kaydırarak kaz. Dokun = baktığın yöne hava
/// pompası fırlat (tünel boyunca 3 hücre). Yaratığı dört pompada patlat.
/// Yaratıklar tünellerde dolaşır, ara sıra topraktan süzülür. Değerlerse
/// can gider. Hepsi bitince yeni katman.
const int kW = 12, kH = 17;
const double kC = 1000 / kW, kTop = 160;

class Critter {
  int x, y, dir;
  double fx, fy;
  int inflate = 0, lastPump = -999;
  bool ghost = false, dead = false;
  Critter(this.x, this.y, this.dir)
      : fx = x.toDouble(),
        fy = y.toDouble();
}

const _dx = [0, 1, 0, -1], _dy = [-1, 0, 1, 0];

class DigSim extends ArcadeSim {
  final ALevel level;
  late List<List<bool>> dug;
  int px = kW ~/ 2, py = 0, face = 2, moveT = 0, wantDir = -1;
  double fx = kW / 2, fy = 0;
  final List<Critter> critters = [];
  int layers = 0, popped = 0, cellsDug = 0, lastEvent = 0, pumpAt = -100, pumpLen = 0, doneAt = -1;
  late final int goalN = level.target(2, 0) == 0 ? 0 : 2 + level.d ~/ 4;

  DigSim(this.level) : super(level.meta) {
    _newLayer();
  }

  void _newLayer() {
    dug = List.generate(kW, (_) => List<bool>.filled(kH, false));
    for (var y = 0; y <= 2; y++) {
      dug[kW ~/ 2][y] = true;
    }
    critters.clear();
    final n = 2 + math.min<int>(level.d ~/ 3, 3);
    for (var i = 0; i < n; i++) {
      // her yaratık kısa bir yatay/dikey tünelde
      final horiz = rng.chance(0.5);
      final cx = 1 + rng.nextInt(kW - 4), cy = 5 + rng.nextInt(kH - 8);
      for (var k = 0; k < 4; k++) {
        dug[horiz ? cx + k : cx][horiz ? cy : cy + k] = true;
      }
      critters.add(Critter(cx + (horiz ? 1 : 0), cy + (horiz ? 0 : 1), horiz ? 1 : 2));
    }
    px = kW ~/ 2;
    py = 0;
    fx = px.toDouble();
    fy = 0;
    face = 2;
  }

  bool inGrid(int x, int y) => x >= 0 && y >= 0 && x < kW && y < kH;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 50) {
        doneAt = -1;
        _newLayer();
      }
      return;
    }
    var sw = input.swipe;
    if (sw < 0 && (input.dirX != 0 || input.dirY != 0)) {
      sw = input.dirY < 0 ? 0 : (input.dirX > 0 ? 1 : (input.dirY > 0 ? 2 : 3));
    }
    if (sw >= 0) wantDir = sw;
    if (input.tap && input.swipe < 0 && ticks - pumpAt > 8) {
      pumpAt = ticks;
      pumpLen = 0;
      lastEvent = 1;
      if (input.hasPointer) {
        final ddx = input.x - (px + 0.5) * kC, ddy = input.y - (kTop + (py + 0.5) * kC);
        face = ddx.abs() > ddy.abs() ? (ddx > 0 ? 1 : 3) : (ddy > 0 ? 2 : 0);
      }
      for (var k = 1; k <= 3; k++) {
        final x = px + _dx[face] * k, y = py + _dy[face] * k;
        if (!inGrid(x, y) || !dug[x][y]) break;
        pumpLen = k;
        final hitC = critters.where((c) => !c.dead && c.x == x && c.y == y);
        if (hitC.isNotEmpty) {
          final c = hitC.first;
          c.inflate++;
          c.lastPump = ticks;
          lastEvent = 2;
          if (c.inflate >= 4) {
            c.dead = true;
            popped++;
            score += 50 + py * 5;
            lastEvent = 4;
          }
          break;
        }
      }
    }
    if (moveT == 0 && wantDir >= 0) {
      face = wantDir;
      final nx = px + _dx[wantDir], ny = py + _dy[wantDir];
      if (inGrid(nx, ny)) {
        final wasDug = dug[nx][ny];
        if (!wasDug) {
          dug[nx][ny] = true;
          cellsDug++;
          score += 1;
        }
        px = nx;
        py = ny;
        moveT = wasDug ? 9 : 12;
      }
      wantDir = -1;
    }
    if (moveT > 0) moveT--;
    fx = moveToward(fx, px.toDouble(), 1 / 8);
    fy = moveToward(fy, py.toDouble(), 1 / 8);
    final step = math.max<int>(18, 30 - level.d);
    for (final c in critters) {
      if (c.dead) continue;
      if (c.inflate > 0 && ticks - c.lastPump > 70) {
        c.inflate--;
        c.lastPump = ticks - 40;
      }
      if (c.inflate > 0) continue;
      if (ticks % step == 0) {
        if (!c.ghost && rng.chance(0.03 + level.d * 0.002)) c.ghost = true;
        if (c.ghost) {
          // oyuncuya doğru topraktan süzül
          if ((px - c.x).abs() > (py - c.y).abs()) {
            c.x += (px - c.x).sign;
          } else {
            c.y += (py - c.y).sign;
          }
          if (dug[c.x][c.y] && rng.chance(0.5)) c.ghost = false;
        } else {
          final opts = [for (var d = 0; d < 4; d++) if (inGrid(c.x + _dx[d], c.y + _dy[d]) && dug[c.x + _dx[d]][c.y + _dy[d]]) d];
          if (opts.isNotEmpty) {
            // tünelde oyuncuya yaklaşmayı tercih et
            opts.sort((a, b) => ((c.x + _dx[a] - px).abs() + (c.y + _dy[a] - py).abs()).compareTo((c.x + _dx[b] - px).abs() + (c.y + _dy[b] - py).abs()));
            c.dir = rng.chance(0.6) ? opts.first : rng.pick(opts);
            c.x += _dx[c.dir];
            c.y += _dy[c.dir];
          }
        }
      }
      c.fx = moveToward(c.fx, c.x.toDouble(), 1 / step * 1.3);
      c.fy = moveToward(c.fy, c.y.toDouble(), 1 / step * 1.3);
    }
    for (final c in critters) {
      if (!c.dead && c.inflate == 0 && c.x == px && c.y == py) {
        lastEvent = 3;
        hit();
        return;
      }
    }
    if (critters.every((c) => c.dead)) {
      layers++;
      score += 150;
      lastEvent = 5;
      doneAt = ticks;
      if (goalN > 0 && layers >= goalN) win();
    }
  }

  @override
  void onLifeLost() {
    px = kW ~/ 2;
    py = 0;
    fx = px.toDouble();
    fy = 0;
    for (final c in critters) {
      if (!c.dead && c.y < 4) {
        c.y = kH - 2;
        c.fy = c.y.toDouble();
        dug[c.x][c.y] = true;
      }
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : layers / goalN;
  @override
  String get goalText => goalN == 0 ? '$layers' : '$layers/$goalN';
  @override
  Map<String, int> get stats => {'layers_cleared': layers, 'critters_popped': popped, 'cells_dug': cellsDug};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: en yakın yaratıkla aynı satır/sütuna gelip 2-3 hücre mesafede
/// durur, ona dön ve pompala. Tünel yoksa kazarak hizalanır.
ArcadeInput digBot(ArcadeSim sim) {
  final s = sim as DigSim;
  if (s.doneAt >= 0 || s.moveT > 0) return ArcadeInput.idle;
  Critter? t;
  for (final c in s.critters) {
    if (c.dead) continue;
    if (t == null || (c.x - s.px).abs() + (c.y - s.py).abs() < (t.x - s.px).abs() + (t.y - s.py).abs()) t = c;
  }
  if (t == null) return ArcadeInput.idle;
  final dx = t.x - s.px, dy = t.y - s.py;
  final d = dx.abs() + dy.abs();
  // Çok yakın ve şişmemişse: geri çekil
  if (d <= 1 && t.inflate == 0) {
    final away = dx.abs() > dy.abs() ? (dx > 0 ? 3 : 1) : (dy > 0 ? 0 : 2);
    final nx = s.px + _dx[away], ny = s.py + _dy[away];
    if (s.inGrid(nx, ny)) return ArcadeInput(swipe: away);
  }
  // Aynı hizada mı ve arada tünel var mı?
  if ((dx == 0 || dy == 0) && d <= 3) {
    final dir = dx == 0 ? (dy < 0 ? 0 : 2) : (dx > 0 ? 1 : 3);
    var open = true;
    for (var k = 1; k < d; k++) {
      if (!s.dug[s.px + _dx[dir] * k][s.py + _dy[dir] * k]) open = false;
    }
    if (open && s.dug[t.x][t.y]) {
      // Yaratığa dokun: o yöne döner ve pompalar.
      return tapAt((t.x + 0.5) * kC, kTop + (t.y + 0.5) * kC);
    }
    if (d >= 2) {
      // aradaki toprağı kaz
      return ArcadeInput(swipe: dir);
    }
  }
  // Hizalan: önce yatay (aynı sütuna değil, 2 hücre uzakta aynı satıra)
  if (dy != 0 && dx.abs() >= 2) return ArcadeInput(swipe: dy < 0 ? 0 : 2);
  if (dy != 0) return ArcadeInput(swipe: dx >= 0 ? 3 : 1);
  return ArcadeInput(swipe: dx > 0 ? 1 : 3);
}

void paintDig(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as DigSim;
  paintSky(c, const Color(0xFF8ECAE6), const Color(0xFF8ECAE6));
  final soil = [const Color(0xFFDDA15E), const Color(0xFFBC6C25), const Color(0xFF9C4A1A), const Color(0xFF6F2E0E)];
  for (var x = 0; x < kW; x++) {
    for (var y = 0; y < kH; y++) {
      final r = Rect.fromLTWH(x * kC, kTop + y * kC, kC + 0.5, kC + 0.5);
      if (s.dug[x][y]) {
        c.drawRect(r, Paint()..color = const Color(0xFF1B1B1B));
      } else {
        c.drawRect(r, Paint()..color = soil[math.min(y * 4 ~/ kH, 3)]);
        c.drawCircle(r.center + Offset(((x * 7 + y * 3) % 5 - 2) * 8.0, ((x * 3 + y * 5) % 5 - 2) * 8.0), 5, Paint()..color = Colors.black12);
      }
    }
  }
  c.drawRect(const Rect.fromLTWH(0, kTop - 20, kWorldW, 20), Paint()..color = const Color(0xFF6A994E));
  if (s.ticks - s.pumpAt < 10 && s.pumpLen > 0) {
    final a = Offset((s.fx + 0.5) * kC, kTop + (s.fy + 0.5) * kC);
    final b = a + Offset(_dx[s.face] * s.pumpLen * kC, _dy[s.face] * s.pumpLen * kC);
    c.drawLine(a, b, Paint()
      ..color = Colors.white
      ..strokeWidth = 6);
  }
  for (final cr in s.critters) {
    if (cr.dead) continue;
    final o = Offset((cr.fx + 0.5) * kC, kTop + (cr.fy + 0.5) * kC);
    final r = kC * (0.34 + cr.inflate * 0.08);
    if (cr.ghost) {
      c.drawCircle(o, r, Paint()..color = Colors.white30);
      c.drawCircle(o + const Offset(-10, -4), 5, Paint()..color = Colors.white);
      c.drawCircle(o + const Offset(10, -4), 5, Paint()..color = Colors.white);
      continue;
    }
    paintBall(c, o, r, const Color(0xFFE63946));
    c.drawOval(Rect.fromCenter(center: o + const Offset(0, -6), width: r * 1.2, height: r * 0.5), Paint()..color = const Color(0xFFFFD60A));
    c.drawCircle(o + const Offset(-8, -6), 4, Paint()..color = Colors.black);
    c.drawCircle(o + const Offset(8, -6), 4, Paint()..color = Colors.black);
  }
  final po = Offset((s.fx + 0.5) * kC, kTop + (s.fy + 0.5) * kC);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, po, kC * 0.34, blink ? Colors.white54 : p.piece(0));
  c.drawArc(Rect.fromCircle(center: po + const Offset(0, -8), radius: kC * 0.3), math.pi, math.pi, true, Paint()..color = Colors.white);
}

Sfx? digSound(ArcadeSim sim) => switch ((sim as DigSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.lose,
      4 => Sfx.coin,
      5 => Sfx.win,
      _ => null,
    };

KitRules digRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('layers_cleared', 'Temizlenen katman', 'Layers cleared', scale: 50),
        GameStat('critters_popped', 'Patlatılan yaratık', 'Critters popped', scale: 200),
        GameStat('cells_dug', 'Kazılan hücre', 'Cells dug', scale: 2000),
      ],
      missionTemplates: const [
        MissionTemplate('critters_popped', 'critters_popped', [10, 20, 40]),
        MissionTemplate('cells_dug', 'cells_dug', [100, 200, 400]),
      ],
      make: DigSim.new,
      botFn: digBot,
    );
