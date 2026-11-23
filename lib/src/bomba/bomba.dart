import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Bomba labirenti: kaydırarak yürü, dokunarak bomba bırak. Bomba artı
/// biçiminde patlar; kırılabilir sandıkları ve canavarları yok eder.
/// Tüm canavarlar bitince kapı açılır; kapıya ulaş. Patlamaya ya da
/// canavara değmek can götürür.
const int kW = 13, kH = 17;
const double kC = 1000 / kW, kTop = 100;
const int kFuse = 120, kFlame = 30;

class Bomb {
  final int x, y, placed;
  Bomb(this.x, this.y, this.placed);
}

class Monster {
  int x, y, dir;
  double fx, fy;
  bool dead = false;
  Monster(this.x, this.y, this.dir)
      : fx = x.toDouble(),
        fy = y.toDouble();
}

const _dx = [0, 1, 0, -1], _dy = [-1, 0, 1, 0];

class BomberSim extends ArcadeSim {
  final ALevel level;
  late List<List<int>> g; // 0 boş, 1 sabit duvar, 2 sandık, 3 kapı (sandık altında olabilir)
  int px = 1, py = 1, moveDir = -1, moveT = 0;
  double fx = 1, fy = 1;
  final List<Bomb> bombs = [];
  final Map<int, int> flames = {}; // hücre → bitiş tiki
  final List<Monster> monsters = [];
  int doorX = 0, doorY = 0, range = 2, maxBombs = 1, levelsDone = 0, killed = 0, crates = 0, lastEvent = 0, doneAt = -1;
  late final int goalN = level.target(2, 0) == 0 ? 0 : 2 + level.d ~/ 3;

  BomberSim(this.level) : super(level.meta) {
    _newMap();
  }

  int key(int x, int y) => x * 100 + y;

  void _newMap() {
    g = List.generate(kW, (x) => List.generate(kH, (y) => (x == 0 || y == 0 || x == kW - 1 || y == kH - 1 || (x.isEven && y.isEven)) ? 1 : 0));
    final crateP = 0.35 + level.d * 0.03;
    for (var x = 1; x < kW - 1; x++) {
      for (var y = 1; y < kH - 1; y++) {
        if (g[x][y] == 0 && x + y > 3 && rng.chance(crateP)) g[x][y] = 2;
      }
    }
    // kapı bir sandığın altında
    final cand = [for (var x = 1; x < kW - 1; x++) for (var y = 1; y < kH - 1; y++) if (g[x][y] == 2 && x + y > 10) (x, y)];
    final (dx0, dy0) = cand.isEmpty ? (kW - 2, kH - 2) : rng.pick(cand);
    doorX = dx0;
    doorY = dy0;
    g[doorX][doorY] = 2;
    monsters.clear();
    final n = 2 + level.d ~/ 2;
    var tries = 0;
    while (monsters.length < n && tries++ < 500) {
      final x = 1 + rng.nextInt(kW - 2), y = 1 + rng.nextInt(kH - 2);
      if (g[x][y] == 0 && x + y > 8) monsters.add(Monster(x, y, rng.nextInt(4)));
    }
    px = py = 1;
    fx = fy = 1;
    bombs.clear();
    flames.clear();
    moveDir = -1;
  }

  bool walkable(int x, int y) {
    if (x < 0 || y < 0 || x >= kW || y >= kH) return false;
    if (g[x][y] == 1 || g[x][y] == 2) return false;
    if (bombs.any((b) => b.x == x && b.y == y)) return false;
    return true;
  }

  /// Bir bombanın etkileyeceği hücreler.
  List<(int, int)> blast(int bx, int by) {
    final out = [(bx, by)];
    for (var d = 0; d < 4; d++) {
      for (var k = 1; k <= range; k++) {
        final x = bx + _dx[d] * k, y = by + _dy[d] * k;
        if (g[x][y] == 1) break;
        out.add((x, y));
        if (g[x][y] == 2) break;
      }
    }
    return out;
  }

  bool get doorOpen => monsters.every((m) => m.dead) && g[doorX][doorY] != 2;

