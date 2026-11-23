import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Topçu düellosu: sırayla atış. Topundan geriye doğru sürükle (sapan gibi):
/// yön ve güç seçilir, bırakınca ateşlenir. Rüzgâr mermiyi iter. Rakip
/// topçu her atışta biraz daha isabetli olur. Rakibi vurursan tur senin.
const double kGrav = 0.35;
const int kCols = 50; // arazi 20 px adım

class Shell {
  double x, y, vx, vy;
  final bool mine;
  Shell(this.x, this.y, this.vx, this.vy, this.mine);
}

class ArtillerySim extends ArcadeSim {
  final ALevel level;
  late List<double> ground;
  double myX = 0, aiX = 0, wind = 0;
  bool myTurn = true;
  Shell? shell;
  int roundsWon = 0, shotsFired = 0, directHits = 0, aiShots = 0, waitT = 40, lastEvent = 0, boomAt = -100;
  double boomX = 0, boomY = 0;
  final DragTracker drag = DragTracker();
  double aimAngle = -0.8, aimPower = 0.6;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;

  ArtillerySim(this.level) : super(level.meta) {
    _newRound();
  }

  double groundAt(double x) {
    final f = clampD(x / 20, 0, kCols - 1.001);
    final i = f.floor();
    return ground[i] * (1 - (f - i)) + ground[i + 1] * (f - i);
  }

  void _newRound() {
    ground = List<double>.filled(kCols + 1, 1200);
    final hill = 300 + rng.nextDouble() * (200 + level.d * 25);
    final hx = 400 + rng.nextDouble() * 200;
    final base = 1250 + rng.nextDouble() * 80;
    for (var i = 0; i <= kCols; i++) {
      final x = i * 20.0;
      ground[i] = base - hill * math.exp(-math.pow((x - hx) / 180, 2)) + math.sin(i * 0.7 + hx) * 18;
    }
    myX = 110 + rng.nextDouble() * 80;
    aiX = 810 + rng.nextDouble() * 80;
    for (final px in [myX, aiX]) {
      final i = (px / 20).round();
      for (var k = i - 2; k <= i + 2; k++) {
        if (k >= 0 && k <= kCols) ground[k] = ground[i];
      }
    }
    wind = level.has('wind') || level.d >= 4 ? (rng.nextDouble() - 0.5) * (0.04 + level.d * 0.006) : 0;
    myTurn = true;
    aiShots = 0;
    shell = null;
    waitT = 40;
  }

  double get myY => groundAt(myX) - 30;
  double get aiY => groundAt(aiX) - 30;

  void fire(bool mine, double angle, double power) {
    final sp = 10 + power * 22;
    final ox = mine ? myX : aiX, oy = (mine ? myY : aiY) - 20;
    shell = Shell(ox, oy, math.cos(angle) * sp, math.sin(angle) * sp, mine);
    if (mine) shotsFired++;
    lastEvent = 1;
  }

