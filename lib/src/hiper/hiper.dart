import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Hiper-gündelik paket: her bölüm sekiz tek-dokunuş mekaniğinden birini
/// getirir (bölüm numarasına göre sırayla):
///  0 Zamanla dur   – kayan işaret yeşil bölgedeyken dokun
///  1 Kaç           – düşen bloklardan sağa-sola kaç
///  2 Yörünge       – dokun = iç/dış yörünge değiştir, engellere çarpma
///  3 İp atlama     – ip ayağının altına gelince zıpla
///  4 Zikzak        – dokun = yön değiştir, yoldan çıkma
///  5 Denge         – sol/sağ tarafa basılı tutarak tahtayı dengele
///  6 Bardağa at    – açı salınırken doğru anda dokun
///  7 Yakala        – sepeti kaydır, yıldızları topla, bombadan kaç
const int kKinds = 8;
const double kCx = 500, kCy = 860;

class Faller {
  double x, y;
  final double vy;
  final bool bad;
  bool done = false;
  Faller(this.x, this.y, this.vy, this.bad);
}

class HyperSim extends ArcadeSim {
  final ALevel level;
  late final int kind = ((level.spec.levelId - 1) % kKinds + kKinds) % kKinds;
  int done = 0, lastEvent = 0, flash = 0;
  late final int goalN = level.target(8, 1);
  // ortak
  double px = 500;
  final List<Faller> fallers = [];
  int spawnIn = 30;
  // 0 zamanla
  double mark = 0, markV = 0.012, zone = 0.5, zoneW = 0.22;
  // 2 yörünge
  double orbA = 0;
  bool outer = true;
  final List<(double, bool)> orbObs = []; // (açı, dış mı)
  // 3 ip
  double rope = 0, ropeV = 2.6, jumpH = 0, jumpV = 0;
  bool ropeArmed = true;
  // 4 zikzak
  final List<Offset> zz = []; // köşe noktaları (dünya)
  double zx = 500, zy = 1300, zdir = 1, zcam = 0;
  int zseg = 0;
  // 5 denge
  double beamA = 0, ballX = 0, ballV = 0, drift = 0;
  int balanceT = 0;
  // 6 at
  double aimA = 0.35, aimV = 0.012, cupX = 700;
  (double, double)? throwPos;
  double tvx = 0, tvy = 0;

  HyperSim(this.level) : super(level.meta) {
    switch (kind) {
      case 0:
        markV = 0.010 + level.d * 0.0012;
        zoneW = 0.24 - level.d * 0.012;
        zone = 0.2 + rng.nextDouble() * 0.6;
      case 2:
        for (var k = 0; k < 3 + level.d ~/ 3; k++) {
          _orbObstacle(1.2 + k * 1.3);
        }
      case 3:
        ropeV = 2.4 + level.d * 0.2;
      case 4:
        zz.add(const Offset(500, 1300));
        while (zz.length < 30) {
          _zzNext();
        }
      case 6:
        _newCup();
      default:
        break;
    }
  }

  // ---------------------------------------------------------- yardımcılar
  void _ok([int pts = 10]) {
    done++;
    score += pts;
    lastEvent = 1;
    flash = 12;
    if (goalN > 0 && done >= goalN) win();
  }

  void _bad() {
    lastEvent = 3;
    flash = -12;
    hit();
  }

  void _orbObstacle(double at) {
    for (var tries = 0; tries < 20; tries++) {
      final outerRing = rng.chance(0.5);
      final a = at + rng.nextDouble() * 0.6;
      final clash = orbObs.any((o) => o.$2 != outerRing && _angDist(o.$1, a) < 0.75);
      if (!clash) {
        orbObs.add((a, outerRing));
        return;
      }
    }
  }

  static double _angDist(double a, double b) {
    var d = (a - b) % (math.pi * 2);
    if (d < 0) d += math.pi * 2;
    return math.min(d, math.pi * 2 - d);
  }