  void _explode(Bomb b) {
    bombs.remove(b);
    for (final (x, y) in blast(b.x, b.y)) {
      flames[key(x, y)] = ticks + kFlame;
      if (g[x][y] == 2) {
        g[x][y] = 0;
        crates++;
        score += 5;
        if (rng.chance(0.12)) {
          if (range < 5 && rng.chance(0.5)) {
            range++;
          } else if (maxBombs < 3) {
            maxBombs++;
          }
        }
      }
      for (final o in [...bombs]) {
        if (o.x == x && o.y == y) _explode(o);
      }
    }
    lastEvent = 2;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 50) {
        doneAt = -1;
        _newMap();
      }
      return;
    }
    var sw = input.swipe;
    if (sw < 0 && (input.dirX != 0 || input.dirY != 0)) {
      sw = input.dirY < 0 ? 0 : (input.dirX > 0 ? 1 : (input.dirY > 0 ? 2 : 3));
    }
    if (sw >= 0) moveDir = sw;
    if (input.tap && input.swipe < 0 && bombs.length < maxBombs && !bombs.any((b) => b.x == px && b.y == py)) {
      bombs.add(Bomb(px, py, ticks));
      lastEvent = 1;
    }
    // Hareket: hücreden hücreye 8 tik
    if (moveT == 0 && moveDir >= 0) {
      final nx = px + _dx[moveDir], ny = py + _dy[moveDir];
      final blocked = g[nx][ny] == 1 || g[nx][ny] == 2 || bombs.any((b) => b.x == nx && b.y == ny);
      if (!blocked) {
        px = nx;
        py = ny;
        moveT = 8;
      }
      moveDir = -1;
    }
    if (moveT > 0) moveT--;
    fx = moveToward(fx, px.toDouble(), 1 / 8);
    fy = moveToward(fy, py.toDouble(), 1 / 8);
    for (final b in [...bombs]) {
      if (bombs.contains(b) && ticks - b.placed >= kFuse) _explode(b);
    }
    flames.removeWhere((k, end) => end <= ticks);
    // Canavarlar
    final mStep = math.max(10, 22 - level.d);
    for (final m in monsters) {
      if (m.dead) continue;
      if (flames.containsKey(key(m.x, m.y))) {
        m.dead = true;
        killed++;
        score += 50;
        lastEvent = 4;
        continue;
      }
      if (ticks % mStep == 0) {
        final opts = [for (var d = 0; d < 4; d++) if (walkable(m.x + _dx[d], m.y + _dy[d])) d];
        if (opts.isNotEmpty) {
          if (!opts.contains(m.dir) || rng.chance(0.25)) m.dir = rng.pick(opts);
          m.x += _dx[m.dir];
          m.y += _dy[m.dir];
        }
      }
      m.fx = moveToward(m.fx, m.x.toDouble(), 1 / mStep * 1.2);
      m.fy = moveToward(m.fy, m.y.toDouble(), 1 / mStep * 1.2);
    }
    if (flames.containsKey(key(px, py)) || monsters.any((m) => !m.dead && m.x == px && m.y == py)) {
      lastEvent = 3;
      hit();
      return;
    }
    if (doorOpen && px == doorX && py == doorY) {
      levelsDone++;
      score += 200;
      lastEvent = 5;
      doneAt = ticks;
      if (goalN > 0 && levelsDone >= goalN) win();
    }
  }

  @override
  void onLifeLost() {
    // Güvenli köşeye dön; yakındaki canavarları uzaklaştır.
    px = py = 1;
    fx = fy = 1;
    for (final m in monsters) {
      if (!m.dead && m.x + m.y < 6) {
        m.x = kW - 2;
        m.y = kH - 2;
        m.fx = m.x.toDouble();
        m.fy = m.y.toDouble();
      }
    }
    bombs.clear();
    flames.clear();
  }

  @override
  double get progress => goalN == 0 ? 0 : levelsDone / goalN;
  @override
  String get goalText => goalN == 0 ? '$levelsDone' : '$levelsDone/$goalN';
  @override
  Map<String, int> get stats => {'mazes_cleared': levelsDone, 'monsters_defeated': killed, 'crates_broken': crates};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: tehlikedeyse en yakın güvenli hücreye kaçar; değilse hedefe
