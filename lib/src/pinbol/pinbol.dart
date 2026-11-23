import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Pinbol (langırt makinesi): ekranın sol yarısına dokun = sol palet,
/// sağ yarısı = sağ palet. Tamponlar ve düşen hedefler puan verir; dört
/// hedefin hepsini düşürmek çarpanı artırır. Top paletlerin arasından
/// kaçarsa can gider.
const double kBall = 22, kGrav = 0.28, kFlipLen = 150;

class Seg {
  final double ax, ay, bx, by;
  const Seg(this.ax, this.ay, this.bx, this.by);
}

class Bumper {
  final double x, y, r;
  int lit = 0;
  Bumper(this.x, this.y, this.r);
}

class DropTarget {
  final double x, y;
  bool down = false;
  DropTarget(this.x, this.y);
}

class Flipper {
  final double px, py;
  final int side; // -1 sol, 1 sağ
  double a; // açı
  double w = 0;
  Flipper(this.px, this.py, this.side) : a = side < 0 ? 0.5 : math.pi - 0.5;
  double get rest => side < 0 ? 0.5 : math.pi - 0.5;
  double get up => side < 0 ? -0.5 : math.pi + 0.5;
  double get tx => px + math.cos(a) * kFlipLen;
  double get ty => py + math.sin(a) * kFlipLen;
}

const List<Seg> _walls = [
  Seg(40, 1250, 40, 260),
  Seg(40, 260, 120, 140),
  Seg(120, 140, 300, 90),
  Seg(300, 90, 700, 90),
  Seg(700, 90, 880, 140),
  Seg(880, 140, 960, 260),
  Seg(960, 260, 960, 1250),
  Seg(40, 1250, 325, 1395),
  Seg(960, 1250, 675, 1395),
  // sapanlar (paletlerin üstündeki üçgen kenarlar)
  Seg(170, 1080, 280, 1250),
  Seg(830, 1080, 720, 1250),
];

class PinballSim extends ArcadeSim {
  final ALevel level;
  double x = 500, y = 300, vx = 0, vy = 0;
  final Flipper left = Flipper(330, 1400, -1), right = Flipper(670, 1400, 1);
  final List<Bumper> bumpers = [Bumper(340, 420, 52), Bumper(660, 420, 52), Bumper(500, 610, 56)];
  final List<DropTarget> drops = [for (var i = 0; i < 4; i++) DropTarget(320 + i * 120.0, 230)];
  int mult = 1, bumps = 0, dropsHit = 0, flips = 0, lastEvent = 0, respawnIn = 0, ballsLost = 0;
  late final int goal = level.target(3000, 600);

  PinballSim(this.level) : super(level.meta) {
    _launch();
  }

  void _launch() {
    x = 500 + (rng.nextDouble() - 0.5) * 200;
    y = 300;
    vx = (rng.nextDouble() - 0.5) * 6;
    vy = 2;
  }

