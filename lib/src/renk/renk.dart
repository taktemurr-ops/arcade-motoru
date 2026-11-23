import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Renk geçişi: dokun = top zıplar. Engellerin yalnız topla aynı renkteki
/// kısmından geçilebilir. Renk değiştirici yıldız topun rengini değiştirir.
/// Engeller zamanın saf fonksiyonudur (bot önceden hesaplayabilsin diye).
const double kR = 230, kThick = 34, kBall = 24, kG = 0.7, kJump = -15;

const _cols = [Color(0xFF06D6A0), Color(0xFFFFD166), Color(0xFFEF476F), Color(0xFF8338EC)];

class Obst {
  final int kind; // 0 halka, 1 çubuk, 2 çift halka (iç içe yön zıt)
  final double oy, phase, speed;
  Obst(this.kind, this.oy, this.phase, this.speed);
  double get top => kind == 1 ? oy - kThick / 2 : oy - kR - kThick / 2;
  double get bottom => kind == 1 ? oy + kThick / 2 : oy + kR + kThick / 2;
}

/// Bir geçiş bandı: y konumu ve zamana göre renk.
class Band {
  final Obst o;
  final double y;
  final bool topArc;
  Band(this.o, this.y, this.topArc);

  int colorAt(int t) {
    if (o.kind == 1) {
      final off = o.phase + o.speed * t;
      final v = ((500 - off) % 1000 + 1000) % 1000;
      return (v / 250).floor() % 4;
    }
    final th = o.phase + o.speed * t;
    final a = topArc ? 270.0 : 90.0;
    final v = ((a - th) % 360 + 360) % 360;
    return (v / 90).floor() % 4;
  }
}

class Switcher {
  final double y;
  final int color;
  bool used = false;
  Switcher(this.y, this.color);
}

class ColorSim extends ArcadeSim {
  final ALevel level;
  double y = 0, vy = 0, camTop = -900, best = 0;
  int color = 0, t = 0, passed = 0, switches = 0, jumps = 0, lastEvent = 0;
  final List<Obst> obst = [];
  final List<Band> bands = [];
  final List<Switcher> sws = [];
  late final int goalN = level.target(8, 2);
  double _nextY = -520;

  ColorSim(this.level) : super(level.meta) {
    color = rng.nextInt(4);
    while (obst.length < 6) {
      _add();
    }
  }

  void _add() {
    final kinds = [0, 1, if (level.d >= 4) 0];
    final kind = kinds[rng.nextInt(kinds.length)];
    final sp = kind == 1 ? (2.2 + level.d * 0.35) * (rng.chance(0.5) ? 1 : -1) : (0.9 + level.d * 0.16) * (rng.chance(0.5) ? 1 : -1);
    final half = kind == 1 ? kThick / 2 : kR + kThick / 2;
    final oy = _nextY - half;
    final o = Obst(kind, oy, rng.nextDouble() * 360, sp);
    obst.add(o);
    if (kind == 1) {
      bands.add(Band(o, oy, false));
    } else {
      bands.add(Band(o, oy + kR, false));
      bands.add(Band(o, oy - kR, true));
    }
    // Sonraki engelin altına (bu engelin üstüne) renk değiştirici.
    final swY = o.top - 230;
    sws.add(Switcher(swY, rng.nextInt(4)));
    _nextY = o.top - 520;
  }

  /// Topun bu durumda bir banda çarpıp çarpmadığı (saf).
  static Band? collides(Iterable<Band> bands, double y, int color, int t) {
    for (final b in bands) {
      if ((y - b.y).abs() < kThick / 2 + kBall && b.colorAt(t) != color) return b;
    }
    return null;
  }

  Band? hitBand;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    t++;
    if (input.tap || input.swipe == 0) {
      vy = kJump;
      jumps++;
      lastEvent = 1;
    }
    vy += kG;
    y += vy;
    camTop = math.min(camTop, y - 700);
    for (final s in sws) {
      if (!s.used && y < s.y) {
        s.used = true;
        if (s.color != color) switches++;
        color = s.color;
        lastEvent = 2;
      }
    }
    for (final o in obst) {
      // engelin tamamen üstüne çıkıldı mı?
      if (y + kBall < o.top && !_done.contains(o)) {
        _done.add(o);
        passed++;
        score += 20;
        lastEvent = 4;
        if (goalN > 0 && passed >= goalN) {
          win();
          return;
        }
      }
    }
    final hb = collides(bands, y, color, t);
    if (hb != null) {
      hitBand = hb;
      lastEvent = 3;
      hit();
      if (over) return;
    }
    if (y > camTop + kWorldH + 40) {
      hitBand = null;
      lastEvent = 3;
      hit();
      if (over) return;
    }
    while (obst.length - _done.length < 5) {
      _add();
    }
    if (obst.length > 12) {
      final o = obst.removeAt(0);
      bands.removeWhere((b) => b.o == o);
      _done.remove(o);
    }
    sws.removeWhere((s) => s.used && s.y > y + 2000);
  }

  final Set<Obst> _done = {};

  @override
  void onLifeLost() {
    final hb = hitBand;
    y = hb != null ? hb.y + kThick / 2 + kBall + 230 : camTop + 1100;
    vy = 0;
    hitBand = null;
  }

  @override
  double get progress => goalN == 0 ? 0 : passed / goalN;
  @override
  String get goalText => goalN == 0 ? '$passed' : '$passed/$goalN';
  @override
  Map<String, int> get stats => {'obstacles_passed': passed, 'color_changes': switches, 'jumps': jumps};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: bir sonraki bandın altında bekler; "art arda zıpla" geçişi
