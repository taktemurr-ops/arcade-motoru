import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Yandan görünüşlü koşu–zıplama motoru. İki oyun kullanır:
///  * Platform oyunu: kahraman kendiliğinden koşar; dokun = zıpla (havada
///    bir kez daha). Basılı tutmak yavaşlatır. Düşmanın üstüne in, jeton
///    topla, sona ulaş.
///  * Koş ve ateş et: aynı kontrol + otomatik ateş; düşmanlar ateş eder.
const double kGrav = 0.9, kJump = -19, kPlayerW = 46, kPlayerH = 70, kScreenX = 280;

class Plat {
  final double x, y, w;
  final bool moving;
  final double amp;
  Plat(this.x, this.y, this.w, {this.moving = false, this.amp = 0});
  double yAt(int t) => moving ? y + math.sin(t / 50) * amp : y;
}

class Foe {
  double x, y, vx;
  final double minX, maxX;
  final bool flyer, shooter;
  bool dead = false;
  int cool = 60;
  Foe(this.x, this.y, this.vx, this.minX, this.maxX, {this.flyer = false, this.shooter = false});
}

class Coin {
  final double x, y;
  bool got = false;
  Coin(this.x, this.y);
}

class EShot {
  double x, y;
  final double vx;
  EShot(this.x, this.y, this.vx);
}

class SideSim extends ArcadeSim {
  final ALevel level;
  final bool gun;
  final List<Plat> plats = [];
  final List<Foe> foes = [];
  final List<Coin> coins = [];
  final List<EShot> eshots = [];
  final List<Offset> shots = [];
  final List<Fx> fx = [];
  double x = 100, y = 0, vy = 0, length = 0, checkpoint = 100;
  bool onGround = false;
  int jumpsLeft = 2, stages = 0, coinsGot = 0, stomps = 0, lastEvent = 0, doneAt = -1;
  late final int goalN = level.target(2, 0) == 0 ? 0 : 2 + level.d ~/ 4;

  SideSim(this.level, this.gun) : super(level.meta) {
    _build();
  }

  void _build() {
    plats.clear();
    foes.clear();
    coins.clear();
    eshots.clear();
    shots.clear();
    final endless = goalN == 0;
    length = endless ? 1e9 : 3400 + level.d * 450.0;
    var px = 0.0, py = 1200.0;
    plats.add(Plat(px, py, 700));
    px = 700;
    final limit = endless ? 6000.0 : length;
    while (px < limit) {
      _segment(px, py);
      final last = plats.last;
      px = last.x + last.w;
      py = last.y;
    }
    plats.add(Plat(px + 160, py, 600));
    x = 100;
    y = 1200 - kPlayerH / 2;
    vy = 0;
    checkpoint = 100;
  }

  void _segment(double px, double py) {
    // boşluk (zıplanabilir) + yükseklik farkı
    final gap = 120 + rng.nextDouble() * (110 + level.d * 14);
    final dy = (rng.nextDouble() * 2 - 1) * (90 + level.d * 8);
    final ny = clampD(py + dy, 700, 1350);
    final w = 320 + rng.nextDouble() * 380;
    final moving = level.d >= 4 && rng.chance(0.18);
    final p = Plat(px + gap, ny, w, moving: moving, amp: moving ? 60 : 0);
    plats.add(p);
    for (var k = 0; k < 3; k++) {
      if (rng.chance(0.5)) coins.add(Coin(p.x + 60 + k * (w - 120) / 2, ny - 140));
    }
    if (!moving && w > 380 && rng.chance(0.35 + level.d * 0.04)) {
      final flyer = level.d >= 3 && rng.chance(0.3);
      foes.add(Foe(p.x + w / 2, flyer ? ny - 230 : ny - 30, -(1.2 + level.d * 0.1), p.x + 40, p.x + w - 40,
          flyer: flyer, shooter: gun && rng.chance(0.4)));
    }
  }

  void _extendIfEndless() {
    if (goalN != 0) return;
    while (plats.last.x < x + 3000) {
      final last = plats.last;
      _segment(last.x + last.w, last.y);
    }
    plats.removeWhere((p) => p.x + p.w < x - 1500);
    foes.removeWhere((f) => f.x < x - 1500);
    coins.removeWhere((c) => c.x < x - 1500);
  }

  double get runSpeed => 6.5 + level.d * 0.25;

