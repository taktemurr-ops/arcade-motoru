import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kabaddi Baskını: kendi yarı sahandan orta çizgiyi geçip rakip sahaya
/// akın et, savunmacılardan birine (ya da birkaçına) dokun ve nefesin
/// bitmeden orta çizgiye geri dön. Dokunduğun her savunmacı oyundan çıkar
/// ve bir puan getirir; bonus çizgisini geçersen +1. İki savunmacı aynı
/// anda sarar ya da biri uzun süre tutarsa yakalanırsın ve bir can gider.
/// Bütün savunma oyundan çıkınca (tüm takım) +2 ve savunma yeniden dizilir.
/// Lig, takım ve oyuncu adları yoktur.
const double kKbMid = 800, kKbBaulk = 640, kKbBonus = 470, kKbTop = 150;
const double kKbL = 120, kKbR = 880, kKbHome = 1060;
const double kKbTouch = 72, kKbTackle = 66, kKbHold = 48;
const double kKbSpeed = 9.5;

class KbDef {
  double x, y, hx, hy;
  bool out = false, touched = false;
  int hold = 0, alert = 0;
  KbDef(this.x, this.y) : hx = x, hy = y;
}

class KabaddiSim extends ArcadeSim {
  final ALevel level;
  final List<KbDef> defs = [];
  double rx = 500, ry = kKbHome;
  bool raiding = false, crossedBaulk = false, bonusTaken = false;
  int breath = 0, pause = 30, raids = 0, points = 0, touches = 0, bonuses = 0, allOuts = 0, okRaids = 0;
  int why = 0, allOutAt = -100, emptyAt = -100, bonusAt = -100;
  int lastEvent = 0, lastGain = 0, gainAt = -100, caughtAt = -100;
  late final int target = level.target(5, 1);
  late final int breathMax = level.lerp(560, 400).round();
  late final double dSpeed = level.lerp(3.8, 5.9) * (level.has('fast') ? 1.1 : 1);
  late final int reactDelay = level.lerp(14, 4).round();
  late final int nDefs = math.min(7, 4 + level.d ~/ 3 + (level.has('wide') ? 1 : 0));

  KabaddiSim(this.level) : super(level.meta) {
    _form(true);
  }

  bool get bonusOn => level.has('bonus') || level.d >= 3;

  int get alive => defs.where((d) => !d.out).length;

