import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Yılan arenası: yılanın parmağının yönüne döner. Işık toplarını ye,
/// uza. Başın başka bir yılanın gövdesine değerse ölürsün; rakip senin
/// gövdene çarparsa o ölür ve ışık topuna dönüşür. Hedef boya ulaş.
const double kArena = 1500, kSegR = 18, kSpeed = 5.2;

class Snake {
  final int id;
  double x, y, a;
  final List<Offset> body = []; // baştan kuyruğa
  int len; // nokta sayısı
  bool dead = false;
  int respawn = 0;
  double wantA = 0;
  Snake(this.id, this.x, this.y, this.a, this.len);
}

class Pellet {
  final double x, y;
  final int value, color;
  Pellet(this.x, this.y, this.value, this.color);
}

class SnakeIoSim extends ArcadeSim {
  final ALevel level;
  final List<Snake> snakes = [];
  final List<Pellet> pellets = [];
  int eaten = 0, rivalsBeaten = 0, best = 0, lastEvent = 0;
  late final int goalLen = level.target(60, 10) == 0 ? 0 : 60 + level.d * 10;

  SnakeIoSim(this.level) : super(level.meta) {
    snakes.add(Snake(0, 0, 400, -math.pi / 2, 24));
    final n = 3 + math.min(level.d ~/ 2, 5);
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      snakes.add(Snake(i + 1, math.cos(a) * 900, math.sin(a) * 900 - 300, a + math.pi, 20 + rng.nextInt(10 + level.d * 3)));
    }
    for (final s in snakes) {
      _initBody(s);
    }
    for (var i = 0; i < 260; i++) {
      _pellet();
    }
  }

  Snake get me => snakes.first;
  int get myLen => me.len;

  void _initBody(Snake s) {
    s.body.clear();
    for (var k = 0; k < s.len; k++) {
      s.body.add(Offset(s.x - math.cos(s.a) * k * 5, s.y - math.sin(s.a) * k * 5));
    }
    s.wantA = s.a;
  }

  void _pellet([double? x, double? y, int value = 1]) {
    double px, py;
    if (x == null || y == null) {
      final r = math.sqrt(rng.nextDouble()) * (kArena - 60);
      final a = rng.nextDouble() * math.pi * 2;
      px = math.cos(a) * r;
      py = math.sin(a) * r;
    } else {
      px = x;
      py = y;
    }
    pellets.add(Pellet(px, py, value, rng.nextInt(6)));
  }

  void _kill(Snake s) {
    s.dead = true;
    for (var k = 0; k < s.body.length; k += 4) {
      _pellet(s.body[k].dx + (rng.nextDouble() - 0.5) * 20, s.body[k].dy + (rng.nextDouble() - 0.5) * 20, 2);
    }
    s.respawn = 180;
    if (s.id != 0) {
      rivalsBeaten++;
      score += 50;
      lastEvent = 4;
    }
  }

  /// Bir noktanın, başı hariç herhangi bir yılan gövdesine çarpıp çarpmadığı.
  bool hitsBody(double x, double y, Snake self, {double pad = 0}) {
    for (final o in snakes) {
      if (o.dead) continue;
      final start = o == self ? 12 : 0;
      for (var k = start; k < o.body.length; k += 2) {
        final b = o.body[k];
        if ((b.dx - x).abs() < kSegR * 2 + pad && (b.dy - y).abs() < kSegR * 2 + pad && dist(b.dx, b.dy, x, y) < kSegR * 1.6 + pad) return true;
      }
    }
    return false;
  }

  void _steer(Snake s) {
    // rakip yapay zekâsı: en yakın ışığa git, önü tehlikeliyse kaç
    Pellet? best;
    var bd = 1e9;
    for (final p in pellets) {
      final d = dist(p.x, p.y, s.x, s.y);
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    var want = best == null ? s.a : math.atan2(best.y - s.y, best.x - s.x);
    // saldırgan: oyuncunun önünü kesmeyi dene
    if (level.d >= 5 && s.len > me.len && dist(s.x, s.y, me.x, me.y) < 400) {
      want = math.atan2(me.y + math.sin(me.a) * 120 - s.y, me.x + math.cos(me.a) * 120 - s.x);
    }
    final look = 60 + level.d * 6.0;
    if (hitsBody(s.x + math.cos(want) * look, s.y + math.sin(want) * look, s) ||
        dist(0, 0, s.x + math.cos(want) * look, s.y + math.sin(want) * look) > kArena - 40) {
      for (final dA in [0.6, -0.6, 1.2, -1.2, 1.8, -1.8]) {
        final a = s.a + dA;
        if (!hitsBody(s.x + math.cos(a) * look, s.y + math.sin(a) * look, s) && dist(0, 0, s.x + math.cos(a) * look, s.y + math.sin(a) * look) < kArena - 40) {
          want = a;
          break;
        }
      }
    }
    s.wantA = want;
  }

  void _move(Snake s, double speed) {
    var d = s.wantA - s.a;
    while (d > math.pi) {
      d -= math.pi * 2;
    }
    while (d < -math.pi) {
      d += math.pi * 2;
    }
    s.a += clampD(d, -0.12, 0.12);
    s.x += math.cos(s.a) * speed;
    s.y += math.sin(s.a) * speed;
    s.body.insert(0, Offset(s.x, s.y));
    while (s.body.length > s.len) {
      s.body.removeLast();
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      // ekran merkezine göre yön (kamera başa kilitli)
      me.wantA = math.atan2(input.y - 800, input.x - 500);
    } else if (input.dirX != 0 || input.dirY != 0) {
      me.wantA = math.atan2(input.dirY.toDouble(), input.dirX.toDouble());
    }
    for (final s in snakes) {
      if (s.dead) {
        if (s.id != 0 && --s.respawn <= 0) {
          final a = rng.nextDouble() * math.pi * 2;
          s
            ..x = math.cos(a) * (kArena - 200)
            ..y = math.sin(a) * (kArena - 200)
            ..a = a + math.pi
            ..len = 20 + rng.nextInt(20)
            ..dead = false;
          if (dist(s.x, s.y, me.x, me.y) > 500) {
            _initBody(s);
          } else {
            s.dead = true;
            s.respawn = 30;
          }
        }
        continue;
      }
      if (s.id != 0 && ticks % 3 == s.id % 3) _steer(s);
      _move(s, s.id == 0 ? kSpeed : kSpeed * (0.8 + level.d * 0.025));
    }
    // yeme
    for (final s in snakes) {
      if (s.dead) continue;
      pellets.removeWhere((p) {
        if ((p.x - s.x).abs() < 34 && (p.y - s.y).abs() < 34) {
          s.len += p.value;
          if (s.id == 0) {
            eaten++;
            score += p.value;
            lastEvent = 1;
          }
          return true;
        }
        return false;
      });
    }
    while (pellets.length < 240) {
      _pellet();
    }
    // çarpışmalar
    for (final s in snakes) {
      if (s.dead) continue;
      final out = dist(0, 0, s.x, s.y) > kArena;
      if (out || hitsBody(s.x, s.y, s)) {
        if (s.id == 0) {
          lastEvent = 3;
          hit();
          if (over) return;
        } else {
          _kill(s);
        }
      }
    }
    best = math.max(best, me.len);
    if (goalLen > 0 && me.len >= goalLen) win();
  }

  @override
  void onLifeLost() {
    // Kayıp: boyun yarısı; güvenli yere taşın.
    me.len = math.max(20, me.len * 2 ~/ 3);
    var bx = 0.0, by = 0.0, bestClear = -1.0;
    for (var k = 0; k < 24; k++) {
      final a = k / 24 * math.pi * 2;
      final r = (k % 3 + 1) * 350.0;
      final x = math.cos(a) * r, y = math.sin(a) * r;
      var clear = 1e9;
      for (final o in snakes.skip(1)) {
        if (o.dead) continue;
        for (final b in o.body) {
          clear = math.min(clear, dist(b.dx, b.dy, x, y));
        }
      }
      if (clear > bestClear) {
        bestClear = clear;
        bx = x;
        by = y;
      }
    }
    me
      ..x = bx
      ..y = by;
    _initBody(me);
  }

  @override
  double get progress => goalLen == 0 ? 0 : me.len / goalLen;
  @override
  String get goalText => goalLen == 0 ? '${me.len}' : '${me.len}/$goalLen';
  @override
  Map<String, int> get stats => {'orbs_eaten': eaten, 'rivals_beaten': rivalsBeaten, 'best_length': best};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: 13 aday yönü 20 adım ileriye doğru tarar; çarpmayan yönler
/// arasında ışığa en yakın olanı seçer.
ArcadeInput snakeIoBot(ArcadeSim sim) {
  final s = sim as SnakeIoSim;
  final me = s.me;
  Pellet? best;
  var bd = 1e9;
  for (final p in s.pellets) {
    final d = dist(p.x, p.y, me.x, me.y) - p.value * 30;
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  final goalA = best == null ? me.a : math.atan2(best.y - me.y, best.x - me.x);
  var bestA = me.a, bestScore = -1e9;
  for (var k = -6; k <= 6; k++) {
    final a = me.a + k * 0.28;
    var ok = true;
    var x = me.x, y = me.y, aa = me.a;
    for (var step = 1; step <= 24 && ok; step++) {
      var d = a - aa;
      while (d > math.pi) {
        d -= math.pi * 2;
      }
      while (d < -math.pi) {
        d += math.pi * 2;
      }
      aa += clampD(d, -0.12, 0.12);
      x += math.cos(aa) * kSpeed;
      y += math.sin(aa) * kSpeed;
      if (step % 3 == 0 && (s.hitsBody(x, y, me, pad: 14) || dist(0, 0, x, y) > kArena - 60)) ok = false;
    }
    if (!ok) continue;
    var diff = (a - goalA) % (math.pi * 2);
    if (diff > math.pi) diff = math.pi * 2 - diff;
    if (diff < 0) diff = -diff;
    // diğer yılanların başından uzak dur
    var near = 0.0;
    for (final o in s.snakes.skip(1)) {
      if (o.dead) continue;
      final dd = dist(o.x, o.y, x, y);
      if (dd < 200) near += (200 - dd) * 0.02;
    }
    final sc = -diff - near - (k.abs() * 0.01);
    if (sc > bestScore) {
      bestScore = sc;
      bestA = a;
    }
  }
  return holdAt(500 + math.cos(bestA) * 300, 800 + math.sin(bestA) * 300);
}

void paintSnakeIo(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SnakeIoSim;
  paintSky(c, const Color(0xFF14213D), const Color(0xFF000814));
  c.save();
  c.translate(500 - s.me.x, 800 - s.me.y);
  // arena zemini
  c.drawCircle(Offset.zero, kArena, Paint()..color = const Color(0xFF1B263B));
  final hex = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = Colors.white10;
  final gx0 = ((s.me.x - 700) / 80).floor() * 80.0, gy0 = ((s.me.y - 900) / 80).floor() * 80.0;
  for (var gx = gx0; gx < s.me.x + 700; gx += 80) {
    for (var gy = gy0; gy < s.me.y + 900; gy += 80) {
      if (gx * gx + gy * gy < kArena * kArena) c.drawCircle(Offset(gx, gy), 30, hex);
    }
  }
  c.drawCircle(Offset.zero, kArena, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 24
    ..color = const Color(0xFFE63946));
  for (final pl in s.pellets) {
    if ((pl.x - s.me.x).abs() > 600 || (pl.y - s.me.y).abs() > 900) continue;
    final col = p.piece(pl.color);
    c.drawCircle(Offset(pl.x, pl.y), 8.0 + pl.value * 4, Paint()..color = col.withValues(alpha: 0.35));
    c.drawCircle(Offset(pl.x, pl.y), 5.0 + pl.value * 2, Paint()..color = col);
  }
  final cols = [p.piece(0), const Color(0xFFF77F00), const Color(0xFF9D4EDD), const Color(0xFF52B788), const Color(0xFFE63946), const Color(0xFF4CC9F0), const Color(0xFFFFD166), const Color(0xFFB5838D), const Color(0xFF06D6A0)];
  for (final sn in s.snakes.reversed) {
    if (sn.dead) continue;
    final col = cols[sn.id % cols.length];
    final blink = sn.id == 0 && s.shield > 0 && (s.ticks ~/ 5).isOdd;
    for (var k = sn.body.length - 1; k >= 0; k -= 2) {
      final b = sn.body[k];
      if ((b.dx - s.me.x).abs() > 600 || (b.dy - s.me.y).abs() > 900) continue;
      c.drawCircle(b, kSegR, Paint()..color = blink ? Colors.white38 : (k ~/ 6).isEven ? col : Color.lerp(col, Colors.black, 0.2)!);
    }
    final h = Offset(sn.x, sn.y);
    for (final side in [-1.0, 1.0]) {
      final e = h + Offset(math.cos(sn.a + side * 0.6), math.sin(sn.a + side * 0.6)) * 11;
      c.drawCircle(e, 7, Paint()..color = Colors.white);
      c.drawCircle(e + Offset(math.cos(sn.a), math.sin(sn.a)) * 3, 3.5, Paint()..color = Colors.black);
    }
  }
  c.restore();
  paintText(c, '${s.me.len}', const Offset(500, 90), 60, Colors.white70);
}

Sfx? snakeIoSound(ArcadeSim sim) => switch ((sim as SnakeIoSim).lastEvent) {
      1 => null,
      3 => Sfx.lose,
      4 => Sfx.combo,
      _ => null,
    };

KitRules snakeIoRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('orbs_eaten', 'Yenilen ışık', 'Orbs eaten', scale: 2000),
        GameStat('rivals_beaten', 'Yenilen rakip', 'Rivals beaten', scale: 50),
        GameStat('best_length', 'En uzun boy', 'Best length', scale: 10),
      ],
      missionTemplates: const [
        MissionTemplate('orbs_eaten', 'orbs_eaten', [100, 200, 400]),
        MissionTemplate('rivals_beaten', 'rivals_beaten', [1, 3, 6]),
      ],
      make: SnakeIoSim.new,
      botFn: snakeIoBot,
    );