  /// Oyuncunun altındaki platformun üst yüzeyi (yoksa null).
  Plat? platUnder(double px, double footY) {
    for (final p in plats) {
      if (px + kPlayerW / 2 > p.x && px - kPlayerW / 2 < p.x + p.w) {
        final top = p.yAt(ticks);
        if (footY >= top - 2 && footY <= top + 30) return p;
      }
    }
    return null;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (doneAt >= 0) {
      if (ticks - doneAt > 60) {
        doneAt = -1;
        _build();
      }
      return;
    }
    final slow = input.down && input.hasPointer && !input.tap && input.y > 1300;
    final jump = (input.tap && !(input.hasPointer && input.y > 1300)) || input.swipe == 0 || input.dirY < 0;
    if (jump && jumpsLeft > 0) {
      vy = jumpsLeft == 2 ? kJump : kJump * 0.85;
      jumpsLeft--;
      onGround = false;
      lastEvent = 1;
    }
    x += slow ? runSpeed * 0.35 : runSpeed;
    vy = math.min(vy + kGrav, 22);
    final prevFoot = y + kPlayerH / 2;
    y += vy;
    final foot = y + kPlayerH / 2;
    onGround = false;
    if (vy >= 0) {
      for (final p in plats) {
        if (x + kPlayerW / 2 > p.x && x - kPlayerW / 2 < p.x + p.w) {
          final top = p.yAt(ticks);
          if (prevFoot <= top + 4 && foot >= top) {
            y = top - kPlayerH / 2;
            vy = 0;
            onGround = true;
            jumpsLeft = 2;
            if (p.x > checkpoint && !p.moving) checkpoint = p.x + 40;
          }
        }
      }
    }
    // duvar: yüksek platformun yan yüzüne çarpma
    for (final p in plats) {
      final top = p.yAt(ticks);
      if (x + kPlayerW / 2 > p.x && x + kPlayerW / 2 < p.x + 16 && foot > top + 20 && y - kPlayerH / 2 < top + 60) {
        x = p.x - kPlayerW / 2;
      }
    }
    // jetonlar
    for (final c in coins) {
      if (!c.got && (c.x - x).abs() < 50 && (c.y - y).abs() < 60) {
        c.got = true;
        coinsGot++;
        score += 10;
        lastEvent = 2;
      }
    }
    // düşmanlar
    for (final f in foes) {
      if (f.dead) continue;
      f.x += f.vx;
      if (f.x < f.minX || f.x > f.maxX) f.vx = -f.vx;
      if (f.shooter && (f.x - x).abs() < 900 && f.x > x) {
        if (--f.cool <= 0) {
          eshots.add(EShot(f.x - 30, f.y - 20, -(7 + level.d * 0.3)));
          f.cool = math.max(70, 140 - level.d * 6);
        }
      }
      final fy = f.flyer ? f.y + math.sin(ticks / 25) * 40 : f.y;
      if ((f.x - x).abs() < 46 && (fy - y).abs() < 60) {
        if (vy > 0 && y < fy - 20) {
          f.dead = true;
          stomps++;
          vy = kJump * 0.7;
          jumpsLeft = 1;
          score += 30;
          fx.add(Fx(f.x, fy, ticks, 2));
          lastEvent = 4;
        } else {
          lastEvent = 3;
          hit();
          if (over) return;
        }
      }
    }
    if (gun) {
      if (ticks % 9 == 0) shots.add(Offset(x + 30, y - 6));
      for (var i = 0; i < shots.length; i++) {
        shots[i] = shots[i] + const Offset(26, 0);
      }
      shots.removeWhere((s) {
        for (final f in foes) {
          if (f.dead) continue;
          final fy = f.flyer ? f.y + math.sin(ticks / 25) * 40 : f.y;
          if ((s.dx - f.x).abs() < 36 && (s.dy - fy).abs() < 40) {
            f.dead = true;
            stomps++;
            score += 20;
            fx.add(Fx(f.x, fy, ticks, 3));
            lastEvent = 4;
            return true;
          }
        }
        return s.dx > x + 1100;
      });
      for (final e in eshots) {
        e.x += e.vx;
      }
      for (final e in eshots) {
        if ((e.x - x).abs() < 28 && (e.y - y).abs() < 40) {
          e.x = -9999;
          lastEvent = 3;
          hit();
          if (over) return;
        }
      }
      eshots.removeWhere((e) => e.x < x - 600);
    }
    pruneFx(fx, ticks);
    _extendIfEndless();
    if (y > 1700) {
      lastEvent = 3;
      hit();
      if (over) return;
      _respawn();
    }
    if (goalN > 0 && x > plats.last.x + 200) {
      stages++;
      score += 200;
      lastEvent = 5;
      doneAt = ticks;
      if (stages >= goalN) win();
    }
  }