/// güvenliyse (saf zaman fonksiyonlarıyla hesaplanır) geçişe başlar ve
/// geçiş bitene kadar aynı politikayı izler.
class _ColorBot {
  Band? commit;
}

final _colorBots = Expando<_ColorBot>();

ArcadeInput colorBot(ArcadeSim sim) {
  final s = sim as ColorSim;
  final st = _colorBots[s] ??= _ColorBot();
  final c = st.commit;
  if (c != null) {
    if (s.y < c.y - kThick / 2 - kBall - 50 || s.y > c.y + 400 || !s.bands.contains(c)) {
      st.commit = null;
    } else {
      return s.vy > 2 ? tapAny : ArcadeInput.idle;
    }
  }
  Band? next;
  for (final b in s.bands) {
    if (b.y < s.y - 10 && (next == null || b.y > next.y)) next = b;
  }
  if (next == null) return s.vy > 0 ? tapAny : ArcadeInput.idle;
  final target = next;
  bool burstSafe() {
    var y = s.y, vy = s.vy, color = s.color;
    final used = <Switcher>{};
    for (var k = 1; k <= 120; k++) {
      final tap = k == 1 ? true : vy > 2;
      if (tap) vy = kJump;
      vy += kG;
      y += vy;
      for (final w in s.sws) {
        if (!w.used && !used.contains(w) && y < w.y) {
          used.add(w);
          color = w.color;
        }
      }
      if (ColorSim.collides(s.bands, y, color, s.t + k) != null) return false;
      if (y < target.y - kThick / 2 - kBall - 50) return true;
    }
    return false;
  }

  final hoverY = target.y + kThick / 2 + kBall + 210;
  if (s.vy > 0 && s.y < hoverY + 120 && s.shield == 0 && burstSafe()) {
    st.commit = target;
    return tapAny;
  }
  if (s.y > hoverY && s.vy > 0) return tapAny;
  return ArcadeInput.idle;
}

void paintColor(Canvas c, ArcadeSim sim, ArcadePalette p, double tt) {
  final s = sim as ColorSim;
  paintSky(c, const Color(0xFF1B1B2F), const Color(0xFF162447));
  c.save();
  c.translate(0, -s.camTop);
  for (final o in s.obst) {
    if (o.bottom < s.camTop - 50 || o.top > s.camTop + kWorldH + 50) continue;
    if (o.kind == 1) {
      final off = ((o.phase + o.speed * s.t) % 1000 + 1000) % 1000;
      for (var k = -4; k < 5; k++) {
        final x = off + k * 250;
        if (x + 250 < 0 || x > kWorldW) continue;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 3, o.oy - kThick / 2, 244, kThick), const Radius.circular(17)), Paint()..color = _cols[(k % 4 + 4) % 4]);
      }
    } else {
      final th = o.phase + o.speed * s.t;
      final rect = Rect.fromCircle(center: Offset(500, o.oy), radius: kR);
      for (var q = 0; q < 4; q++) {
        c.drawArc(rect, (th + q * 90 + 1.5) * math.pi / 180, (87) * math.pi / 180, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kThick
          ..strokeCap = StrokeCap.round
          ..color = _cols[q]);
      }
    }
  }
  for (final w in s.sws) {
    if (w.used) continue;
    final o = Offset(500, w.y);
    for (var q = 0; q < 4; q++) {
      c.drawArc(Rect.fromCircle(center: o, radius: 30), (q * 90 + s.t * 2) * math.pi / 180, math.pi / 2, true, Paint()..color = _cols[q]);
    }
  }
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBall(c, Offset(500, s.y), kBall, blink ? Colors.white38 : _cols[s.color]);
  c.restore();
}

Sfx? colorSound(ArcadeSim sim) => switch ((sim as ColorSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.unlock,
      3 => Sfx.error,
      4 => Sfx.place,
      _ => null,
    };

KitRules colorRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('obstacles_passed', 'Geçilen engel', 'Obstacles passed', scale: 200),
        GameStat('color_changes', 'Renk değişimi', 'Color changes', scale: 100),
        GameStat('jumps', 'Zıplama', 'Jumps', scale: 1000),
      ],
      missionTemplates: const [
        MissionTemplate('obstacles_passed', 'obstacles_passed', [15, 30, 60]),
        MissionTemplate('color_changes', 'color_changes', [5, 10, 20]),
      ],
      make: ColorSim.new,
      botFn: colorBot,
    );
