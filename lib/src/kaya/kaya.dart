import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kaya düşmesi: mağarada kaydırarak kaz, elmasları topla. Altı boşalan
/// kaya düşer; düşen kaya başına gelirse can gider. Yeterli elmas
/// toplanınca çıkış açılır.
const int kW = 14, kH = 20;
const double kC = 1000 / kW, kTop = 110;
// 0 boş, 1 toprak, 2 duvar, 3 kaya, 4 elmas, 5 çıkış
const int kEmpty = 0, kDirt = 1, kWall = 2, kRock = 3, kGem = 4, kExit = 5;

const _dx = [0, 1, 0, -1], _dy = [-1, 0, 1, 0];

class BoulderSim extends ArcadeSim {
  final ALevel level;
  late List<List<int>> g;
  late List<List<bool>> falling;
  int px = 1, py = 1, moveT = 0, wantDir = -1;
  double fx = 1, fy = 1;
  int gems = 0, need = 0, caves = 0, totalGems = 0, lastEvent = 0, doneAt = -1, exitX = 0, exitY = 0;
  late final int goalN = level.target(2, 0) == 0 ? 0 : 2 + level.d ~/ 3;
  late List<List<int>> _start;

  BoulderSim(this.level) : super(level.meta) {
    _newCave();
  }

  void _newCave() {
    g = List.generate(kW, (x) => List.generate(kH, (y) => x == 0 || y == 0 || x == kW - 1 || y == kH - 1 ? kWall : kDirt));
    final rocks = 0.10 + level.d * 0.012;
    var gemCount = 0;
    for (var x = 1; x < kW - 1; x++) {
      for (var y = 1; y < kH - 1; y++) {
        if (x <= 2 && y <= 2) continue;
        final r = rng.nextDouble();
        if (r < rocks) {
          g[x][y] = kRock;
        } else if (r < rocks + 0.07) {
          g[x][y] = kGem;
          gemCount++;
        } else if (r < rocks + 0.11) {
          g[x][y] = kEmpty;
        } else if (r < rocks + 0.14 && level.d >= 3) {
          g[x][y] = kWall;
        }
      }
    }
    g[1][1] = kEmpty;
    exitX = kW - 2;
    exitY = kH - 2;
    g[exitX][exitY] = kWall; // kapalı çıkış
    need = math.max(3, (gemCount * (0.45 + level.d * 0.02)).round());
    totalGems = gemCount;
    falling = List.generate(kW, (_) => List<bool>.filled(kH, false));
    // Başlangıçta havada duran kayaları yerleştir (fiziği oturt).
    for (var i = 0; i < kH; i++) {
      _physics(settleOnly: true);
    }
    falling = List.generate(kW, (_) => List<bool>.filled(kH, false));
    _start = [for (final col in g) [...col]];
    px = 1;
    py = 1;
    fx = fy = 1;
    gems = 0;
    if (totalGems < need) _newCave();
  }

  void _restart() {
    g = [for (final col in _start) [...col]];
    falling = List.generate(kW, (_) => List<bool>.filled(kH, false));
    px = py = 1;
    fx = fy = 1;
    gems = 0;
  }

  bool get exitOpen => gems >= need;

  /// Kaya/elmas düşüşü: aşağısı boşsa düşer; kaya üstündeyse ve yanı + yan
  /// altı boşsa yuvarlanır.
  void _physics({bool settleOnly = false}) {
    for (var y = kH - 2; y >= 1; y--) {
      for (var x = 1; x < kW - 1; x++) {
        final v = g[x][y];
        if (v != kRock && v != kGem) continue;
        final below = g[x][y + 1];
        final playerBelow = !settleOnly && px == x && py == y + 1;
        if (below == kEmpty && !playerBelow) {
          g[x][y + 1] = v;
          g[x][y] = kEmpty;
          falling[x][y + 1] = true;
          falling[x][y] = false;
          // bir sonraki satırda oyuncu varsa ve düşmeye devam ediyorsa ezer
          continue;
        }
        if (playerBelow && falling[x][y]) {
          // Düşen kaya oyuncunun üstüne geldi.
          falling[x][y] = false;
          if (!settleOnly) _crush();
          continue;
        }
        if (below == kRock || below == kGem) {
          for (final side in [-1, 1]) {
            final sx = x + side;
            if (g[sx][y] == kEmpty && g[sx][y + 1] == kEmpty && !(px == sx && (py == y || py == y + 1))) {
              g[sx][y] = v;
              g[x][y] = kEmpty;
              falling[sx][y] = true;
              falling[x][y] = false;
              break;
            }
          }
        }
        if (g[x][y] == v) falling[x][y] = false;
      }
    }
  }

