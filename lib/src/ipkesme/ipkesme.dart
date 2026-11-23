import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// İp kesme: şeker iplere asılı sallanır. Parmağını ipin üstünden
/// kaydırarak ipi kes; şeker uçup aşağıdaki aç dostumuzun ağzına düşmeli.
/// Yoldaki yıldızları toplamak puan getirir. Şeker ekrandan çıkarsa can gider.
const double kGrav = 0.45, kCandyR = 30, kMouthW = 150;

class Rope {
  final double ax, ay, len;
  bool cut = false;
  Rope(this.ax, this.ay, this.len);
}

class CandyState {
  double x, y, px, py;
  CandyState(this.x, this.y, this.px, this.py);
  CandyState copy() => CandyState(x, y, px, py);
}

/// Saf adım: şekeri bir tik ilerlet.
void stepCandy(CandyState s, List<Rope> ropes) {
  final vx = (s.x - s.px) * 0.999, vy = (s.y - s.py) * 0.999;
  s.px = s.x;
  s.py = s.y;
  s.x += vx;
  s.y += vy + kGrav;
  for (var it = 0; it < 3; it++) {
    for (final r in ropes) {
      if (r.cut) continue;
      final dx = s.x - r.ax, dy = s.y - r.ay;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > r.len) {
        s.x = r.ax + dx / d * r.len;
        s.y = r.ay + dy / d * r.len;
      }
    }
  }
}

class Star {
  final double x, y;
  bool got = false;
  Star(this.x, this.y);
}

class RopeSim extends ArcadeSim {
  final ALevel level;
  final List<Rope> ropes = [];
  final List<Star> starsList = [];
  late CandyState candy;
  late CandyState _start;
  double mouthX = 500, mouthY = 1350;
  int solved = 0, cuts = 0, starsGot = 0, lastEvent = 0, doneAt = -1;
  double lx = -1, ly = -1;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;

  RopeSim(this.level) : super(level.meta) {
    _newPuzzle();
  }

  void _newPuzzle() {
    for (var attempt = 0; attempt < 60; attempt++) {
      if (_tryBuild()) return;
    }
    // Basit yedek: dikey ip, ağız tam altında.
    ropes
      ..clear()
      ..add(Rope(500, 260, 320));
    candy = CandyState(500, 580, 500, 580);
    _start = candy.copy();
    mouthX = 500;
    mouthY = 1350;
    starsList
      ..clear()
      ..add(Star(500, 900));
  }

  bool _tryBuild() {
    ropes.clear();
    starsList.clear();
    final ax = 260 + rng.nextDouble() * 480, ay = 220 + rng.nextDouble() * 160;
    final len = 260 + rng.nextDouble() * 200;
    final side = rng.chance(0.5) ? 1.0 : -1.0;
    final th = (0.5 + rng.nextDouble() * 0.6) * side; // dikeyden açı
    final cx = ax + math.sin(th) * len, cy = ay + math.cos(th) * len;
    if (cx < 80 || cx > 920) return false;
    ropes.add(Rope(ax, ay, len));
    // Tutucu ip(ler): şekeri başlangıç noktasında tutar.
    final extra = 1 + (level.d >= 5 ? 1 : 0);
    for (var k = 0; k < extra; k++) {
      final hx = clampD(cx + side * (120 + rng.nextDouble() * 200), 60, 940);
      final hy = cy - 150 - rng.nextDouble() * 200;
      ropes.add(Rope(hx, hy, dist(hx, hy, cx, cy)));
    }
    // Kesim anını seç: tutucular t=0'da kesilir, ana ip tr'de.
    final sim = CandyState(cx, cy, cx, cy);
    final main = [Rope(ax, ay, len)];
    final path = <Offset>[];
    for (var t = 0; t < 400; t++) {
      stepCandy(sim, main);
      path.add(Offset(sim.x, sim.y));
      if (t < 30 || !rng.chance(0.08)) continue;
      // Bu andan serbest uçuş
      final f = sim.copy();
      final flight = <Offset>[];
      for (var k = 0; k < 300; k++) {
        stepCandy(f, const []);
        flight.add(Offset(f.x, f.y));
        if (f.y > 1150 && f.y - f.py > 0 && f.y >= 1200 + rng.nextDouble() * 150) {
          if (f.x < 120 || f.x > 880) return false;
          mouthX = f.x;
          mouthY = f.y + 40;
          // yıldızlar: biri salınımda, ikisi uçuşta
          starsList.add(Star(path[path.length * 2 ~/ 3].dx, path[path.length * 2 ~/ 3].dy));
          starsList.add(Star(flight[flight.length ~/ 3].dx, flight[flight.length ~/ 3].dy));
          starsList.add(Star(flight[flight.length * 2 ~/ 3].dx, flight[flight.length * 2 ~/ 3].dy));
          candy = CandyState(cx, cy, cx, cy);
          _start = candy.copy();
          return true;
        }
        if (f.x < -60 || f.x > kWorldW + 60) break;
      }
    }
    return false;
  }