  void _form(bool all) {
    if (all) {
      defs.clear();
      final n = nDefs;
      for (var i = 0; i < n; i++) {
        final a = math.pi * (0.12 + 0.76 * i / (n - 1));
        final jx = (rng.nextDouble() - 0.5) * 30, jy = (rng.nextDouble() - 0.5) * 30;
        defs.add(KbDef(500 - math.cos(a) * 320 + jx, 330 + math.sin(a) * 150 + jy));
      }
    }
    for (final d in defs) {
      d.x = d.hx;
      d.y = d.hy;
      d.hold = 0;
      d.alert = 0;
      d.touched = false;
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (pause > 0) {
      pause--;
      return;
    }
    // Akıncı
    var tx = rx, ty = ry;
    if (input.down && input.hasPointer) {
      tx = input.x;
      ty = input.y - 50;
    }
    if (input.dirX != 0) tx = rx + input.dirX * 60;
    if (input.dirY != 0) ty = ry + input.dirY * 60;
    final dx = tx - rx, dy = ty - ry;
    final dd = math.sqrt(dx * dx + dy * dy);
    if (dd > 0.5) {
      final st = math.min(kKbSpeed, dd);
      rx += dx / dd * st;
      ry += dy / dd * st;
    }
    rx = clampD(rx, kKbL, kKbR);
    ry = clampD(ry, kKbTop, 1450);
    if (!raiding) {
      if (ry < kKbMid) {
        raiding = true;
        breath = breathMax;
        crossedBaulk = false;
        bonusTaken = false;
        raids++;
      } else {
        _defMove(false);
        return;
      }
    }
    // Akın sürüyor
    breath--;
    if (ry < kKbBaulk) crossedBaulk = true;
    if (!bonusTaken && ry < kKbBonus && bonusOn && alive >= 4) {
      bonusTaken = true;
      bonusAt = ticks;
      lastEvent = 5;
    }
    for (final d in defs) {
      if (d.out || d.touched) continue;
      if (dist(d.x, d.y, rx, ry) < kKbTouch) {
        d.touched = true;
        touches++;
        lastEvent = 1;
      }
    }
    _defMove(true);
    // Yakalama
    var near = 0;
    for (final d in defs) {
      if (d.out) continue;
      final r = dist(d.x, d.y, rx, ry);
      if (r < kKbTackle) near++;
      d.hold = r < kKbHold ? d.hold + 1 : 0;
      if (d.hold > 22) near = 9;
    }
    if (near >= 2) {
      why = 1;
      _caught();
      return;
    }
    if (breath <= 0) {
      why = 2;
      _caught();
      return;
    }
    if (ry > kKbMid + 10) _home();
  }

  void _defMove(bool active) {
    final n = defs.where((d) => !d.out).toList();
    if (!active) {
      for (final d in n) {
        d.x = moveToward(d.x, d.hx, 3);
        d.y = moveToward(d.y, d.hy, 3);
      }
      return;
    }
    // En yakın iki savunmacı sarmaya gider, diğerleri dönüş yolunu keser.
    n.sort((a, b) => dist(a.x, a.y, rx, ry).compareTo(dist(b.x, b.y, rx, ry)));
    final react = ry < kKbBaulk + 40;
    for (var i = 0; i < n.length; i++) {
      final d = n[i];
      double gx, gy;
      final r = dist(d.x, d.y, rx, ry);
      if (!react) {
        gx = d.hx + (rx - d.hx) * 0.15;
        gy = d.hy;
      } else if ((i < 2 && r < 300 && ++d.alert > reactDelay) || d.touched) {
        gx = rx;
        gy = ry;
      } else {
        // Kesici: akıncı ile orta çizgi arasına
        gx = rx + (d.hx - 500) * 0.35;
        gy = math.min(kKbMid - 30, ry + 170);
      }
      final sp = d.touched ? dSpeed * 1.08 : dSpeed;
      final vx = gx - d.x, vy = gy - d.y;
      final l = math.sqrt(vx * vx + vy * vy);
      if (l > 0.5) {
        final st = math.min(sp, l);
        d.x += vx / l * st;
        d.y += vy / l * st;
      }
      d.x = clampD(d.x, kKbL, kKbR);
      d.y = clampD(d.y, kKbTop, kKbMid - 20);
    }
    // Savunmacılar üst üste binmesin
    for (var i = 0; i < n.length; i++) {
      for (var j = i + 1; j < n.length; j++) {
        final a = n[i], b = n[j];
        final r = dist(a.x, a.y, b.x, b.y);
        if (r < 46 && r > 0.01) {
          final push = (46 - r) / 2;
          final ux = (a.x - b.x) / r, uy = (a.y - b.y) / r;
          a.x += ux * push;
          a.y += uy * push;
          b.x -= ux * push;
          b.y -= uy * push;
        }
      }
    }
  }

  void _home() {
    raiding = false;
    var gain = 0;
    for (final d in defs) {
      if (d.touched && !d.out) {
        d.out = true;
        gain++;
      }
    }
    if (bonusTaken && crossedBaulk) {
      gain++;
      bonuses++;
    }
    if (!crossedBaulk && gain == 0) {
      lastEvent = 6; // boş akın
      emptyAt = ticks;
    } else if (gain > 0) {
      okRaids++;
      lastEvent = 2;
    }
    if (alive == 0) {
      gain += 2;
      allOuts++;
      allOutAt = ticks;
      lastEvent = 4;
      _form(true);
    } else {
      _form(false);
    }
    points += gain;
    score += gain * 50 + (gain > 0 ? breath ~/ 6 : 0);
    lastGain = gain;
    gainAt = ticks;
    pause = 40;
    rx = 500;
    ry = kKbHome;
    if (level.goal && points >= target) {
      score += 100 * lives;
      win();
    }
  }

  void _caught() {
    raiding = false;
    caughtAt = ticks;
    lastEvent = 3;
    hit();
    for (final d in defs) {
      d.touched = false;
    }
    _form(false);
    rx = 500;
    ry = kKbHome;
    pause = 50;
  }

  @override
  void onLifeLost() {}

  @override
  bool useBooster() {
    if (over) return false;
    breath = math.min(breathMax, breath + 240);
    shield = 240;
    return true;
  }

  @override
  double get progress => target == 0 ? 0 : math.min(1.0, points / target);
  @override
  String get goalText => target == 0 ? '$points' : '$points/$target';
  @override
  Map<String, int> get stats => {'raid_points': points, 'touches': touches, 'bonus_points': bonuses, 'all_outs': allOuts};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: en dıştaki savunmacıya dıştan yaklaşır, dokununca savunmacılardan
/// uzaklaşarak orta çizgiye koşar.
ArcadeInput kabaddiBot(ArcadeSim sim) {
  final s = sim as KabaddiSim;
  if (s.pause > 0) return ArcadeInput.idle;
  final live = s.defs.where((d) => !d.out).toList();
  final touchedAny = live.any((d) => d.touched);
  double gx, gy;
  final urgent = s.raiding && s.breath < 150;
  if (touchedAny || urgent || (s.raiding && live.isEmpty)) {
    gx = s.rx;
    gy = kKbMid + 120;
  } else {
    // Hedef: orta çizgiye en yakın, komşusu uzak savunmacı.
    KbDef? best;
    var bv = -1e9;
    for (final d in live) {
      var mn = 1e9;
      for (final o in live) {
        if (identical(o, d)) continue;
        mn = math.min(mn, dist(o.x, o.y, d.x, d.y));
      }
      final v = mn * 1.2 + d.y * 0.8;
      if (v > bv) {
        bv = v;
        best = d;
      }
    }
    if (best == null) {
      gx = 500;
      gy = kKbMid + 120;
    } else {
      // En yakın komşunun tersinden yaklaş.
      KbDef? nb;
      var nd = 1e9;
      for (final o in live) {
        if (identical(o, best)) continue;
        final r = dist(o.x, o.y, best.x, best.y);
        if (r < nd) {
          nd = r;
          nb = o;
        }
      }
      var ax = 0.0, ay = 1.0;
      if (nb != null) {
        ax = best.x - nb.x;
        ay = best.y - nb.y;
        final l = math.sqrt(ax * ax + ay * ay);
        ax = ax / l + 0.0;
        ay = ay / l + 0.8;
        final l2 = math.sqrt(ax * ax + ay * ay);
        ax /= l2;
        ay /= l2;
      }
      gx = best.x + ax * 45;
      gy = best.y + ay * 45;
    }
  }
  // Kaçınma: yakın savunmacılardan itilme (dokunulacak hedef hariç).
  var vx = gx - s.rx, vy = gy - s.ry;
  final l = math.sqrt(vx * vx + vy * vy);
  if (l > 0.01) {
    vx /= l;
    vy /= l;
  }
  for (final d in live) {
    final r = dist(d.x, d.y, s.rx, s.ry);
    final avoid = touchedAny || urgent ? 230.0 : 120.0;
    if (r < avoid && r > 0.01) {
      final w = (avoid - r) / avoid * (touchedAny || urgent ? 2.2 : 0.9);
      vx += (s.rx - d.x) / r * w;
      vy += (s.ry - d.y) / r * w;
    }
  }
  if (touchedAny || urgent) vy = math.max(vy, 0.35);
  final m = math.sqrt(vx * vx + vy * vy);
  if (m < 0.01) return holdAt(s.rx, s.ry + 50);
  final x = clampD(s.rx + vx / m * 80, kKbL, kKbR), y = clampD(s.ry + vy / m * 80, kKbTop, 1450);
  return holdAt(x.roundToDouble(), (y + 50).roundToDouble());
}

KitRules kabaddiRules(String id) => KitRules(
      id,
      optionalMechanics: const ['bonus', 'fast', 'wide'],
      gameStats: const [
        GameStat('raid_points', 'Akın puanı', 'Raid points', scale: 1000),
        GameStat('touches', 'Dokunuş', 'Touches', scale: 800),
        GameStat('bonus_points', 'Bonus puanı', 'Bonus points', scale: 150),
        GameStat('all_outs', 'Tüm takım çıktı', 'All outs', scale: 60),
      ],
      missionTemplates: const [
        MissionTemplate('raid_points', 'raid_points', [100, 300, 1000]),
        MissionTemplate('touches', 'touches', [80, 250, 800]),
        MissionTemplate('all_outs', 'all_outs', [5, 20, 60]),
      ],
      make: KabaddiSim.new,
      botFn: kabaddiBot,
    );