  void _collideSeg(double ax, double ay, double bx, double by, double rest, double svx, double svy) {
    final ex = bx - ax, ey = by - ay;
    final l2 = ex * ex + ey * ey;
    var t = ((x - ax) * ex + (y - ay) * ey) / l2;
    t = clampD(t, 0, 1);
    final cx = ax + ex * t, cy = ay + ey * t;
    final dx = x - cx, dy = y - cy;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d >= kBall || d == 0) return;
    final nx = dx / d, ny = dy / d;
    x = cx + nx * kBall;
    y = cy + ny * kBall;
    final rvx = vx - svx, rvy = vy - svy;
    final vn = rvx * nx + rvy * ny;
    if (vn < 0) {
      vx = rvx - (1 + rest) * vn * nx + svx;
      vy = rvy - (1 + rest) * vn * ny + svy;
    }
  }

  void _flipper(Flipper f, bool pressed) {
    final target = pressed ? f.up : f.rest;
    final old = f.a;
    f.w = moveToward(f.a, target, 0.32) - old;
    if (pressed && f.w != 0 && old == f.rest) {
      flips++;
      lastEvent = 1;
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (respawnIn > 0) {
      respawnIn--;
      if (respawnIn == 0) _launch();
      left.a = left.rest;
      right.a = right.rest;
      left.w = right.w = 0;
      return;
    }
    final l = (input.down && input.hasPointer && input.x < 500) || input.dirX < 0 || input.dirY < 0;
    final r = (input.down && input.hasPointer && input.x >= 500) || input.dirX > 0 || input.dirY < 0;
    _flipper(left, l);
    _flipper(right, r);
    const subs = 4;
    for (var k = 0; k < subs; k++) {
      vy += kGrav / subs;
      x += vx / subs;
      y += vy / subs;
      for (final w in _walls) {
        _collideSeg(w.ax, w.ay, w.bx, w.by, w == _walls[9] || w == _walls[10] ? 1.1 : 0.45, 0, 0);
      }
      for (final f in [left, right]) {
        f.a += f.w / subs;
        // Paletin yüzey hızı: temas noktasında ω × r
        final tx = f.tx, ty = f.ty;
        final ex = tx - f.px, ey = ty - f.py;
        var t = ((x - f.px) * ex + (y - f.py) * ey) / (ex * ex + ey * ey);
        t = clampD(t, 0, 1);
        final rr = t * kFlipLen;
        final svx = -math.sin(f.a) * f.w * rr, svy = math.cos(f.a) * f.w * rr;
        _collideSeg(f.px, f.py, tx, ty, 0.35, svx, svy);
      }
      for (final b in bumpers) {
        final d = dist(x, y, b.x, b.y);
        if (d < b.r + kBall) {
          final nx = (x - b.x) / d, ny = (y - b.y) / d;
          x = b.x + nx * (b.r + kBall);
          y = b.y + ny * (b.r + kBall);
          final sp = math.max(11.0, math.sqrt(vx * vx + vy * vy));
          vx = nx * sp;
          vy = ny * sp;
          b.lit = 10;
          bumps++;
          score += 100 * mult;
          lastEvent = 2;
        }
      }
      for (final dt in drops) {
        if (!dt.down && (x - dt.x).abs() < 50 + kBall && (y - dt.y).abs() < 14 + kBall) {
          dt.down = true;
          vy = vy.abs() + 2;
          dropsHit++;
          score += 250 * mult;
          lastEvent = 4;
          if (drops.every((d) => d.down)) {
            mult = math.min(mult + 1, 5);
            score += 1000;
            for (final d in drops) {
              d.down = false;
            }
          }
        }
      }
    }
    final sp = math.sqrt(vx * vx + vy * vy);
    if (sp > 34) {
      vx *= 34 / sp;
      vy *= 34 / sp;
    }
    for (final b in bumpers) {
      if (b.lit > 0) b.lit--;
    }
    if (goal > 0 && score >= goal) {
      win();
      return;
    }
    if (y > kWorldH + 40 || x < 0 || x > kWorldW) {
      ballsLost++;
      lastEvent = 3;
      respawnIn = 50;
      if (shield == 0) hit();
    }
  }

  @override
  double get progress => goal == 0 ? 0 : score / goal;
  @override
  String get goalText => goal == 0 ? '$score' : '$score/$goal';
  @override
  Map<String, int> get stats => {'bumper_hits': bumps, 'targets_dropped': dropsHit, 'flips': flips};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: top bir paletin üstüne yaklaşınca o paleti kaldırır; top
/// yükseldikten sonra bırakır.
class _PinBot {
  int holdL = 0, holdR = 0;
}

final _pinBots = Expando<_PinBot>();

ArcadeInput pinballBot(ArcadeSim sim) {
  final s = sim as PinballSim;
  final st = _pinBots[s] ??= _PinBot();
  bool near(Flipper f) {
    // Topun 4 tik sonraki konumu paletin üstünde mi?
    final px = s.x + s.vx * 3, py = s.y + s.vy * 3 + 1;
    final ex = math.cos(f.rest) * kFlipLen, ey = math.sin(f.rest) * kFlipLen;
    final t = ((px - f.px) * ex + (py - f.py) * ey) / (kFlipLen * kFlipLen);
    if (t < 0.15 || t > 1.05) return false;
    final cx = f.px + ex * t, cy = f.py + ey * t;
    return dist(px, py, cx, cy) < kBall + 34 && py < cy + 10;
  }

  if (s.respawnIn > 0) {
    st.holdL = st.holdR = 0;
    return ArcadeInput.idle;
  }
  if (st.holdL > 0) st.holdL--;
  if (st.holdR > 0) st.holdR--;
  if (st.holdL == 0 && near(s.left) && s.vy > -2) st.holdL = 12;
  if (st.holdR == 0 && near(s.right) && s.vy > -2) st.holdR = 12;
  if (st.holdL > 0 && st.holdR > 0) return const ArcadeInput(dirY: -1);
  if (st.holdL > 0) return holdAt(200, 1500);
  if (st.holdR > 0) return holdAt(800, 1500);
  return ArcadeInput.idle;
}

void paintPinball(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as PinballSim;
  paintSky(c, const Color(0xFF240046), const Color(0xFF10002B));
  final table = Path()
    ..moveTo(40, 1250)
    ..lineTo(40, 260)
    ..lineTo(120, 140)
    ..lineTo(300, 90)
    ..lineTo(700, 90)
    ..lineTo(880, 140)
    ..lineTo(960, 260)
    ..lineTo(960, 1250)
    ..lineTo(675, 1395)
    ..lineTo(675, kWorldH)
    ..lineTo(325, kWorldH)
    ..lineTo(325, 1395)
    ..close();
  c.drawPath(table, Paint()..shader = const RadialGradient(colors: [Color(0xFF3C096C), Color(0xFF240046)]).createShader(const Rect.fromLTWH(0, 0, kWorldW, kWorldH)));
  paintGrid(c, const Rect.fromLTWH(40, 90, 920, 1300), 80, const Color(0x10FFFFFF));
  final wallPaint = Paint()
    ..color = const Color(0xFFE0AAFF)
    ..strokeWidth = 12
    ..strokeCap = StrokeCap.round;
  for (final w in _walls) {
    c.drawLine(Offset(w.ax, w.ay), Offset(w.bx, w.by), wallPaint);
  }
  for (final tri in [
    [const Offset(170, 1080), const Offset(280, 1250), const Offset(170, 1200)],
    [const Offset(830, 1080), const Offset(720, 1250), const Offset(830, 1200)],
  ]) {
    c.drawPath(Path()..addPolygon(tri, true), Paint()..color = p.piece(3));
  }
  for (final b in s.bumpers) {
    c.drawCircle(Offset(b.x, b.y), b.r + 10, Paint()..color = b.lit > 0 ? Colors.white : const Color(0xFF7B2CBF));
    paintBall(c, Offset(b.x, b.y), b.r, b.lit > 0 ? const Color(0xFFFFD60A) : p.piece(1));
    c.drawCircle(Offset(b.x, b.y), b.r * 0.4, Paint()..color = Colors.white70);
  }
  for (final d in s.drops) {
    paintBox(c, Rect.fromCenter(center: Offset(d.x, d.y), width: 100, height: d.down ? 8 : 28), d.down ? Colors.white24 : const Color(0xFFFF6D00), radius: 6, shade: false);
  }
  for (final f in [s.left, s.right]) {
    final paint = Paint()
      ..color = const Color(0xFFF72585)
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(f.px, f.py), Offset(f.tx, f.ty), paint);
    c.drawCircle(Offset(f.px, f.py), 12, Paint()..color = Colors.white);
  }
  if (s.respawnIn == 0) {
    paintBall(c, Offset(s.x, s.y), kBall, const Color(0xFFDEE2E6));
  }
  paintText(c, '×${s.mult}', const Offset(500, 820), 70, Colors.white24);
}

Sfx? pinballSound(ArcadeSim sim) => switch ((sim as PinballSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.lose,
      4 => Sfx.coin,
      _ => null,
    };

KitRules pinballRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('bumper_hits', 'Tampon vuruşu', 'Bumper hits', scale: 1000),
        GameStat('targets_dropped', 'Düşen hedef', 'Targets dropped', scale: 200),
        GameStat('flips', 'Palet', 'Flips', scale: 1000),
      ],
      missionTemplates: const [
        MissionTemplate('bumper_hits', 'bumper_hits', [50, 100, 200]),
        MissionTemplate('targets_dropped', 'targets_dropped', [8, 16, 32]),
      ],
      make: PinballSim.new,
      botFn: pinballBot,
    );