  void _respawn() {
    x = checkpoint;
    final p = platUnder(x, 9999) ?? plats.firstWhere((p) => p.x + p.w > x, orElse: () => plats.first);
    if (x < p.x || x > p.x + p.w) x = p.x + 40;
    y = p.yAt(ticks) - kPlayerH / 2 - 4;
    vy = 0;
    eshots.clear();
  }

  @override
  double get progress => goalN == 0 ? 0 : (stages + clampD(x / (plats.last.x + 200), 0, 1)) / goalN;
  @override
  String get goalText => goalN == 0 ? '${x ~/ 100}m' : '${stages + 1}/$goalN';
  @override
  Map<String, int> get stats => {'stages_cleared': stages, 'coins_collected': coinsGot, 'foes_defeated': stomps};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: ileriyi küçük bir fizik simülasyonuyla tarar: şimdi zıplamak ya
/// da beklemek; hangisi önümüzdeki 60 tikte düşmeden/çarpmadan ilerlerse.
ArcadeInput sideBot(ArcadeSim sim) {
  final s = sim as SideSim;
  if (s.doneAt >= 0) return ArcadeInput.idle;
  // Basit kurallar: önümüzde boşluk/yüksek basamak/düşman varsa zıpla.
  final lookX = s.x + s.runSpeed * 2 + kPlayerW / 2;
  final foot = s.y + kPlayerH / 2;
  Plat? cur;
  for (final p in s.plats) {
    if (s.x > p.x - 10 && s.x < p.x + p.w + 10 && (p.yAt(s.ticks) - foot).abs() < 40) cur = p;
  }
  var wantJump = false;
  if (s.onGround && cur != null) {
    final edge = cur.x + cur.w;
    // kenara yaklaştık mı?
    if (lookX > edge) wantJump = true;
    // önde yüksek basamak
    for (final p in s.plats) {
      if (p != cur && p.x > s.x && p.x < s.x + s.runSpeed * 14 && p.yAt(s.ticks) < foot - 30) wantJump = true;
    }
    // düşman
    for (final f in s.foes) {
      if (!f.dead && f.x > s.x && f.x - s.x < s.runSpeed * 14 && !f.flyer) wantJump = true;
    }
    // düşman mermisi
    for (final e in s.eshots) {
      if (e.x > s.x && e.x - s.x < 260 && (e.y - s.y).abs() < 50) wantJump = true;
    }
  } else if (!s.onGround && s.vy > 2 && s.jumpsLeft > 0) {
    // Havada: altımızda inecek platform yoksa ikinci zıplama
    var landing = false;
    for (final p in s.plats) {
      final top = p.yAt(s.ticks);
      // 22 tik ileri (yaklaşık düşüş)
      final fx = s.x + s.runSpeed * 16;
      if (fx > p.x - 10 && s.x < p.x + p.w && top > foot - 10) landing = true;
    }
    if (!landing) wantJump = true;
    // önümüzde yüksek basamak, altına düşüyorsak
    for (final p in s.plats) {
      final top = p.yAt(s.ticks);
      if (p.x > s.x && p.x - s.x < s.runSpeed * 8 && top < foot + 20 && foot > top - 40) wantJump = true;
    }
  }
  return wantJump ? tapAt(500, 600) : ArcadeInput.idle;
}

void paintSide(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SideSim;
  final top = s.gun ? const Color(0xFF3D405B) : const Color(0xFF90E0EF);
  final bottom = s.gun ? const Color(0xFFE07A5F) : const Color(0xFFCAF0F8);
  paintSky(c, top, bottom);
  // paralaks tepeler
  for (var i = 0; i < 5; i++) {
    final hx = ((i * 330) - s.x * 0.25) % 1650 - 300;
    c.drawOval(Rect.fromLTWH(hx, 900, 600, 500), Paint()..color = (s.gun ? const Color(0xFF81B29A) : const Color(0xFF95D5B2)).withValues(alpha: 0.6));
  }
  c.save();
  c.translate(kScreenX - s.x, 0);
  for (final pl in s.plats) {
    if (pl.x + pl.w < s.x - 400 || pl.x > s.x + 900) continue;
    final y = pl.yAt(s.ticks);
    paintBox(c, Rect.fromLTWH(pl.x, y, pl.w, pl.moving ? 36 : kWorldH - y), s.gun ? const Color(0xFF8D6E63) : const Color(0xFFA47148), radius: 10, shade: false);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pl.x, y, pl.w, 18), const Radius.circular(9)), Paint()..color = s.gun ? const Color(0xFF606C38) : const Color(0xFF52B788));
  }
  for (final cn in s.coins) {
    if (cn.got || (cn.x - s.x).abs() > 900) continue;
    final w = 26 * (0.4 + 0.6 * math.cos(s.ticks / 10 + cn.x).abs());
    c.drawOval(Rect.fromCenter(center: Offset(cn.x, cn.y), width: w, height: 30), Paint()..color = const Color(0xFFFFC300));
  }
  for (final f in s.foes) {
    if (f.dead || (f.x - s.x).abs() > 900) continue;
    final fy = f.flyer ? f.y + math.sin(s.ticks / 25) * 40 : f.y;
    if (f.flyer) {
      paintBall(c, Offset(f.x, fy), 28, const Color(0xFF7209B7));
      final flap = (s.ticks ~/ 6).isEven ? -18.0 : 10.0;
      c.drawLine(Offset(f.x - 20, fy), Offset(f.x - 50, fy + flap), Paint()
        ..strokeWidth = 8
        ..color = const Color(0xFF7209B7));
      c.drawLine(Offset(f.x + 20, fy), Offset(f.x + 50, fy + flap), Paint()
        ..strokeWidth = 8
        ..color = const Color(0xFF7209B7));
    } else {
      paintBox(c, Rect.fromCenter(center: Offset(f.x, fy - 6), width: 64, height: 52), f.shooter ? const Color(0xFFD00000) : const Color(0xFFE76F51), radius: 18);
      c.drawCircle(Offset(f.x - 12, fy - 14), 6, Paint()..color = Colors.white);
      c.drawCircle(Offset(f.x - 13, fy - 14), 3, Paint()..color = Colors.black);
    }
  }
  for (final e in s.eshots) {
    paintBall(c, Offset(e.x, e.y), 10, const Color(0xFFFF006E));
  }
  for (final sh in s.shots) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sh, width: 26, height: 8), const Radius.circular(4)), Paint()..color = const Color(0xFFFFE066));
  }
  paintFxList(c, s.fx, s.ticks, p);
  if (s.goalN > 0) {
    final fx = s.plats.last.x + 200;
    c.drawLine(Offset(fx, s.plats.last.y), Offset(fx, s.plats.last.y - 260), Paint()
      ..strokeWidth = 8
      ..color = Colors.white);
    c.drawPath(Path()..moveTo(fx, s.plats.last.y - 260)..lineTo(fx + 90, s.plats.last.y - 225)..lineTo(fx, s.plats.last.y - 190)..close(), Paint()..color = p.piece(2));
  }
  // kahraman
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  final body = blink ? Colors.white54 : p.piece(0);
  final o = Offset(s.x, s.y);
  paintBox(c, Rect.fromCenter(center: o + const Offset(0, 8), width: kPlayerW, height: kPlayerH - 20), body, radius: 14, shade: false);
  c.drawCircle(o + const Offset(4, -28), 20, Paint()..color = const Color(0xFFFFD6A5));
  c.drawCircle(o + const Offset(12, -30), 4, Paint()..color = Colors.black);
  c.drawArc(Rect.fromCircle(center: o + const Offset(4, -32), radius: 21), math.pi, math.pi, true, Paint()..color = p.piece(1));
  if (s.gun) paintBox(c, Rect.fromLTWH(s.x + 8, s.y - 10, 40, 12), const Color(0xFF343A40), radius: 4, shade: false);
  c.restore();
}

