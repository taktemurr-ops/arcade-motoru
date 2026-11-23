import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Alan kapma: kendi bölgenden çık, arkanda iz bırak, geri dön: izin
/// çevrelediği alan senin olur. Rakip izine değersen ya da rakip senin
/// izine değerse ölür. Kendi izine çarpmak can götürür. Hedef yüzdeye ulaş.
const int kGW = 40, kGH = 56;
const double kCell = 25, kTop = 160;
const _dx = [0, 1, 0, -1], _dy = [-1, 0, 1, 0];

class Player {
  final int id; // 1 oyuncu, 2.. rakipler
  int x, y, dir = 0;
  final List<int> trail = [];
  bool alive = true;
  int respawn = 0;
  // Yapay zekâ/bot planı
  int plan = 0, out = 0, leg = 0, legLen = 0, side = 1;
  Player(this.id, this.x, this.y);
}

class PaperSim extends ArcadeSim {
  final ALevel level;
  late List<int> owner; // kGW*kGH
  late List<int> trailOf; // hangi oyuncunun izi
  final List<Player> ps = [];
  int pendingDir = -1, kills = 0, lastEvent = 0, bestPct = 0;
  late final int goalPct = level.target(25, 3) == 0 ? 0 : 25 + level.d * 3;
  late final int stepTicks = math.max(4, 7 - level.d ~/ 4);

  PaperSim(this.level) : super(level.meta) {
    owner = List<int>.filled(kGW * kGH, 0);
    trailOf = List<int>.filled(kGW * kGH, 0);
    _spawn(Player(1, kGW ~/ 2, kGH - 10));
    final n = 1 + math.min(level.d ~/ 3, 3);
    final spots = [(8, 10), (kGW - 9, 10), (8, kGH ~/ 2), (kGW - 9, kGH ~/ 2)];
    for (var i = 0; i < n; i++) {
      final (x, y) = spots[i];
      _spawn(Player(i + 2, x, y));
    }
  }

  Player get me => ps.first;
  int idx(int x, int y) => y * kGW + x;
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < kGW && y < kGH;