/// (canavar / sandık / kapı) BFS ile yaklaşır, uygun yerde bomba bırakır
/// ama yalnız kaçış yolu varsa.
ArcadeInput bomberBot(ArcadeSim sim) {
  final s = sim as BomberSim;
  if (s.doneAt >= 0 || s.moveT > 0) return ArcadeInput.idle;
  // Tehlikeli hücreler: alevler + patlayacak bombaların menzili
  final danger = <int>{...s.flames.keys};
  for (final b in s.bombs) {
    for (final (x, y) in s.blast(b.x, b.y)) {
      danger.add(s.key(x, y));
    }
  }
  bool passable(int x, int y) => s.g[x][y] != 1 && s.g[x][y] != 2;
  bool hasBomb(int x, int y) => s.bombs.any((b) => b.x == x && b.y == y);
  bool monsterNear(int x, int y) => s.monsters.any((m) => !m.dead && (m.x - x).abs() + (m.y - y).abs() <= 1);
  // BFS: ilk adım yönü
  int? bfs(bool Function(int, int) goal, Set<int> avoid, {int maxD = 200}) {
    final seen = <int>{s.key(s.px, s.py)};
    final q = <(int, int, int, int)>[(s.px, s.py, -1, 0)];
    var i = 0;
    while (i < q.length) {
      final (x, y, first, d) = q[i++];
      if (first >= 0 && goal(x, y)) return first;
      if (d >= maxD) continue;
      for (var dir = 0; dir < 4; dir++) {
        final nx = x + _dx[dir], ny = y + _dy[dir];
        if (!passable(nx, ny) || hasBomb(nx, ny) || avoid.contains(s.key(nx, ny)) || !seen.add(s.key(nx, ny))) continue;
        if (s.flames.containsKey(s.key(nx, ny))) continue;
        q.add((nx, ny, first < 0 ? dir : first, d + 1));
      }
    }
    return null;
  }

  final hereDanger = danger.contains(s.key(s.px, s.py));
  if (hereDanger) {
    final d = bfs((x, y) => !danger.contains(s.key(x, y)) && !monsterNear(x, y), {});
    return d == null ? ArcadeInput.idle : ArcadeInput(swipe: d);
  }
  // Kapı açıksa git
  if (s.doorOpen) {
    final d = bfs((x, y) => x == s.doorX && y == s.doorY, danger);
    return d == null ? ArcadeInput.idle : ArcadeInput(swipe: d);
  }
  // Burada bomba işe yarar mı? (sandık/canavar menzilde)
  final reachable = s.blast(s.px, s.py);
  final useful = reachable.any((c) => s.g[c.$1][c.$2] == 2) ||
      s.monsters.any((m) => !m.dead && reachable.any((c) => c.$1 == m.x && c.$2 == m.y));
  if (useful && s.bombs.length < s.maxBombs && s.bombs.isEmpty) {
    // Kaçış: bomba konduktan sonra güvenli hücre var mı (fitil süresinde)?
    final future = {...danger, for (final (x, y) in s.blast(s.px, s.py)) s.key(x, y)};
    final esc = bfs((x, y) => !future.contains(s.key(x, y)) && !monsterNear(x, y), {}, maxD: 8);
    if (esc != null) return const ArcadeInput(tap: true, down: true, x: 500, y: 800);
  }
  // Hedefe ilerle: canavarın 2 hücre yakınına ya da bir sandığın komşusuna.
  final target = bfs((x, y) {
    if (danger.contains(s.key(x, y))) return false;
    for (var dir = 0; dir < 4; dir++) {
      final nx = x + _dx[dir], ny = y + _dy[dir];
      if (s.g[nx][ny] == 2) return true;
    }
    return s.monsters.any((m) => !m.dead && (m.x == x || m.y == y) && (m.x - x).abs() + (m.y - y).abs() <= s.range && (m.x - x).abs() + (m.y - y).abs() >= 2);
  }, danger);
  if (target != null) {
    final nx = s.px + _dx[target], ny = s.py + _dy[target];
    if (!monsterNear(nx, ny)) return ArcadeInput(swipe: target);
  }
  return ArcadeInput.idle;
}