  /// Saf mermi simülasyonu: nereye düşer (x, y, kimi vurur: 1 ben, 2 rakip, 0 hiç).
  (double, double, int) simulate(double ox, double oy, double vx, double vy) {
    var x = ox, y = oy;
    for (var k = 0; k < 600; k++) {
      vx += wind;
      vy += kGrav;
      x += vx;
      y += vy;
      if (dist(x, y, aiX, aiY) < 44) return (x, y, 2);
      if (dist(x, y, myX, myY) < 44 && k > 4) return (x, y, 1);
      if (x < -50 || x > kWorldW + 50) return (x, y, 0);
      if (y >= groundAt(x)) return (x, y, 0);
    }
    return (x, y, 0);
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    drag.feed(input);
    final sh = shell;
    if (sh != null) {
      sh.vx += wind;
      sh.vy += kGrav;
      sh.x += sh.vx;
      sh.y += sh.vy;
      var who = 0;
      if (dist(sh.x, sh.y, aiX, aiY) < 44) who = 2;
      if (dist(sh.x, sh.y, myX, myY) < 44 && !(sh.mine && sh.y < myY - 10 && sh.vy < 0)) who = 1;
      final landed = who != 0 || sh.x < -50 || sh.x > kWorldW + 50 || sh.y >= groundAt(sh.x);
      if (landed) {
        shell = null;
        boomX = sh.x;
        boomY = sh.y;
        boomAt = ticks;
        // krater
        for (var i = 0; i <= kCols; i++) {
          final dx = i * 20.0 - sh.x;
          if (dx.abs() < 60) ground[i] = math.max(ground[i], math.min(1550.0, ground[i] + (60 - dx.abs()) * 0.6));
        }
        if (who == 2) {
          roundsWon++;
          if (sh.mine) directHits++;
          score += 100 + math.max(0, 3 - shotsFired) * 20;
          lastEvent = 2;
          if (goalN > 0 && roundsWon >= goalN) {
            win();
            return;
          }
          waitT = 70;
          _pendingRound = true;
          return;
        }
        if (who == 1) {
          lastEvent = 3;
          hit();
          if (over) return;
          waitT = 70;
          _pendingRound = true;
          return;
        }
        lastEvent = 4;
        myTurn = !sh.mine;
        waitT = 40;
      }
      return;
    }
    if (waitT > 0) {
      waitT--;
      if (waitT == 0 && _pendingRound) {
        _pendingRound = false;
        _newRound();
      }
      return;
    }
    if (myTurn) {
      if (drag.active) {
        final dx = drag.sx - drag.x, dy = drag.sy - drag.y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 10) {
          aimAngle = math.atan2(dy, dx);
          aimPower = clampD(len / 400, 0.05, 1);
        }
      } else if (drag.released && dist(drag.sx, drag.sy, drag.x, drag.y) > 30) {
        fire(true, aimAngle, aimPower);
      }
    } else {
      _aiShoot();
    }
  }

  bool _pendingRound = false;

  void _aiShoot() {
    aiShots++;
    // En iyi atışı bulur, sonra hata ekler (her atışta azalır).
    var bestA = -2.3, bestP = 0.6, bestD = 1e9;
    for (var a = -2.9; a < -1.75; a += 0.05) {
      for (var p = 0.2; p <= 1.0; p += 0.04) {
        final sp = 10 + p * 22;
        final (x, y, w) = simulate(aiX, aiY - 20, math.cos(a) * sp, math.sin(a) * sp);
        final d = w == 1 ? 0.0 : dist(x, y, myX, myY);
        if (d < bestD) {
          bestD = d;
          bestA = a;
          bestP = p;
        }
      }
    }
    final err = math.max(0.0, (0.22 - level.d * 0.012) / aiShots);
    final a = bestA + (rng.nextDouble() * 2 - 1) * err;
    final p = clampD(bestP + (rng.nextDouble() * 2 - 1) * err * 1.4 + (aiShots == 1 ? 0.12 : 0), 0.1, 1);
    fire(false, a, p);
  }

  @override
  double get progress => goalN == 0 ? 0 : roundsWon / goalN;
  @override
  String get goalText => goalN == 0 ? '$roundsWon' : '$roundsWon/$goalN';
  @override
  Map<String, int> get stats => {'rounds_won': roundsWon, 'shots_fired': shotsFired, 'direct_hits': directHits};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: açı/güç ızgarasında saf simülasyonla isabetli atışı bulur ve
/// sürükleme hareketi olarak uygular.
class _ArtBot {
  int step = 0;
  double sx = 0, sy = 0, ex = 0, ey = 0;
}

final _artBots = Expando<_ArtBot>();

ArcadeInput artilleryBot(ArcadeSim sim) {
  final s = sim as ArtillerySim;
  final st = _artBots[s] ??= _ArtBot();
  if (st.step == 1) {
    st.step = 2;
    return holdAt(st.ex, st.ey);
  }
  if (st.step == 2) {
    st.step = 0;
    return ArcadeInput.idle;
  }
  if (!s.myTurn || s.shell != null || s.waitT > 0) return ArcadeInput.idle;
  var bestA = -0.8, bestP = 0.6, bestD = 1e9;
  for (var a = -1.4; a < -0.2; a += 0.025) {
    for (var p = 0.15; p <= 1.0; p += 0.02) {
      final sp = 10 + p * 22;
      final (x, y, w) = s.simulate(s.myX, s.myY - 20, math.cos(a) * sp, math.sin(a) * sp);
      final d = w == 2 ? 0.0 : (w == 1 ? 1e6 : dist(x, y, s.aiX, s.aiY));
      if (d < bestD) {
        bestD = d;
        bestA = a;
        bestP = p;
      }
    }
  }
  // Sürükleme: başlangıç (sx,sy), bitiş = başlangıç - yön * uzunluk
  final len = bestP * 400;
  st
    ..sx = 500
    ..sy = 800
    ..ex = 500 - math.cos(bestA) * len
    ..ey = 800 - math.sin(bestA) * len
    ..step = 1;
  return holdAt(st.sx, st.sy);
}

