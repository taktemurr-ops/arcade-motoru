import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Işık motoru: arkanda ışık izi bırakan motorla dön (kaydır / oklar).
/// Ize ya da duvara çarpan elenir. Rakip motorların hepsi elenirse turu
/// kazanırsın; sen çarparsan can gider ve tur yeniden başlar.
const int kGW = 40, kGH = 60;
const double kCellPx = 25, kTop = 60;

class Cycle {
  int x, y, dir; // 0 yukarı 1 sağ 2 aşağı 3 sol
  bool alive = true;
  final int id;
  Cycle(this.x, this.y, this.dir, this.id);
}

const _dx = [0, 1, 0, -1], _dy = [-1, 0, 1, 0];

class TronSim extends ArcadeSim {
  final ALevel level;
  late List<List<int>> grid; // 0 boş, id+1 iz
  final List<Cycle> cycles = [];
  int roundsWon = 0, step = 0, cellsDriven = 0, lastEvent = 0, wait = 40, pendingTurn = -1;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 4;
  late final int speedTicks = math.max(3, 6 - level.d ~/ 3);

  TronSim(this.level) : super(level.meta) {
    _newRound();
  }

  Cycle get me => cycles.first;

  void _newRound() {
    grid = List.generate(kGW, (_) => List<int>.filled(kGH, 0));
    cycles
      ..clear()
      ..add(Cycle(kGW ~/ 2, kGH - 8, 0, 0));
    final n = 1 + math.min(level.d ~/ 3, 3);
    final spots = [(kGW ~/ 2, 7, 2), (6, kGH ~/ 2, 1), (kGW - 7, kGH ~/ 2, 3), (8, 10, 1)];
    for (var i = 0; i < n; i++) {
      final (x, y, d) = spots[i];
      cycles.add(Cycle(x, y, d, i + 1));
    }
    // Engeller
    final blocks = level.has('walls') || level.d >= 5 ? 3 + level.d ~/ 2 : 0;
    for (var b = 0; b < blocks; b++) {
      final bx = 4 + rng.nextInt(kGW - 8), by = 14 + rng.nextInt(kGH - 28);
      for (var k = 0; k < 4; k++) {
        final xx = bx + (b.isEven ? k : 0), yy = by + (b.isEven ? 0 : k);
        if (xx < kGW && yy < kGH && cycles.every((c) => (c.x - xx).abs() + (c.y - yy).abs() > 4)) grid[xx][yy] = 9;
      }
    }
    for (final c in cycles) {
      grid[c.x][c.y] = c.id + 1;
    }
    wait = 40;
    pendingTurn = -1;
  }

  bool free(int x, int y) => x >= 0 && y >= 0 && x < kGW && y < kGH && grid[x][y] == 0;

  /// Bir hücreden ulaşılabilir boş alan (sınırlı BFS).
  int reach(int sx, int sy, int cap) {
    if (!free(sx, sy)) return 0;
    final seen = <int>{sx * 100 + sy};
    final q = [(sx, sy)];
    var i = 0;
    while (i < q.length && seen.length < cap) {
      final (x, y) = q[i++];
      for (var d = 0; d < 4; d++) {
        final nx = x + _dx[d], ny = y + _dy[d];
        if (free(nx, ny) && seen.add(nx * 100 + ny)) q.add((nx, ny));
      }
    }
    return seen.length;
  }