  void _zzNext() {
    final last = zz.last;
    final len = 140 + rng.nextDouble() * (260 - level.d * 10);
    final dir = zz.length.isEven ? 1.0 : -1.0;
    var nx = last.dx + dir * len * 0.7;
    if (nx < 140 || nx > 860) nx = last.dx - dir * len * 0.7;
    zz.add(Offset(clampD(nx, 120, 880), last.dy - len * 0.7));
  }

  /// Zikzak: mevcut segmentin yönü (+1 sağ, -1 sol).
  double zzDir(int i) => zz[i + 1].dx > zz[i].dx ? 1 : -1;

  void _newCup() {
    // Bir açı seç, oraya düşecek bardağı yerleştir (çözülebilir).
    final a = 0.3 + rng.nextDouble() * 0.9;
    final land = throwLand(a);
    cupX = clampD(land, 380, 940);
    aimV = (0.010 + level.d * 0.0012) * (aimV >= 0 ? 1 : -1);
  }

  static const double kThrowV = 26, kThrowG = 0.6, kThrowX = 120, kThrowY = 1250;

  /// Saf: açıyla atılan topun yer seviyesine düştüğü x.
  static double throwLand(double a) {
    var x = kThrowX, y = kThrowY, vx = math.cos(a) * kThrowV, vy = -math.sin(a) * kThrowV;
    for (var k = 0; k < 400; k++) {
      vy += kThrowG;
      x += vx;
      y += vy;
      if (vy > 0 && y >= kThrowY) return x;
    }
    return x;
  }