void paintArtillery(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as ArtillerySim;
  paintSky(c, const Color(0xFF90E0EF), const Color(0xFFFFE5D9));
  c.drawCircle(const Offset(160, 220), 70, Paint()..color = const Color(0xFFFFF3B0));
  final path = Path()..moveTo(0, kWorldH);
  for (var i = 0; i <= kCols; i++) {
    path.lineTo(i * 20.0, s.ground[i]);
  }
  path
    ..lineTo(kWorldW, kWorldH)
    ..close();
  c.drawPath(path, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF80B918), Color(0xFF2B9348), Color(0xFF6F4518)], stops: [0, 0.15, 0.5]).createShader(const Rect.fromLTWH(0, 800, kWorldW, 800)));
  void cannon(double x, double y, Color col, double ang) {
    c.save();
    c.translate(x, y - 20);
    c.rotate(ang);
    paintBox(c, const Rect.fromLTWH(0, -10, 70, 20), const Color(0xFF343A40), radius: 8, shade: false);
    c.restore();
    paintBox(c, Rect.fromCenter(center: Offset(x, y), width: 80, height: 40), col, radius: 14);
    c.drawCircle(Offset(x - 22, y + 20), 14, Paint()..color = Colors.black87);
    c.drawCircle(Offset(x + 22, y + 20), 14, Paint()..color = Colors.black87);
  }

  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  cannon(s.myX, s.myY, blink ? Colors.white54 : p.piece(0), s.aimAngle);
  cannon(s.aiX, s.aiY, p.piece(2), -2.3);
  // rüzgâr
  if (s.wind != 0) {
    final w = s.wind * 3000;
    c.drawLine(const Offset(500, 160), Offset(500 + w, 160), Paint()
      ..color = Colors.white
      ..strokeWidth = 8);
    paintText(c, s.wind > 0 ? '›' : '‹', Offset(500 + w, 158), 60, Colors.white);
  }
  // nişan çizgisi
  if (s.myTurn && s.shell == null && s.drag.active) {
    final sp = 10 + s.aimPower * 22;
    var x = s.myX, y = s.myY - 20, vx = math.cos(s.aimAngle) * sp, vy = math.sin(s.aimAngle) * sp;
    for (var k = 0; k < 24; k++) {
      for (var j = 0; j < 3; j++) {
        vx += s.wind;
        vy += kGrav;
        x += vx;
        y += vy;
      }
      c.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white70);
    }
  }
  final sh = s.shell;
  if (sh != null) paintBall(c, Offset(sh.x, sh.y), 14, const Color(0xFF212529));
  final age = (s.ticks - s.boomAt) / 30;
  if (age >= 0 && age < 1) paintBurst(c, Offset(s.boomX, s.boomY), age, const Color(0xFFFF6D00), size: 120);
  paintText(c, s.myTurn ? '▼' : '▽', Offset(s.myTurn ? s.myX : s.aiX, (s.myTurn ? s.myY : s.aiY) - 110), 50, Colors.white);
}

Sfx? artillerySound(ArcadeSim sim) => switch ((sim as ArtillerySim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.win,
      3 => Sfx.lose,
      4 => Sfx.clear,
      _ => null,
    };

KitRules artilleryRules(String id) => KitRules(
      id,
      optionalMechanics: const ['wind'],
      gameStats: const [
        GameStat('rounds_won', 'Kazanılan tur', 'Rounds won', scale: 50),
        GameStat('shots_fired', 'Atış', 'Shots fired', scale: 300),
        GameStat('direct_hits', 'Tam isabet', 'Direct hits', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('rounds_won', 'rounds_won', [3, 6, 12]),
        MissionTemplate('direct_hits', 'direct_hits', [3, 6, 12]),
      ],
      make: ArtillerySim.new,
      botFn: artilleryBot,
    );