  void _resetCandy() {
    for (final r in ropes) {
      r.cut = false;
    }
    for (final s in starsList) {
      s.got = false;
    }
    candy = _start.copy();
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 50) {
        doneAt = -1;
        _newPuzzle();
      }
      return;
    }
    // Kesme
    if (input.down && input.hasPointer) {
      if (lx >= 0 && dist(lx, ly, input.x, input.y) > 6) {
        for (final r in ropes) {
          if (!r.cut && _segX(lx, ly, input.x, input.y, r.ax, r.ay, candy.x, candy.y)) {
            r.cut = true;
            cuts++;
            lastEvent = 1;
          }
        }
      }
      lx = input.x;
      ly = input.y;
    } else {
      lx = ly = -1;
    }
    stepCandy(candy, ropes);
    for (final s in starsList) {
      if (!s.got && dist(s.x, s.y, candy.x, candy.y) < 56) {
        s.got = true;
        starsGot++;
        score += 30;
        lastEvent = 2;
      }
    }
    final vy = candy.y - candy.py;
    if (vy > 0 && (candy.x - mouthX).abs() < kMouthW / 2 && candy.y > mouthY - 50 && candy.y < mouthY + 20) {
      solved++;
      score += 100;
      lastEvent = 4;
      doneAt = ticks;
      if (goalN > 0 && solved >= goalN) win();
      return;
    }
    if (candy.y > kWorldH + 60 || candy.x < -80 || candy.x > kWorldW + 80) {
      lastEvent = 3;
      hit();
      if (!over) _resetCandy();
    }
  }

  static bool _segX(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
    double cross(double ox, double oy, double px, double py, double qx, double qy) => (px - ox) * (qy - oy) - (py - oy) * (qx - ox);
    final d1 = cross(cx, cy, dx, dy, ax, ay), d2 = cross(cx, cy, dx, dy, bx, by);
    final d3 = cross(ax, ay, bx, by, cx, cy), d4 = cross(ax, ay, bx, by, dx, dy);
    return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
  }

  @override
  double get progress => goalN == 0 ? 0 : solved / goalN;
  @override
  String get goalText => goalN == 0 ? '$solved' : '$solved/$goalN';
  @override
  Map<String, int> get stats => {'candies_fed': solved, 'ropes_cut': cuts, 'stars_collected': starsGot};
  @override
  int get stars => lifeStars(this, 3);
}

class _RopeBot {
  int step = 0;
  double x2 = 0, y2 = 0;
}

final _ropeBots = Expando<_RopeBot>();

/// Bot: önce tutucu ipleri keser; sonra ana ipi, kesimden sonraki serbest
/// uçuş ağza düşecekse keser (kesim 2 tik sürer, hesap buna göre).
ArcadeInput ropeBot(ArcadeSim sim) {
  final s = sim as RopeSim;
  final st = _ropeBots[s] ??= _RopeBot();
  if (st.step == 1) {
    st.step = 2;
    return holdAt(st.x2, st.y2);
  }
  if (st.step == 2) {
    st.step = 0;
    return ArcadeInput.idle;
  }
  if (s.doneAt >= 0) return ArcadeInput.idle;
  final alive = [for (final r in s.ropes) if (!r.cut) r];
  if (alive.isEmpty) return ArcadeInput.idle;
  Rope target;
  if (alive.length > 1) {
    target = alive.last;
  } else {
    target = alive.first;
    // İki tik sonra kesilirse (kesim ikinci tikte; o tik ip hâlâ etkin değil)
    final f = s.candy.copy();
    stepCandy(f, alive);
    var ok = false;
    for (var k = 0; k < 400; k++) {
      stepCandy(f, const []);
      if (f.y - f.py > 0 && (f.x - s.mouthX).abs() < kMouthW / 2 - 12 && f.y > s.mouthY - 50 && f.y < s.mouthY + 20) {
        ok = true;
        break;
      }
      if (f.y > kWorldH + 60) break;
    }
    if (!ok) return ArcadeInput.idle;
  }
  // İpin ortasından dik bir çizgi.
  final c = s.candy;
  final mx = (target.ax + c.x) / 2, my = (target.ay + c.y) / 2;
  final dx = c.x - target.ax, dy = c.y - target.ay;
  final d = math.max(1.0, math.sqrt(dx * dx + dy * dy));
  final nx = -dy / d * 90, ny = dx / d * 90;
  st
    ..x2 = mx + nx
    ..y2 = my + ny
    ..step = 1;
  return holdAt(mx - nx, my - ny);
}