  // ---------------------------------------------------------- güncelleme
  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flash > 0) flash--;
    if (flash < 0) flash++;
    final tap = input.tap || input.swipe == 0;
    switch (kind) {
      case 0:
        mark += markV;
        if (mark > 1 || mark < 0) {
          markV = -markV;
          mark = clampD(mark, 0, 1);
        }
        if (tap) {
          if ((mark - zone).abs() < zoneW / 2) {
            _ok(10 + ((1 - (mark - zone).abs() / (zoneW / 2)) * 10).round());
            zone = 0.15 + rng.nextDouble() * 0.7;
            markV *= 1.04;
          } else {
            _bad();
          }
        }
      case 1:
      case 7:
        if (input.down && input.hasPointer) {
          px = moveToward(px, input.x, 24);
        } else {
          px += input.dirX * 16;
        }
        px = clampD(px, 80, 920);
        if (--spawnIn <= 0) {
          if (kind == 1) {
            // bir sıra blok: 5 şeritten biri boş
            final free = rng.nextInt(5);
            for (var l = 0; l < 5; l++) {
              if (l != free && rng.chance(0.75)) fallers.add(Faller(100 + l * 200.0, -60, 7 + level.d * 0.5, true));
            }
            fallers.add(Faller(100 + free * 200.0, -60, 7 + level.d * 0.5, false));
            spawnIn = math.max(52, 90 - level.d * 4);
          } else {
            final bad = rng.chance(0.3);
            fallers.add(Faller(100 + rng.nextDouble() * 800, -40, 5 + level.d * 0.4 + rng.nextDouble() * 2, bad));
            spawnIn = math.max(20, 50 - level.d * 3);
          }
        }
        for (final f in fallers) {
          f.y += f.vy;
          if (f.done) continue;
          if (kind == 1) {
            if (f.bad && f.y > 1340 && f.y < 1460 && (f.x - px).abs() < 130) {
              f.done = true;
              _bad();
            } else if (!f.bad && f.y > 1460) {
              f.done = true;
              _ok();
            }
          } else {
            if (f.y > 1360 && f.y < 1440 && (f.x - px).abs() < 110) {
              f.done = true;
              f.bad ? _bad() : _ok();
            }
          }
        }
        fallers.removeWhere((f) => f.y > 1700);
      case 2:
        orbA += 0.022 + level.d * 0.002;
        if (tap) outer = !outer;
        for (var i = 0; i < orbObs.length; i++) {
          final (a, o) = orbObs[i];
          final rel = (orbA - a) % (math.pi * 2);
          if (o == outer && _angDist(orbA, a) < 0.16) {
            _bad();
            orbObs.removeAt(i);
            _orbObstacle(orbA + 2.0);
            break;
          }
          if (rel > 0.3 && rel < 0.4 && o != outer) {
            // geçildi
            orbObs.removeAt(i);
            _orbObstacle(orbA + 2.2 + rng.nextDouble());
            _ok();
            break;
          }
        }
      case 3:
        rope = (rope + ropeV) % 360;
        if (tap && jumpH == 0) jumpV = 15;
        if (jumpV != 0 || jumpH > 0) {
          jumpH += jumpV;
          jumpV -= 1.0;
          if (jumpH <= 0) {
            jumpH = 0;
            jumpV = 0;
          }
        }
        // ip altta (90°) iken
        final atBottom = (rope - 90).abs() < ropeV * 2.5;
        if (atBottom && ropeArmed) {
          ropeArmed = false;
          if (jumpH < 28) {
            _bad();
          } else {
            _ok();
            ropeV = math.min(ropeV * 1.03, 7.5);
          }
        }
        if (!atBottom) ropeArmed = true;
      case 4:
        if (tap) zdir = -zdir;
        final sp = 5.0 + level.d * 0.35;
        zx += zdir * sp * 0.7;
        zy -= sp * 0.7;
        zcam = zy - 1100;
        while (zseg + 2 < zz.length && zy <= zz[zseg + 1].dy) {
          zseg++;
          _ok(5);
        }
        while (zz.length < zseg + 20) {
          _zzNext();
        }
        // yolda mı? (segment çizgisine uzaklık)
        final a = zz[zseg], b = zz[zseg + 1];
        if (segDist(zx, zy, a.dx, a.dy, b.dx, b.dy) > 46) {
          _bad();
          // yola geri koy
          final t = clampD((zy - a.dy) / (b.dy - a.dy), 0, 1);
          zx = a.dx + (b.dx - a.dx) * t;
          zdir = zzDir(zseg);
        }
      case 5:
        if (ticks % 90 == 0) drift = (rng.nextDouble() * 2 - 1) * (0.0015 + level.d * 0.0003);
        var push = 0.0;
        if (input.down && input.hasPointer) push = input.x < 500 ? -1 : 1;
        if (input.dirX != 0) push = input.dirX.toDouble();
        beamA = clampD(beamA + drift + push * 0.006, -0.45, 0.45);
        ballV += math.sin(beamA) * 0.5;
        ballV *= 0.995;
        ballX += ballV;
        if (ballX.abs() > 380) {
          _bad();
          ballX = 0;
          ballV = 0;
          beamA = 0;
        }
        balanceT++;
        if (balanceT % 120 == 0) _ok(5);
      case 6:
        final tp = throwPos;
        if (tp == null) {
          aimA += aimV;
          if (aimA > 1.25 || aimA < 0.25) aimV = -aimV;
          if (tap) {
            throwPos = (kThrowX, kThrowY);
            tvx = math.cos(aimA) * kThrowV;
            tvy = -math.sin(aimA) * kThrowV;
          }
        } else {
          tvy += kThrowG;
          final nx = tp.$1 + tvx, ny = tp.$2 + tvy;
          throwPos = (nx, ny);
          if (tvy > 0 && ny >= kThrowY) {
            throwPos = null;
            if ((nx - cupX).abs() < 50) {
              _ok(25);
              _newCup();
            } else {
              _bad();
            }
          }
        }
      default:
        break;
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : done / goalN;
  @override
  String get goalText => goalN == 0 ? '$done' : '$done/$goalN';
  @override
  Map<String, int> get stats => {'mini_successes': done};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: her mekaniğin basit ve kesin çözümü.
ArcadeInput hyperBot(ArcadeSim sim) {
  final s = sim as HyperSim;
  switch (s.kind) {
    case 0:
      final next = s.mark + s.markV;
      return (next - s.zone).abs() < s.zoneW / 5 ? tapAny : ArcadeInput.idle;
    case 1:
      // en yakın sıranın boş şeridi
      Faller? free;
      for (final f in s.fallers) {
        if (!f.bad && !f.done && f.y < 1460 && (free == null || f.y > free.y)) free = f;
      }
      return holdAt(free?.x ?? 500, 1400);
    case 2:
      // önümüzdeki (0.25..0.6 rad) engel bizim yörüngemizdeyse değiştir
      for (final (a, o) in s.orbObs) {
        final ahead = (a - s.orbA) % (math.pi * 2);
        if (o == s.outer && ahead > 0 && ahead < 0.45) return tapAny;
      }
      return ArcadeInput.idle;
    case 3:
      final toBottom = (90 - s.rope) % 360;
      return s.jumpH == 0 && toBottom > 0 && toBottom < s.ropeV * 13 ? tapAny : ArcadeInput.idle;
    case 4:
      final want = s.zzDir(s.zseg);
      return want != s.zdir ? tapAny : ArcadeInput.idle;
    case 5:
      final target = clampD(-s.ballX * 0.0012 - s.ballV * 0.05, -0.4, 0.4);
      if ((s.beamA - target).abs() < 0.004) return ArcadeInput.idle;
      return holdAt(s.beamA > target ? 200 : 800, 1200);
    case 6:
      if (s.throwPos != null) return ArcadeInput.idle;
      final land = HyperSim.throwLand(s.aimA + s.aimV);
      return (land - s.cupX).abs() < 40 ? tapAny : ArcadeInput.idle;
    default:
      Faller? best;
      for (final f in s.fallers) {
        if (f.bad || f.done || f.y > 1400) continue;
        final danger = s.fallers.any((b) => b.bad && !b.done && (b.x - f.x).abs() < 140 && (b.y - f.y).abs() < 250);
        if (danger) continue;
        if (best == null || f.y > best.y) best = f;
      }
      var tx = best?.x ?? s.px;
      for (final b in s.fallers) {
        if (b.bad && !b.done && b.y > 1150 && b.y < 1440 && (b.x - tx).abs() < 130) tx = b.x < 500 ? b.x + 260 : b.x - 260;
      }
      return holdAt(tx, 1400);
  }
}

void paintHyper(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as HyperSim;
  final hue = HSVColor.fromAHSV(1, (s.kind * 45.0) % 360, 0.45, 0.55).toColor();
  paintSky(c, hue, Color.lerp(hue, Colors.black, 0.5)!);
  if (s.flash != 0) {
    c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = (s.flash > 0 ? Colors.white : Colors.red).withValues(alpha: s.flash.abs() / 50));
  }
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  final me = blink ? Colors.white54 : p.piece(0);
  switch (s.kind) {
    case 0:
      const bar = Rect.fromLTWH(100, 780, 800, 80);
      paintBox(c, bar, Colors.white24, radius: 40, shade: false);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(100 + (s.zone - s.zoneW / 2) * 800, 780, s.zoneW * 800, 80), const Radius.circular(40)), Paint()..color = const Color(0xFF55A630));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(100 + (s.zone - s.zoneW / 10) * 800, 780, s.zoneW * 160, 80), const Radius.circular(20)), Paint()..color = const Color(0xFFAACC00));
      paintBox(c, Rect.fromCenter(center: Offset(100 + s.mark * 800, 820), width: 22, height: 130), me, radius: 11);
    case 1:
    case 7:
      for (final f in s.fallers) {
        if (f.done && s.kind == 7) continue;
        if (s.kind == 1) {
          if (f.bad) paintBox(c, Rect.fromCenter(center: Offset(f.x, f.y), width: 180, height: 80), const Color(0xFF343A40), radius: 14);
        } else if (f.bad) {
          paintBall(c, Offset(f.x, f.y), 32, const Color(0xFF212529));
          paintText(c, '✸', Offset(f.x, f.y - 40), 30, const Color(0xFFFF6D00));
        } else {
          paintText(c, '★', Offset(f.x, f.y), 72, const Color(0xFFFFC300));
        }
      }
      if (s.kind == 1) {
        paintBall(c, Offset(s.px, 1400), 40, me);
      } else {
        paintBox(c, Rect.fromCenter(center: Offset(s.px, 1420), width: 200, height: 70), me, radius: 20);
      }
    case 2:
      for (final r in [250.0, 380.0]) {
        c.drawCircle(const Offset(kCx, kCy), r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.white24);
      }
      for (final (a, o) in s.orbObs) {
        final r = o ? 380.0 : 250.0;
        paintBox(c, Rect.fromCenter(center: const Offset(kCx, kCy) + Offset(math.cos(a), math.sin(a)) * r, width: 50, height: 50), const Color(0xFFE63946), radius: 10);
      }
      final r = s.outer ? 380.0 : 250.0;
      paintBall(c, const Offset(kCx, kCy) + Offset(math.cos(s.orbA), math.sin(s.orbA)) * r, 28, me);
    case 3:
      final ra = s.rope * math.pi / 180;
      final ropePath = Path()
        ..moveTo(150, 900)
        ..quadraticBezierTo(500, 900 + math.sin(ra) * 900, 850, 900);
      c.drawPath(ropePath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = (s.rope > 0 && s.rope < 180) ? Colors.white : Colors.white38);
      c.drawRect(const Rect.fromLTWH(0, 1360, kWorldW, 240), Paint()..color = Colors.black26);
      paintBox(c, Rect.fromCenter(center: Offset(500, 1300 - s.jumpH * 3), width: 70, height: 120), me, radius: 30);
      for (final x in [150.0, 850.0]) {
        c.drawCircle(Offset(x, 900), 30, Paint()..color = p.piece(2));
      }
    case 4:
      c.save();
      c.translate(0, -s.zcam);
      final path = Path()..moveTo(s.zz.first.dx, s.zz.first.dy);
      for (final q in s.zz.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 100
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white24);
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white54);
      paintBall(c, Offset(s.zx, s.zy), 24, me);
      c.restore();
    case 5:
      c.save();
      c.translate(500, 1000);
      c.rotate(s.beamA);
      paintBox(c, const Rect.fromLTWH(-420, -14, 840, 28), const Color(0xFF8D6E63), radius: 14);
      paintBall(c, Offset(s.ballX, -50), 36, me);
      c.restore();
      c.drawPath(Path()..moveTo(460, 1080)..lineTo(500, 1010)..lineTo(540, 1080)..close(), Paint()..color = Colors.white38);
      paintText(c, '◀', const Offset(150, 1400), 90, Colors.white24);
      paintText(c, '▶', const Offset(850, 1400), 90, Colors.white24);
    case 6:
      c.drawRect(const Rect.fromLTWH(0, HyperSim.kThrowY + 20, kWorldW, 400), Paint()..color = Colors.black26);
      paintBox(c, Rect.fromCenter(center: Offset(s.cupX, HyperSim.kThrowY - 20), width: 100, height: 90), const Color(0xFFE9C46A), radius: 12);
      final tp = s.throwPos;
      if (tp == null) {
        final a = s.aimA;
        c.drawLine(const Offset(HyperSim.kThrowX, HyperSim.kThrowY), Offset(HyperSim.kThrowX + math.cos(a) * 160, HyperSim.kThrowY - math.sin(a) * 160), Paint()
          ..strokeWidth = 8
          ..color = Colors.white70);
        paintBall(c, const Offset(HyperSim.kThrowX, HyperSim.kThrowY), 24, me);
      } else {
        paintBall(c, Offset(tp.$1, tp.$2), 24, me);
      }
    default:
      break;
  }
  const names = ['⏱', '⇆', '◎', '〰', '⟋', '⚖', '◔', '★'];
  paintText(c, names[s.kind], const Offset(500, 300), 110, Colors.white30);
}

Sfx? hyperSound(ArcadeSim sim) => switch ((sim as HyperSim).lastEvent) {
      1 => Sfx.place,
      3 => Sfx.error,
      _ => null,
    };

KitRules hyperRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('mini_successes', 'Başarılı hamle', 'Successful moves', scale: 500),
      ],
      missionTemplates: const [
        MissionTemplate('mini_successes', 'mini_successes', [30, 60, 120]),
      ],
      make: HyperSim.new,
      botFn: hyperBot,
    );
