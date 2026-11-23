import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Sapan atışı: sapandan geriye çek, bırak. Ahşap ve taş bloklardan kale;
/// tepelerdeki yuvarlak yaratıkları düşür. Blok kırılınca üstündekiler
/// aşağı düşer; iki kat düşen yaratık da patlar. Atış hakkı bitince kale
/// yeniden kurulur (can gider).
const double kCell = 60, kGroundY = 1320, kSlingX = 190, kSlingY = 1140, kG = 0.42;
const int kGridCols = 8, kGridRows = 10; // x: 480..960

class Proj {
  double x, y, vx, vy;
  Proj(this.x, this.y, this.vx, this.vy);
}

class SlingSim extends ArcadeSim {
  final ALevel level;
  // grid[c][r]: 0 boş, 1 ahşap, 2 taş(2 can), 3 taş(1 can), 9 yaratık; r=0 en alt
  late List<List<int>> grid;
  Proj? proj;
  int shotsLeft = 0, cleared = 0, popped = 0, shots = 0, lastEvent = 0, settleT = 0, boomAt = -100;
  double boomX = 0, boomY = 0;
  final DragTracker drag = DragTracker();
  double aimA = -0.7, aimP = 0.5;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;
  late List<List<int>> _layout;

  SlingSim(this.level) : super(level.meta) {
    _build();
  }

  static double colX(int c) => 480 + c * kCell + kCell / 2;
  static double rowY(int r) => kGroundY - r * kCell - kCell / 2;

  int get creatures => grid.fold(0, (a, col) => a + col.where((v) => v == 9).length);

  void _build() {
    grid = List.generate(kGridCols, (_) => List<int>.filled(kGridRows, 0));
    final nTargets = 1 + math.min<int>(level.d ~/ 3, 3) + rng.nextInt(2);
    final cols = [for (var c = 0; c < kGridCols; c++) c];
    rng.shuffle(cols);
    for (var k = 0; k < nTargets; k++) {
      final c = cols[k];
      final h = rng.nextInt(math.min(2 + level.d ~/ 2, 6));
      for (var r = 0; r < h; r++) {
        grid[c][r] = rng.chance(0.25 + level.d * 0.04) ? 2 : 1;
      }
      grid[c][h] = 9;
      // kalkan: hedefin önüne (solda) bir duvar
      if (c > 0 && level.d >= 3 && rng.chance(0.5)) {
        for (var r = 0; r <= h + 1 && r < kGridRows; r++) {
          if (grid[c - 1][r] == 0) grid[c - 1][r] = 1;
        }
      }
    }
    _settle();
    _layout = [for (final col in grid) [...col]];
    shotsLeft = nTargets + 2;
  }

  void _restore() {
    grid = [for (final col in _layout) [...col]];
    shotsLeft = creatures + 2;
  }

  /// Desteksiz şeyler düşer. 2+ kat düşen yaratık patlar.
  void _settle() {
    for (var c = 0; c < kGridCols; c++) {
      final col = grid[c];
      final stack = <(int, int)>[]; // (değer, eski satır)
      for (var r = 0; r < kGridRows; r++) {
        if (col[r] != 0) stack.add((col[r], r));
      }
      for (var r = 0; r < kGridRows; r++) {
        col[r] = 0;
      }
      var r = 0;
      for (final (v, old) in stack) {
        if (v == 9 && old - r >= 2) {
          popped++;
          score += 50;
          lastEvent = 2;
          continue;
        }
        col[r++] = v;
      }
    }
  }

  void launch(double a, double p) {
    final sp = 12 + p * 22;
    proj = Proj(kSlingX, kSlingY, math.cos(a) * sp, math.sin(a) * sp);
    shotsLeft--;
    shots++;
    lastEvent = 1;
  }