  bool _crushed = false;
  void _crush() => _crushed = true;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 50) {
        doneAt = -1;
        _newCave();
      }
      return;
    }
    var sw = input.swipe;
    if (sw < 0 && (input.dirX != 0 || input.dirY != 0)) {
      sw = input.dirY < 0 ? 0 : (input.dirX > 0 ? 1 : (input.dirY > 0 ? 2 : 3));
    }
    if (sw >= 0) wantDir = sw;
    if (moveT == 0 && wantDir >= 0) {
      final nx = px + _dx[wantDir], ny = py + _dy[wantDir];
      final v = g[nx][ny];
      if (v == kEmpty || v == kDirt || v == kGem || (v == kExit && exitOpen)) {
        if (v == kGem) {
          gems++;
          score += 20;
          lastEvent = 2;
          if (gems == need) {
            g[exitX][exitY] = kExit;
            lastEvent = 4;
          }
        }
        g[nx][ny] = kEmpty;
        px = nx;
        py = ny;
        moveT = 8;
        if (v == kExit) {
          caves++;
          score += 200 + (gems - need) * 10;
          lastEvent = 5;
          doneAt = ticks;
          if (goalN > 0 && caves >= goalN) win();
          return;
        }
      } else if (v == kRock && _dy[wantDir] == 0 && g[nx + _dx[wantDir]][ny] == kEmpty) {
        // Kayayı yana it.
        g[nx + _dx[wantDir]][ny] = kRock;
        g[nx][ny] = kEmpty;
        px = nx;
        moveT = 12;
      }
      wantDir = -1;
    }
    if (moveT > 0) moveT--;
    fx = moveToward(fx, px.toDouble(), 1 / 8);
    fy = moveToward(fy, py.toDouble(), 1 / 8);
    if (ticks % 6 == 0) {
      _physics();
      if (_crushed) {
        _crushed = false;
        lastEvent = 3;
        hit();
      }
    }
  }

  @override
  void onLifeLost() => _restart();

  @override
  double get progress => goalN == 0 ? 0 : caves / goalN;
  @override
  String get goalText => goalN == 0 ? '$caves' : '$caves/$goalN · ◆$gems/$need';
  @override
  Map<String, int> get stats => {'caves_cleared': caves, 'gems_collected': gems};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: BFS ile en yakın elmasa (açıksa çıkışa) yürür. Üstünde kaya/elmas
/// olan hücreye aşağıdan girmez ve hücrenin üstü doluyken aşağı inmez.
ArcadeInput boulderBot(ArcadeSim sim) {
  final s = sim as BoulderSim;
  if (s.doneAt >= 0 || s.moveT > 0) return ArcadeInput.idle;
  bool heavy(int x, int y) => y >= 0 && (s.g[x][y] == kRock || s.g[x][y] == kGem);
  bool fall(int x, int y) => y >= 0 && s.falling[x][y];
  bool unsafe(int x, int y) {
    // Bu hücrenin üstünde düşmekte olan bir şey var mı?
    if (heavy(x, y - 1) && fall(x, y - 1)) return true;
    if (heavy(x, y - 2) && fall(x, y - 2) && s.g[x][y - 1] == kEmpty) return true;
    return false;
  }

  bool enterable(int x, int y, int dir) {
    final v = s.g[x][y];
    if (!(v == kEmpty || v == kDirt || v == kGem || (v == kExit && s.exitOpen))) return false;
    if (unsafe(x, y)) return false;
    // Üstü kaya olan hücreden aşağı inersek kaya bizi izler.
    if (dir == 2 && heavy(x, y - 2)) return false;
    // Boş hücreye girip altında boşluk yoksa güvenli; üstü kaya ve hücre boş ise kaya bize düşebilir
    if (heavy(x, y - 1) && v == kEmpty) return false;
    return true;
  }

  final goalIsExit = s.exitOpen;
  final seen = <int>{s.px * 100 + s.py};
  final q = <(int, int, int)>[(s.px, s.py, -1)];
  var i = 0;
  int? found;
  while (i < q.length) {
    final (x, y, first) = q[i++];
    final v = s.g[x][y];
    if (first >= 0 && ((goalIsExit && v == kExit) || (!goalIsExit && v == kGem))) {
      found = first;
      break;
    }
    for (var d = 0; d < 4; d++) {
      final nx = x + _dx[d], ny = y + _dy[d];
      if (!seen.add(nx * 100 + ny)) continue;
      if (!enterable(nx, ny, d)) continue;
      q.add((nx, ny, first < 0 ? d : first));
    }
  }
  if (found != null) return ArcadeInput(swipe: found);
  // Yol yoksa: yanındaki kayayı itmeyi dene
  for (final d in [1, 3]) {
    final nx = s.px + _dx[d];
    if (s.g[nx][s.py] == kRock && s.g[nx + _dx[d]][s.py] == kEmpty) return ArcadeInput(swipe: d);
  }
  return ArcadeInput.idle;
}

