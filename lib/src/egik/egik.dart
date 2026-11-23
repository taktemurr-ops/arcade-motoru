import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Eğik labirent: tahtayı eğerek bilyeyi hedef deliğe yuvarla. Parmağını
/// ekranın merkezinden uzaklaştırdıkça o yöne eğim artar (klavye: oklar).
/// Kara deliklere düşen bilye başa döner.
const double kTop = 180, kBallR = 24;

class TiltSim extends ArcadeSim {
  final ALevel level;
  late int cols, rows;
  late double cell;
  late List<List<bool>> wall; // [r][c]
  final List<(int, int)> holes = [];
  late (int, int) start, goal;
  double x = 0, y = 0, vx = 0, vy = 0, tx = 0, ty = 0;
  int solved = 0, falls = 0, lastEvent = 0, doneAt = -1;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;

  TiltSim(this.level) : super(level.meta) {
    _newMaze();
  }

  Offset center(int r, int c) => Offset((c + 0.5) * cell, kTop + (r + 0.5) * cell);

  void _newMaze() {
    final mc = 4 + math.min<int>(level.d ~/ 3, 2); // labirent hücresi (sütun)
    final mr = (mc * 1.4).floor();
    cols = mc * 2 + 1;
    rows = mr * 2 + 1;
    cell = kWorldW / cols;
    wall = List.generate(rows, (_) => List<bool>.filled(cols, true));
    // DFS labirent
    final seen = List.generate(mr, (_) => List<bool>.filled(mc, false));
    final stack = <(int, int)>[(0, 0)];
    seen[0][0] = true;
    wall[1][1] = false;
    while (stack.isNotEmpty) {
      final (r, c) = stack.last;
      final nb = <(int, int)>[];
      for (final (dr, dc) in const [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
        final nr = r + dr, nc = c + dc;
        if (nr >= 0 && nr < mr && nc >= 0 && nc < mc && !seen[nr][nc]) nb.add((nr, nc));
      }
      if (nb.isEmpty) {
        stack.removeLast();
        continue;
      }
      final (nr, nc) = rng.pick(nb);
      seen[nr][nc] = true;
      wall[r * 2 + 1 + (nr - r)][c * 2 + 1 + (nc - c)] = false;
      wall[nr * 2 + 1][nc * 2 + 1] = false;
      stack.add((nr, nc));
    }
    // Ek açıklıklar (döngüler) — daha akıcı
    for (var k = 0; k < mc; k++) {
      final r = 1 + rng.nextInt(rows - 2), c = 1 + rng.nextInt(cols - 2);
      if ((r.isEven) != (c.isEven)) wall[r][c] = false;
    }
    start = (1, 1);
    goal = (rows - 2, cols - 2);
    // Delikler: çözüm yolunun dışındaki çıkmazlara
    holes.clear();
    final path = bfs(start, goal).toSet();
    final nHoles = math.min(1 + level.d ~/ 2, 6);
    final cand = <(int, int)>[];
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        if (wall[r][c] || path.contains((r, c)) || (r, c) == start) continue;
        cand.add((r, c));
      }
    }
    rng.shuffle(cand);
    for (final h in cand.take(nHoles)) {
      holes.add(h);
    }
    final s = center(start.$1, start.$2);
    x = s.dx;
    y = s.dy;
    vx = vy = 0;
  }

  /// Hücre yolu (BFS), başlangıç hariç.
  List<(int, int)> bfs((int, int) from, (int, int) to) {
    final prev = <(int, int), (int, int)>{};
    final q = <(int, int)>[from];
    final seen = {from};
    var i = 0;
    while (i < q.length) {
      final cur = q[i++];
      if (cur == to) break;
      for (final (dr, dc) in const [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
        final n = (cur.$1 + dr, cur.$2 + dc);
        if (n.$1 < 0 || n.$1 >= rows || n.$2 < 0 || n.$2 >= cols) continue;
        if (wall[n.$1][n.$2] || seen.contains(n) || holes.contains(n)) continue;
        seen.add(n);
        prev[n] = cur;
        q.add(n);
      }
    }
    final out = <(int, int)>[];
    var cur = to;
    while (cur != from && prev.containsKey(cur)) {
      out.add(cur);
      cur = prev[cur]!;
    }
    return out.reversed.toList();
  }

  (int, int) cellOf(double px, double py) => (((py - kTop) / cell).floor(), (px / cell).floor());

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 45) {
        doneAt = -1;
        _newMaze();
      }
      return;
    }
    if (input.down && input.hasPointer) {
      tx = clampD((input.x - 500) / 350, -1, 1);
      ty = clampD((input.y - 900) / 350, -1, 1);
    } else if (input.dirX != 0 || input.dirY != 0) {
      tx = input.dirX.toDouble();
      ty = input.dirY.toDouble();
    } else {
      tx *= 0.9;
      ty *= 0.9;
    }
    vx = (vx + tx * 0.42) * 0.97;
    vy = (vy + ty * 0.42) * 0.97;
    final sp = math.sqrt(vx * vx + vy * vy);
    if (sp > 11) {
      vx *= 11 / sp;
      vy *= 11 / sp;
    }
    _move(vx, 0);
    _move(0, vy);
    final (r, c) = cellOf(x, y);
    for (final h in holes) {
      final o = center(h.$1, h.$2);
      if (dist(x, y, o.dx, o.dy) < cell * 0.28) {
        falls++;
        lastEvent = 3;
        hit();
        if (!over) {
          final s = center(start.$1, start.$2);
          x = s.dx;
          y = s.dy;
          vx = vy = 0;
        }
        return;
      }
    }
    final g = center(goal.$1, goal.$2);
    if ((r, c) == goal && dist(x, y, g.dx, g.dy) < cell * 0.3) {
      solved++;
      score += 100;
      lastEvent = 2;
      doneAt = ticks;
      if (goalN > 0 && solved >= goalN) win();
    }
  }

  void _move(double dx, double dy) {
    x += dx;
    y += dy;
    final (r0, c0) = cellOf(x, y);
    for (var r = r0 - 1; r <= r0 + 1; r++) {
      for (var c = c0 - 1; c <= c0 + 1; c++) {
        if (r < 0 || r >= rows || c < 0 || c >= cols || !wall[r][c]) continue;
        final left = c * cell, top = kTop + r * cell;
        final nx = clampD(x, left, left + cell), ny = clampD(y, top, top + cell);
        final d = dist(x, y, nx, ny);
        if (d < kBallR) {
          if (dx != 0) {
            x = dx > 0 ? left - kBallR : left + cell + kBallR;
            vx = -vx * 0.3;
          }
          if (dy != 0) {
            y = dy > 0 ? top - kBallR : top + cell + kBallR;
            vy = -vy * 0.3;
          }
        }
      }
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : solved / goalN;
  @override
  String get goalText => goalN == 0 ? '$solved' : '$solved/$goalN';
  @override
  Map<String, int> get stats => {'mazes_solved': solved, 'falls': falls};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: BFS yolundaki bir sonraki hücre merkezine doğru hız denetimi.
ArcadeInput tiltBot(ArcadeSim sim) {
  final s = sim as TiltSim;
  if (s.doneAt >= 0) return ArcadeInput.idle;
  final here = s.cellOf(s.x, s.y);
  final path = s.bfs(here, s.goal);
  Offset target;
  if (path.isEmpty) {
    target = s.center(s.goal.$1, s.goal.$2);
  } else {
    target = s.center(path.first.$1, path.first.$2);
    // Düz giden yolda biraz ileri bak.
    if (path.length > 1) {
      final a = path[0], b = path[1];
      final dirSame = (a.$1 - here.$1, a.$2 - here.$2) == (b.$1 - a.$1, b.$2 - a.$2);
      if (dirSame) target = s.center(b.$1, b.$2);
    }
  }
  // Hücrenin içinde merkez hattına hizala (köşelerde takılmasın).
  final hc = s.center(here.$1, here.$2);
  final dx = target.dx - s.x, dy = target.dy - s.y;
  final horiz = dx.abs() > dy.abs();
  final wantVx = horiz ? clampD(dx * 0.06, -6, 6) : clampD((hc.dx - s.x) * 0.15, -3, 3);
  final wantVy = horiz ? clampD((hc.dy - s.y) * 0.15, -3, 3) : clampD(dy * 0.06, -6, 6);
  final ax = clampD((wantVx - s.vx) * 0.8, -1, 1), ay = clampD((wantVy - s.vy) * 0.8, -1, 1);
  return holdAt(500 + ax * 350, 900 + ay * 350);
}

void paintTilt(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as TiltSim;
  paintSky(c, const Color(0xFFDDB892), const Color(0xFFB08968));
  final board = Rect.fromLTWH(0, kTop, kWorldW, s.rows * s.cell);
  c.drawRect(board, Paint()..color = const Color(0xFFEDE0D4));
  paintGrid(c, board, s.cell / 2, const Color(0x0F000000));
  for (final h in s.holes) {
    final o = s.center(h.$1, h.$2);
    c.drawCircle(o, s.cell * 0.34, Paint()..shader = const RadialGradient(colors: [Colors.black, Color(0xFF3D2B1F)]).createShader(Rect.fromCircle(center: o, radius: s.cell * 0.34)));
  }
  final g = s.center(s.goal.$1, s.goal.$2);
  c.drawCircle(g, s.cell * 0.38, Paint()..color = const Color(0xFF2D6A4F));
  c.drawCircle(g, s.cell * 0.28, Paint()..color = const Color(0xFF081C15));
  c.drawCircle(g, s.cell * 0.42, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..color = const Color(0xFFFFC300));
  for (var r = 0; r < s.rows; r++) {
    for (var col = 0; col < s.cols; col++) {
      if (!s.wall[r][col]) continue;
      paintBox(c, Rect.fromLTWH(col * s.cell, kTop + r * s.cell, s.cell + 0.5, s.cell + 0.5), const Color(0xFF7F5539), radius: 6, shade: false);
    }
  }
  paintShadow(c, Offset(s.x + 8, s.y + 18), 50);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, Offset(s.x, s.y), kBallR, blink ? Colors.white38 : const Color(0xFFADB5BD));
  // eğim göstergesi
  c.drawCircle(const Offset(500, 100), 50, Paint()..color = Colors.black12);
  c.drawCircle(Offset(500 + s.tx * 36, 100 + s.ty * 36), 16, Paint()..color = p.piece(0));
}

Sfx? tiltSound(ArcadeSim sim) => switch ((sim as TiltSim).lastEvent) {
      2 => Sfx.win,
      3 => Sfx.lose,
      _ => null,
    };

KitRules tiltRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('mazes_solved', 'Çözülen labirent', 'Mazes solved', scale: 50),
        GameStat('falls', 'Deliğe düşüş', 'Falls', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('mazes_solved', 'mazes_solved', [3, 6, 12]),
      ],
      make: TiltSim.new,
      botFn: tiltBot,
    );