  /// Rakip yapay zekâsı: en geniş alana dönen yönü seçer; zorluk düşükse
  /// bazen yalnız bir adım ileriye bakar.
  int aiDir(Cycle c) {
    var best = c.dir, bestV = -1;
    final smart = rng.nextDouble() < 0.45 + level.d * 0.05;
    for (final d in [c.dir, (c.dir + 1) % 4, (c.dir + 3) % 4]) {
      final nx = c.x + _dx[d], ny = c.y + _dy[d];
      if (!free(nx, ny)) continue;
      final v = smart ? reach(nx, ny, 300) : 1 + (d == c.dir ? 1 : 0);
      if (v > bestV) {
        bestV = v;
        best = d;
      }
    }
    return best;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var sw = input.swipe;
    if (sw < 0 && (input.dirX != 0 || input.dirY != 0)) {
      sw = input.dirY < 0 ? 0 : (input.dirX > 0 ? 1 : (input.dirY > 0 ? 2 : 3));
    }
    if (sw < 0 && input.tap && input.hasPointer) {
      // Dokunma: ekranın soluna = sola dön, sağına = sağa dön
      sw = input.x < 500 ? (me.dir + 3) % 4 : (me.dir + 1) % 4;
    }
    if (sw >= 0 && sw != (me.dir + 2) % 4) pendingTurn = sw;
    if (wait > 0) {
      wait--;
      return;
    }
    if (ticks % speedTicks != 0) return;
    step++;
    if (pendingTurn >= 0) {
      me.dir = pendingTurn;
      pendingTurn = -1;
    }
    for (final c in cycles.skip(1)) {
      if (c.alive) c.dir = aiDir(c);
    }
    // Hareket (eşzamanlı)
    final targets = <Cycle, (int, int)>{};
    for (final c in cycles) {
      if (c.alive) targets[c] = (c.x + _dx[c.dir], c.y + _dy[c.dir]);
    }
    for (final e in targets.entries) {
      final (nx, ny) = e.value;
      final clash = targets.entries.any((o) => o.key != e.key && o.value == e.value);
      if (!free(nx, ny) || clash) {
        e.key.alive = false;
      }
    }
    for (final e in targets.entries) {
      if (!e.key.alive) continue;
      final (nx, ny) = e.value;
      e.key
        ..x = nx
        ..y = ny;
      grid[nx][ny] = e.key.id + 1;
    }
    if (me.alive) cellsDriven++;
    if (!me.alive) {
      lastEvent = 3;
      hit();
      if (!over) _newRound();
      return;
    }
    if (cycles.skip(1).every((c) => !c.alive)) {
      roundsWon++;
      score += 100 + cellsDriven ~/ 10;
      lastEvent = 2;
      if (goalN > 0 && roundsWon >= goalN) {
        win();
        return;
      }
      _newRound();
    } else if (!meta.goal && step % 400 == 0) {
      _newRound();
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : roundsWon / goalN;
  @override
  String get goalText => goalN == 0 ? '$roundsWon' : '$roundsWon/$goalN';
  @override
  Map<String, int> get stats => {'rounds_won': roundsWon, 'cells_driven': cellsDriven};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: her yön için ulaşılabilir alanı ölçer; rakibin önünü kesmek için
/// en yakın rakibe yaklaşan yönü eşitlikte tercih eder.
ArcadeInput tronBot(ArcadeSim sim) {
  final s = sim as TronSim;
  final me = s.me;
  if (!me.alive || s.wait > 0) return ArcadeInput.idle;
  if ((s.ticks + 1) % s.speedTicks != 0) return ArcadeInput.idle;
  var best = me.dir;
  var bestV = -1.0;
  Cycle? foe;
  for (final c in s.cycles.skip(1)) {
    if (c.alive && (foe == null || (c.x - me.x).abs() + (c.y - me.y).abs() < (foe.x - me.x).abs() + (foe.y - me.y).abs())) foe = c;
  }
  for (final d in [me.dir, (me.dir + 1) % 4, (me.dir + 3) % 4]) {
    final nx = me.x + _dx[d], ny = me.y + _dy[d];
    if (!s.free(nx, ny)) continue;
    // Rakibin de gidebileceği hücreden kaçın (kafa kafaya).
    var danger = false;
    for (final c in s.cycles.skip(1)) {
      if (c.alive && (c.x - nx).abs() + (c.y - ny).abs() == 1) danger = true;
    }
    var v = s.reach(nx, ny, 1200).toDouble();
    if (danger) v -= 500;
    if (foe != null) v -= ((foe.x - nx).abs() + (foe.y - ny).abs()) * 0.5;
    if (d == me.dir) v += 0.3;
    if (v > bestV) {
      bestV = v;
      best = d;
    }
  }
  return best == me.dir ? ArcadeInput.idle : ArcadeInput(swipe: best);
}

void paintTron(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as TronSim;
  paintSky(c, const Color(0xFF020617), const Color(0xFF0F172A));
  const board = Rect.fromLTWH(0, kTop, kGW * kCellPx, kGH * kCellPx);
  c.drawRect(board, Paint()..color = const Color(0xFF020617));
  paintGrid(c, board, kCellPx * 2, const Color(0x2238BDF8));
  final cols = [p.piece(0), const Color(0xFFF97316), const Color(0xFFE11D48), const Color(0xFFA3E635), const Color(0xFFFACC15)];
  for (var x = 0; x < kGW; x++) {
    for (var y = 0; y < kGH; y++) {
      final v = s.grid[x][y];
      if (v == 0) continue;
      final r = Rect.fromLTWH(x * kCellPx, kTop + y * kCellPx, kCellPx, kCellPx);
      if (v == 9) {
        paintBox(c, r.deflate(1), const Color(0xFF475569), radius: 4, shade: false);
      } else {
        final col = cols[(v - 1) % cols.length];
        c.drawRect(r.deflate(4), Paint()..color = col.withValues(alpha: 0.85));
        c.drawRect(r.deflate(9), Paint()..color = Colors.white38);
      }
    }
  }
  for (final cy in s.cycles) {
    if (!cy.alive) continue;
    final o = Offset((cy.x + 0.5) * kCellPx, kTop + (cy.y + 0.5) * kCellPx);
    c.drawCircle(o, kCellPx * 1.1, Paint()..color = cols[cy.id % cols.length].withValues(alpha: 0.35));
    final blink = cy.id == 0 && s.shield > 0 && (s.ticks ~/ 5).isOdd;
    paintBall(c, o, kCellPx * 0.6, blink ? Colors.white : cols[cy.id % cols.length]);
  }
}

Sfx? tronSound(ArcadeSim sim) => switch ((sim as TronSim).lastEvent) {
      2 => Sfx.win,
      3 => Sfx.lose,
      _ => null,
    };

KitRules tronRules(String id) => KitRules(
      id,
      optionalMechanics: const ['walls'],
      gameStats: const [
        GameStat('rounds_won', 'Kazanılan tur', 'Rounds won', scale: 50),
        GameStat('cells_driven', 'Gidilen hücre', 'Cells driven', scale: 5000),
      ],
      missionTemplates: const [
        MissionTemplate('rounds_won', 'rounds_won', [3, 6, 12]),
        MissionTemplate('cells_driven', 'cells_driven', [500, 1000, 2000]),
      ],
      make: TronSim.new,
      botFn: tronBot,
    );