void paintBomber(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as BomberSim;
  paintSky(c, const Color(0xFF386641), const Color(0xFF283618));
  Rect cell(double x, double y) => Rect.fromLTWH(x * kC, kTop + y * kC, kC, kC);
  for (var x = 0; x < kW; x++) {
    for (var y = 0; y < kH; y++) {
      final v = s.g[x][y];
      final r = cell(x.toDouble(), y.toDouble());
      c.drawRect(r, Paint()..color = (x + y).isEven ? const Color(0xFF6A994E) : const Color(0xFF5F8D45));
      if (x == s.doorX && y == s.doorY && v != 2) {
        paintBox(c, r.deflate(8), s.doorOpen ? const Color(0xFFFFC300) : const Color(0xFF6C757D), radius: 10);
        paintText(c, s.doorOpen ? '⇪' : '✕', r.center, kC * 0.5, Colors.white);
      }
      if (v == 1) paintBox(c, r.deflate(2), const Color(0xFF495057), radius: 8, shade: false);
      if (v == 2) {
        paintBox(c, r.deflate(6), const Color(0xFFBC6C25), radius: 6, shade: false);
        c.drawLine(r.topLeft + const Offset(10, 10), r.bottomRight - const Offset(10, 10), Paint()
          ..color = const Color(0xFF8B4513)
          ..strokeWidth = 5);
      }
    }
  }
  for (final e in s.flames.keys) {
    final r = cell((e ~/ 100).toDouble(), (e % 100).toDouble());
    c.drawRRect(RRect.fromRectAndRadius(r.deflate(4), const Radius.circular(20)), Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.85));
    c.drawRRect(RRect.fromRectAndRadius(r.deflate(20), const Radius.circular(12)), Paint()..color = const Color(0xFFFFE066));
  }
  for (final b in s.bombs) {
    final r = cell(b.x.toDouble(), b.y.toDouble());
    final pulse = 1 + 0.08 * math.sin((s.ticks - b.placed) / 4);
    paintBall(c, r.center, kC * 0.34 * pulse, const Color(0xFF212529));
    c.drawCircle(r.center + Offset(kC * 0.2, -kC * 0.3), 6, Paint()..color = (s.ticks ~/ 6).isEven ? const Color(0xFFFF6D00) : Colors.yellow);
  }
  for (final m in s.monsters) {
    if (m.dead) continue;
    final r = cell(m.fx, m.fy);
    paintBall(c, r.center, kC * 0.36, const Color(0xFFB5179E));
    c.drawCircle(r.center + const Offset(-10, -6), 7, Paint()..color = Colors.white);
    c.drawCircle(r.center + const Offset(10, -6), 7, Paint()..color = Colors.white);
  }
  final pr = cell(s.fx, s.fy);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, pr.center, kC * 0.36, blink ? Colors.white54 : p.piece(0));
  c.drawCircle(pr.center + const Offset(0, -6), kC * 0.18, Paint()..color = const Color(0xFFFFD6A5));
  paintText(c, '💣${s.maxBombs}  ✸${s.range}', const Offset(500, 50), 40, Colors.white70);
}

Sfx? bomberSound(ArcadeSim sim) => switch ((sim as BomberSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.clear,
      3 => Sfx.lose,
      4 => Sfx.coin,
      5 => Sfx.win,
      _ => null,
    };

KitRules bomberRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('mazes_cleared', 'Geçilen labirent', 'Mazes cleared', scale: 50),
        GameStat('monsters_defeated', 'Yenilen canavar', 'Monsters defeated', scale: 200),
        GameStat('crates_broken', 'Kırılan sandık', 'Crates broken', scale: 500),
      ],
      missionTemplates: const [
        MissionTemplate('monsters_defeated', 'monsters_defeated', [10, 20, 40]),
        MissionTemplate('crates_broken', 'crates_broken', [30, 60, 120]),
      ],
      make: BomberSim.new,
      botFn: bomberBot,
    );