void paintBoulder(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as BoulderSim;
  paintSky(c, const Color(0xFF212529), const Color(0xFF343A40));
  for (var x = 0; x < kW; x++) {
    for (var y = 0; y < kH; y++) {
      final r = Rect.fromLTWH(x * kC, kTop + y * kC, kC + 0.5, kC + 0.5);
      switch (s.g[x][y]) {
        case kDirt:
          c.drawRect(r, Paint()..color = const Color(0xFF7F5539));
          c.drawCircle(r.center + Offset(((x * 5 + y) % 3 - 1) * 12.0, ((x + y * 7) % 3 - 1) * 12.0), 4, Paint()..color = Colors.black26);
        case kWall:
          paintBox(c, r.deflate(1), const Color(0xFF6C757D), radius: 4, shade: false);
          if (x == s.exitX && y == s.exitY) paintText(c, '⌂', r.center, kC * 0.6, Colors.white38);
        case kRock:
          paintBall(c, r.center, kC * 0.44, const Color(0xFFADB5BD));
        case kGem:
          final path = Path()
            ..moveTo(r.center.dx, r.top + 8)
            ..lineTo(r.right - 10, r.center.dy)
            ..lineTo(r.center.dx, r.bottom - 8)
            ..lineTo(r.left + 10, r.center.dy)
            ..close();
          c.drawPath(path, Paint()..color = const Color(0xFF4CC9F0));
          c.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white70);
        case kExit:
          paintBox(c, r.deflate(4), (s.ticks ~/ 15).isEven ? const Color(0xFFFFC300) : const Color(0xFFFFE066), radius: 8);
          paintText(c, '⇪', r.center, kC * 0.6, Colors.black54);
        default:
          break;
      }
    }
  }
  final o = Offset((s.fx + 0.5) * kC, kTop + (s.fy + 0.5) * kC);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, o, kC * 0.36, blink ? Colors.white54 : p.piece(0));
  c.drawRect(Rect.fromCenter(center: o + const Offset(0, -12), width: kC * 0.5, height: 10), Paint()..color = const Color(0xFFFFC300));
  paintText(c, '◆ ${s.gems}/${s.need}', const Offset(500, 55), 50, s.exitOpen ? const Color(0xFFFFC300) : Colors.white70);
}

Sfx? boulderSound(ArcadeSim sim) => switch ((sim as BoulderSim).lastEvent) {
      2 => Sfx.coin,
      3 => Sfx.lose,
      4 => Sfx.unlock,
      5 => Sfx.win,
      _ => null,
    };

KitRules boulderRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('caves_cleared', 'Geçilen mağara', 'Caves cleared', scale: 50),
        GameStat('gems_collected', 'Toplanan elmas', 'Gems collected', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('caves_cleared', 'caves_cleared', [3, 6, 12]),
        MissionTemplate('gems_collected', 'gems_collected', [20, 40, 80]),
      ],
      make: BoulderSim.new,
      botFn: boulderBot,
    );