  void _spawn(Player p) {
    if (!ps.contains(p)) ps.add(p);
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = p.x + dx, y = p.y + dy;
        if (inside(x, y)) owner[idx(x, y)] = p.id;
      }
    }
    p.alive = true;
    p.trail.clear();
    p.plan = 0;
  }

  int areaOf(int id) => owner.where((o) => o == id).length;
  int get pct => areaOf(1) * 100 ~/ (kGW * kGH);

  void _kill(Player p) {
    for (final t in p.trail) {
      if (trailOf[t] == p.id) trailOf[t] = 0;
    }
    p.trail.clear();
    if (p.id == 1) return;
    p.alive = false;
    p.respawn = 240;
    for (var i = 0; i < owner.length; i++) {
      if (owner[i] == p.id) owner[i] = 0;
    }
    kills++;
    score += 150;
    lastEvent = 4;
  }

  void _capture(Player p) {
    for (final t in p.trail) {
      owner[t] = p.id;
      trailOf[t] = 0;
    }
    p.trail.clear();
    // Dışarıdan ulaşılamayan hücreler kapanmış demektir.
    final reach = List<bool>.filled(kGW * kGH, false);
    final q = <int>[];
    for (var x = 0; x < kGW; x++) {
      for (final y in [0, kGH - 1]) {
        final i = idx(x, y);
        if (owner[i] != p.id && !reach[i]) {
          reach[i] = true;
          q.add(i);
        }
      }
    }
    for (var y = 0; y < kGH; y++) {
      for (final x in [0, kGW - 1]) {
        final i = idx(x, y);
        if (owner[i] != p.id && !reach[i]) {
          reach[i] = true;
          q.add(i);
        }
      }
    }
    var h = 0;
    while (h < q.length) {
      final i = q[h++];
      final x = i % kGW, y = i ~/ kGW;
      for (var d = 0; d < 4; d++) {
        final nx = x + _dx[d], ny = y + _dy[d];
        if (!inside(nx, ny)) continue;
        final j = idx(nx, ny);
        if (!reach[j] && owner[j] != p.id) {
          reach[j] = true;
          q.add(j);
        }
      }
    }
    var gained = 0;
    for (var i = 0; i < owner.length; i++) {
      if (!reach[i] && owner[i] != p.id) {
        owner[i] = p.id;
        if (trailOf[i] != 0) {
          final victim = ps.firstWhere((o) => o.id == trailOf[i]);
          if (victim.alive && victim.id != p.id) _kill(victim);
        }
        gained++;
      }
    }
    if (p.id == 1) {
      score += gained + 10;
      lastEvent = 2;
    }
  }

  void _step(Player p, int dir) {
    if (dir >= 0 && dir != (p.dir + 2) % 4) p.dir = dir;
    var nx = p.x + _dx[p.dir], ny = p.y + _dy[p.dir];
    if (!inside(nx, ny)) {
      // kenarda dön
      p.dir = (p.dir + 1) % 4;
      nx = p.x + _dx[p.dir];
      ny = p.y + _dy[p.dir];
      if (!inside(nx, ny)) {
        p.dir = (p.dir + 2) % 4;
        nx = p.x + _dx[p.dir];
        ny = p.y + _dy[p.dir];
      }
    }
    final i = idx(nx, ny);
    final t = trailOf[i];
    if (t == p.id) {
      // kendi izi
      if (p.id == 1) {
        lastEvent = 3;
        _kill(p);
        hit();
        return;
      }
      _kill(p);
      return;
    }
    if (t != 0) {
      final victim = ps.firstWhere((o) => o.id == t);
      if (victim.id == 1) {
        _kill(victim);
        lastEvent = 3;
        hit();
      } else {
        _kill(victim);
      }
    }
    p.x = nx;
    p.y = ny;
    if (owner[i] == p.id) {
      if (p.trail.isNotEmpty) _capture(p);
    } else {
      trailOf[i] = p.id;
      p.trail.add(i);
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var sw = input.swipe;
    if (sw < 0 && (input.dirX != 0 || input.dirY != 0)) {
      sw = input.dirY < 0 ? 0 : (input.dirX > 0 ? 1 : (input.dirY > 0 ? 2 : 3));
    }
    if (sw < 0 && input.down && input.hasPointer) {
      // basılı tut: parmağa doğru dön
      final px = (me.x + 0.5) * kCell, py = kTop + (me.y + 0.5) * kCell;
      final ddx = input.x - px, ddy = input.y - py;
      if (ddx.abs() + ddy.abs() > 40) sw = ddx.abs() > ddy.abs() ? (ddx > 0 ? 1 : 3) : (ddy > 0 ? 2 : 0);
    }
    if (sw >= 0) pendingDir = sw;
    if (ticks % stepTicks != 0) return;
    _step(me, pendingDir);
    pendingDir = -1;
    if (over) return;
    for (final p in ps.skip(1)) {
      if (!p.alive) {
        if (--p.respawn <= 0) {
          p.x = 4 + rng.nextInt(kGW - 8);
          p.y = 4 + rng.nextInt(kGH ~/ 2);
          if ((p.x - me.x).abs() + (p.y - me.y).abs() > 12) _spawn(p);
        }
        continue;
      }
      _step(p, planDir(this, p, cautious: false));
    }
    bestPct = math.max(bestPct, pct);
    if (goalPct > 0 && pct >= goalPct) win();
  }

  @override
  void onLifeLost() {
    // Kendi bölgendeki en yakın hücreye dön; bölge kalmadıysa yeniden başla.
    var best = -1, bd = 1 << 30;
    for (var i = 0; i < owner.length; i++) {
      if (owner[i] != 1) continue;
      final d = (i % kGW - me.x).abs() + (i ~/ kGW - me.y).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best < 0) {
      me
        ..x = kGW ~/ 2
        ..y = kGH - 10;
      _spawn(me);
    } else {
      me
        ..x = best % kGW
        ..y = best ~/ kGW;
    }
    me.plan = 0;
  }

  @override
  double get progress => goalPct == 0 ? 0 : pct / goalPct;
  @override
  String get goalText => goalPct == 0 ? '%$pct' : '%$pct / %$goalPct';
  @override
  Map<String, int> get stats => {'best_area_pct': bestPct, 'rivals_cut': kills};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bölgeden çıkıp dikdörtgen çizen plan (oyuncu botu ve rakipler).
int planDir(PaperSim s, Player p, {required bool cautious}) {
  final home = s.owner[s.idx(p.x, p.y)] == p.id;
  if (home) {
    p.plan = 0;
    // Sınıra git: en yakın kendi-olmayan, iz olmayan komşu hücre.
    final seen = <int>{s.idx(p.x, p.y)};
    final q = <(int, int, int)>[(p.x, p.y, -1)];
    var i = 0;
    while (i < q.length) {
      final (x, y, first) = q[i++];
      for (var d = 0; d < 4; d++) {
        final nx = x + _dx[d], ny = y + _dy[d];
        if (!s.inside(nx, ny) || !seen.add(s.idx(nx, ny))) continue;
        if (first < 0 && d == (p.dir + 2) % 4) continue;
        final j = s.idx(nx, ny);
        if (s.trailOf[j] != 0) continue;
        if (s.owner[j] != p.id) {
          // çıkış: dışarı uzunluk ve yan uzunluk seç
          p
            ..plan = 1
            ..out = 0
            ..leg = 0
            ..legLen = 3 + s.rng.nextInt(cautious ? 3 : 5)
            ..side = s.rng.chance(0.5) ? 1 : 3;
          return first < 0 ? d : first;
        }
        q.add((nx, ny, first < 0 ? d : first));
      }
    }
    return p.dir;
  }
  // Dışarıda: tehlike varsa ya da plan bittiyse eve dön.
  var danger = false;
  for (final o in s.ps) {
    if (o == p || !o.alive) continue;
    for (final t in p.trail.isEmpty ? [s.idx(p.x, p.y)] : [...p.trail.take(1), ...p.trail.skip(p.trail.length - 1), s.idx(p.x, p.y)]) {
      if ((o.x - t % kGW).abs() + (o.y - t ~/ kGW).abs() < (cautious ? 9 : 4)) danger = true;
    }
  }
  if (p.plan == 1 && !danger) {
    p.out++;
    if (p.out < p.legLen) return p.dir;
    p.plan = 2;
    p.leg = 0;
    final nd = (p.dir + p.side) % 4;
    if (_safe(s, p, nd)) return nd;
    p.plan = 3;
  }
  if (p.plan == 2 && !danger) {
    p.leg++;
    if (p.leg < p.legLen + 1 && _safe(s, p, p.dir)) return p.dir;
    p.plan = 3;
  }
  // Eve dön: BFS (izlerden kaçın)
  final seen = <int>{s.idx(p.x, p.y)};
  final q = <(int, int, int)>[(p.x, p.y, -1)];
  var i = 0;
  while (i < q.length) {
    final (x, y, first) = q[i++];
    for (var d = 0; d < 4; d++) {
      if (first < 0 && d == (p.dir + 2) % 4) continue;
      final nx = x + _dx[d], ny = y + _dy[d];
      if (!s.inside(nx, ny) || !seen.add(s.idx(nx, ny))) continue;
      final j = s.idx(nx, ny);
      if (s.trailOf[j] == p.id) continue;
      final f = first < 0 ? d : first;
      if (s.owner[j] == p.id) return f;
      q.add((nx, ny, f));
    }
  }
  return p.dir;
}

bool _safe(PaperSim s, Player p, int d) {
  final nx = p.x + _dx[d], ny = p.y + _dy[d];
  return s.inside(nx, ny) && s.trailOf[s.idx(nx, ny)] != p.id;
}

ArcadeInput paperBot(ArcadeSim sim) {
  final s = sim as PaperSim;
  if ((s.ticks + 1) % s.stepTicks != 0) return ArcadeInput.idle;
  final d = planDir(s, s.me, cautious: true);
  return ArcadeInput(swipe: d);
}

void paintPaper(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as PaperSim;
  paintSky(c, const Color(0xFFF1F5F9), const Color(0xFFE2E8F0));
  const board = Rect.fromLTWH(0, kTop, kGW * kCell, kGH * kCell);
  c.drawRect(board, Paint()..color = Colors.white);
  paintGrid(c, board, kCell * 2, const Color(0x0F000000));
  final cols = [p.piece(0), const Color(0xFFF77F00), const Color(0xFF7209B7), const Color(0xFF2A9D8F), const Color(0xFFE63946)];
  for (var y = 0; y < kGH; y++) {
    for (var x = 0; x < kGW; x++) {
      final i = s.idx(x, y);
      final o = s.owner[i], tr = s.trailOf[i];
      final r = Rect.fromLTWH(x * kCell, kTop + y * kCell, kCell + 0.5, kCell + 0.5);
      if (o != 0) c.drawRect(r, Paint()..color = cols[(o - 1) % cols.length].withValues(alpha: 0.55));
      if (tr != 0) c.drawRect(r.deflate(5), Paint()..color = cols[(tr - 1) % cols.length].withValues(alpha: 0.9));
    }
  }
  for (final pl in s.ps) {
    if (!pl.alive) continue;
    final o = Offset((pl.x + 0.5) * kCell, kTop + (pl.y + 0.5) * kCell);
    final blink = pl.id == 1 && s.shield > 0 && (s.ticks ~/ 5).isOdd;
    paintBox(c, Rect.fromCenter(center: o, width: kCell * 1.5, height: kCell * 1.5), blink ? Colors.white : cols[(pl.id - 1) % cols.length], radius: 8);
  }
  paintText(c, '%${s.pct}', const Offset(500, 90), 64, const Color(0xFF334155));
}

Sfx? paperSound(ArcadeSim sim) => switch ((sim as PaperSim).lastEvent) {
      2 => Sfx.place,
      3 => Sfx.lose,
      4 => Sfx.combo,
      _ => null,
    };

KitRules paperRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('best_area_pct', 'En geniş alan %', 'Best area %', scale: 2),
        GameStat('rivals_cut', 'Kesilen rakip', 'Rivals cut', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('best_area_pct', 'best_area_pct', [30, 45, 60]),
        MissionTemplate('rivals_cut', 'rivals_cut', [2, 4, 8]),
      ],
      make: PaperSim.new,
      botFn: paperBot,
    );