Sfx? sideSound(ArcadeSim sim) => switch ((sim as SideSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.lose,
      4 => Sfx.place,
      5 => Sfx.win,
      _ => null,
    };

KitRules platformRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('stages_cleared', 'Geçilen bölüm', 'Stages cleared', scale: 50),
        GameStat('coins_collected', 'Jeton', 'Coins', scale: 500),
        GameStat('foes_defeated', 'Yenilen düşman', 'Foes defeated', scale: 200),
      ],
      missionTemplates: const [
        MissionTemplate('coins_collected', 'coins_collected', [30, 60, 120]),
        MissionTemplate('foes_defeated', 'foes_defeated', [5, 10, 20]),
      ],
      make: (l) => SideSim(l, false),
      botFn: sideBot,
    );

KitRules runGunRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('stages_cleared', 'Geçilen bölüm', 'Stages cleared', scale: 50),
        GameStat('foes_defeated', 'Yenilen düşman', 'Foes defeated', scale: 300),
        GameStat('coins_collected', 'Jeton', 'Coins', scale: 500),
      ],
      missionTemplates: const [
        MissionTemplate('foes_defeated', 'foes_defeated', [10, 20, 40]),
        MissionTemplate('coins_collected', 'coins_collected', [30, 60, 120]),
      ],
      make: (l) => SideSim(l, true),
      botFn: sideBot,
    );