  /// Saf yörünge: ilk çarpılan hücre (c, r) ya da null.
  static (int, int)? trace(List<List<int>> g, double x, double y, double vx, double vy) {
    for (var k = 0; k < 700; k++) {
      vy += kG;
      // ince adımlar (tünelleme olmasın)
      for (var sub = 0; sub < 3; sub++) {
        x += vx / 3;
        y += vy / 3;
        if (y >= kGroundY || x > kWorldW + 40 || x < -40) return null;
        final c = ((x - 480) / kCell).floor();
        final r = ((kGroundY - y) / kCell).floor();
        if (c >= 0 && c < kGridCols && r >= 0 && r < kGridRows && g[c][r] != 0) {
          // yaratık daire, blok kare
          if (g[c][r] == 9) {
            if (dist(x, y, colX(c), rowY(r)) < kCell * 0.48) return (c, r);
          } else {
            return (c, r);
          }
        }
      }
    }
    return null;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    drag.feed(input);
    final pr = proj;
    if (pr != null) {
      pr.vy += kG;
      for (var sub = 0; sub < 3; sub++) {
        pr.x += pr.vx / 3;
        pr.y += pr.vy / 3;
        if (pr.y >= kGroundY || pr.x > kWorldW + 40 || pr.x < -40) {
          proj = null;
          settleT = 30;
          return;
        }
        final c = ((pr.x - 480) / kCell).floor();
        final r = ((kGroundY - pr.y) / kCell).floor();
        if (c >= 0 && c < kGridCols && r >= 0 && r < kGridRows && grid[c][r] != 0) {
          final v = grid[c][r];
          if (v == 9 && dist(pr.x, pr.y, colX(c), rowY(r)) >= kCell * 0.48) continue;
          proj = null;
          boomAt = ticks;
          boomX = pr.x;
          boomY = pr.y;
          if (v == 9) {
            popped++;
            score += 50;
            grid[c][r] = 0;
            lastEvent = 2;
          } else if (v == 2) {
            grid[c][r] = 3;
            lastEvent = 4;
          } else {
            grid[c][r] = 0;
            score += 5;
            lastEvent = 4;
          }
          _settle();
          settleT = 30;
          return;
        }
      }
      return;
    }
    if (settleT > 0) {
      settleT--;
      if (settleT == 0) {
        if (creatures == 0) {
          cleared++;
          score += 100 + shotsLeft * 30;
          lastEvent = 5;
          if (goalN > 0 && cleared >= goalN) {
            win();
            return;
          }
          _build();
        } else if (shotsLeft <= 0) {
          lastEvent = 3;
          hit();
          if (over) return;
          _restore();
        }
      }
      return;
    }
    if (drag.active) {
      final dx = drag.sx - drag.x, dy = drag.sy - drag.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 10) {
        aimA = math.atan2(dy, dx);
        aimP = clampD(len / 360, 0.05, 1);
      }
    } else if (drag.released && dist(drag.sx, drag.sy, drag.x, drag.y) > 30 && shotsLeft > 0) {
      launch(aimA, aimP);
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : cleared / goalN;
  @override
  String get goalText => goalN == 0 ? '$cleared' : '$cleared/$goalN';
  @override
  Map<String, int> get stats => {'castles_cleared': cleared, 'creatures_popped': popped, 'shots_fired': shots};
  @override
  int get stars => lifeStars(this, 3);
}

class _SlingBot {
  int step = 0;
  double ex = 0, ey = 0;
}

final _slingBots = Expando<_SlingBot>();

ArcadeInput slingBot(ArcadeSim sim) {
  final s = sim as SlingSim;
  final st = _slingBots[s] ??= _SlingBot();
  if (st.step == 1) {
    st.step = 2;
    return holdAt(st.ex, st.ey);
  }
  if (st.step == 2) {
    st.step = 0;
    return ArcadeInput.idle;
  }
  if (s.proj != null || s.settleT > 0 || s.shotsLeft <= 0) return ArcadeInput.idle;
  // 1) Yaratığa doğrudan isabet; 2) yaratığın altındaki bloğu kır (düşürür);
  // 3) önündeki kalkanı kır.
  double? bestA, bestP;
  var bestScore = -1;
  for (var a = -1.45; a < 0.1; a += 0.02) {
    for (var p = 0.1; p <= 1.0; p += 0.025) {
      final sp = 12 + p * 22;
      final h = SlingSim.trace(s.grid, kSlingX, kSlingY, math.cos(a) * sp, math.sin(a) * sp);
      if (h == null) continue;
      final (c, r) = h;
      final v = s.grid[c][r];
      var sc = 0;
      if (v == 9) {
        sc = 100;
      } else {
        // Bu bloğun üstünde (aynı kolonda) yaratık var mı?
        final above = [for (var k = r + 1; k < kGridRows; k++) s.grid[c][k]];
        final idx = above.indexOf(9);
        if (idx >= 0 && v == 1) sc = 60 - idx * 5;
        if (idx >= 0 && v >= 2) sc = 30;
        if (idx < 0 && c + 1 < kGridCols && s.grid[c + 1].contains(9)) sc = 20;
        if (sc == 0) sc = 1;
      }
      if (sc > bestScore) {
        bestScore = sc;
        bestA = a;
        bestP = p;
      }
    }
  }
  if (bestA == null || bestP == null) return ArcadeInput.idle;
  final len = bestP * 360;
  st
    ..ex = 500 - math.cos(bestA) * len
    ..ey = 800 - math.sin(bestA) * len
    ..step = 1;
  return holdAt(500, 800);
}

void paintSling(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SlingSim;
  paintSky(c, const Color(0xFF8ECAE6), const Color(0xFFE0FBFC));
  final cloud = Paint()..color = Colors.white70;
  for (var i = 0; i < 4; i++) {
    c.drawOval(Rect.fromLTWH(60.0 + i * 240, 180.0 + (i % 2) * 90, 220, 70), cloud);
  }
  c.drawRect(const Rect.fromLTWH(0, kGroundY, kWorldW, kWorldH - kGroundY), Paint()..color = const Color(0xFF7CB518));
  c.drawRect(const Rect.fromLTWH(0, kGroundY + 30, kWorldW, kWorldH - kGroundY), Paint()..color = const Color(0xFF8B5E34));
  for (var col = 0; col < kGridCols; col++) {
    for (var r = 0; r < kGridRows; r++) {
      final v = s.grid[col][r];
      if (v == 0) continue;
      final rect = Rect.fromCenter(center: Offset(SlingSim.colX(col), SlingSim.rowY(r)), width: kCell - 4, height: kCell - 4);
      if (v == 9) {
        paintBall(c, rect.center, kCell * 0.44, const Color(0xFF80ED99));
        for (final ex in [-9.0, 9.0]) {
          c.drawCircle(rect.center + Offset(ex, -6), 7, Paint()..color = Colors.white);
          c.drawCircle(rect.center + Offset(ex + 2, -6), 3.5, Paint()..color = Colors.black);
        }
        c.drawArc(Rect.fromCenter(center: rect.center + const Offset(0, 6), width: 20, height: 12), 0, math.pi, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
      } else {
        paintBox(c, rect, v == 1 ? const Color(0xFFD4A373) : const Color(0xFF8D99AE), radius: 6, shade: false);
        if (v == 3) {
          c.drawLine(rect.topLeft + const Offset(12, 10), rect.center, Paint()
            ..strokeWidth = 3
            ..color = Colors.black45);
          c.drawLine(rect.center, rect.bottomRight - const Offset(14, 8), Paint()
            ..strokeWidth = 3
            ..color = Colors.black45);
        }
      }
    }
  }
  // sapan
  final wood = Paint()
    ..color = const Color(0xFF6F4518)
    ..strokeWidth = 16
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(kSlingX, kGroundY), const Offset(kSlingX, kSlingY + 40), wood);
  c.drawLine(const Offset(kSlingX, kSlingY + 40), const Offset(kSlingX - 30, kSlingY - 20), wood);
  c.drawLine(const Offset(kSlingX, kSlingY + 40), const Offset(kSlingX + 30, kSlingY - 20), wood);
  var stone = const Offset(kSlingX, kSlingY);
  if (s.drag.active && s.proj == null) {
    stone = Offset(kSlingX - math.cos(s.aimA) * s.aimP * 120, kSlingY - math.sin(s.aimA) * s.aimP * 120);
    final sp = 12 + s.aimP * 22;
    var x = kSlingX, y = kSlingY, vx = math.cos(s.aimA) * sp, vy = math.sin(s.aimA) * sp;
    for (var k = 0; k < 14; k++) {
      for (var j = 0; j < 3; j++) {
        vy += kG;
        x += vx;
        y += vy;
      }
      c.drawCircle(Offset(x, y), 7 - k * 0.3, Paint()..color = Colors.white70);
    }
  }
  final band = Paint()
    ..color = const Color(0xFF3D2B1F)
    ..strokeWidth = 7;
  c.drawLine(const Offset(kSlingX - 30, kSlingY - 20), stone, band);
  c.drawLine(const Offset(kSlingX + 30, kSlingY - 20), stone, band);
  final pr = s.proj;
  if (pr != null) {
    paintBall(c, Offset(pr.x, pr.y), 22, p.piece(0));
  } else if (s.shotsLeft > 0) {
    paintBall(c, stone, 22, p.piece(0));
  }
  for (var i = 0; i < s.shotsLeft - (s.proj == null ? 1 : 0); i++) {
    paintBall(c, Offset(70, kGroundY - 26 - i * 48.0), 20, p.piece(0));
  }
  final age = (s.ticks - s.boomAt) / 25;
  if (age >= 0 && age < 1) paintBurst(c, Offset(s.boomX, s.boomY), age, const Color(0xFFFFB703));
  paintText(c, '${s.creatures}', const Offset(900, 120), 56, Colors.black38);
}

Sfx? slingSound(ArcadeSim sim) => switch ((sim as SlingSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.lose,
      4 => Sfx.clear,
      5 => Sfx.win,
      _ => null,
    };

KitRules slingRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('castles_cleared', 'Yıkılan kale', 'Castles cleared', scale: 50),
        GameStat('creatures_popped', 'Düşen yaratık', 'Creatures popped', scale: 200),
        GameStat('shots_fired', 'Atış', 'Shots fired', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('castles_cleared', 'castles_cleared', [3, 6, 12]),
        MissionTemplate('creatures_popped', 'creatures_popped', [10, 20, 40]),
      ],
      make: SlingSim.new,
      botFn: slingBot,
    );