void paintRope(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as RopeSim;
  paintSky(c, const Color(0xFFFFF1E6), const Color(0xFFFDE2E4));
  paintGrid(c, const Rect.fromLTWH(0, 0, kWorldW, kWorldH), 120, const Color(0x0F000000));
  // ağız (aç dost)
  final m = Offset(s.mouthX, s.mouthY);
  paintBox(c, Rect.fromCenter(center: m + const Offset(0, 70), width: kMouthW + 30, height: 140), const Color(0xFFB08968), radius: 20);
  paintBall(c, m + const Offset(0, 10), 72, const Color(0xFF52B788));
  final open = s.doneAt < 0 && dist(s.candy.x, s.candy.y, s.mouthX, s.mouthY) < 400;
  c.drawOval(Rect.fromCenter(center: m + const Offset(0, 22), width: 70, height: open ? 46 : 12), Paint()..color = const Color(0xFF6A040F));
  for (final ex in [-26.0, 26.0]) {
    c.drawCircle(m + Offset(ex, -22), 14, Paint()..color = Colors.white);
    final lookX = clampD((s.candy.x - s.mouthX) / 100, -5, 5);
    c.drawCircle(m + Offset(ex + lookX, -22), 7, Paint()..color = Colors.black);
  }
  for (final st in s.starsList) {
    if (st.got) continue;
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final a = k / 10 * math.pi * 2 - math.pi / 2 + s.ticks * 0.01;
      final r = k.isEven ? 34.0 : 15.0;
      final o = Offset(st.x + math.cos(a) * r, st.y + math.sin(a) * r);
      k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    path.close();
    c.drawPath(path, Paint()..color = const Color(0xFFFFC300));
  }
  if (s.doneAt < 0) {
    for (final r in s.ropes) {
      if (r.cut) continue;
      final sag = math.max(0.0, r.len - dist(r.ax, r.ay, s.candy.x, s.candy.y)) * 0.4;
      final mid = Offset((r.ax + s.candy.x) / 2, (r.ay + s.candy.y) / 2 + sag);
      c.drawPath(
          Path()
            ..moveTo(r.ax, r.ay)
            ..quadraticBezierTo(mid.dx, mid.dy, s.candy.x, s.candy.y),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..color = const Color(0xFF7F5539));
      c.drawCircle(Offset(r.ax, r.ay), 14, Paint()..color = const Color(0xFF495057));
      c.drawCircle(Offset(r.ax, r.ay), 6, Paint()..color = const Color(0xFFDEE2E6));
    }
    paintBall(c, Offset(s.candy.x, s.candy.y), kCandyR, p.piece(2));
    c.drawArc(Rect.fromCircle(center: Offset(s.candy.x, s.candy.y), radius: kCandyR * 0.7), s.ticks * 0.05, math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white70);
  }
  if (s.lx >= 0) c.drawCircle(Offset(s.lx, s.ly), 10, Paint()..color = Colors.black26);
}

Sfx? ropeSound(ArcadeSim sim) => switch ((sim as RopeSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.lose,
      4 => Sfx.win,
      _ => null,
    };

KitRules ropeRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('candies_fed', 'Doyurulan dost', 'Candies fed', scale: 50),
        GameStat('ropes_cut', 'Kesilen ip', 'Ropes cut', scale: 200),
        GameStat('stars_collected', 'Yıldız', 'Stars', scale: 100),
      ],
      missionTemplates: const [
        MissionTemplate('candies_fed', 'candies_fed', [3, 6, 12]),
        MissionTemplate('stars_collected', 'stars_collected', [5, 10, 20]),
      ],
      make: RopeSim.new,
      botFn: ropeBot,
    );
