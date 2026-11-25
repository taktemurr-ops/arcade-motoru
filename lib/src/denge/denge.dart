import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';
import '../texts.dart';

/// Denge Kulesi: vincin ucunda sallanan düzensiz parçaları (kutu, kalas,
/// üstü dar kesik piramit, altı dar kâse, sütun) doğru anda bırakıp kuleye
/// yığ. Her katın üstündeki ağırlık merkezi alttaki temas yüzeyinin dışına
/// taşarsa o kattan yukarısı devrilir. Kule rüzgârla ve dengesiz yükle
/// sallanır; tam ortaya bırakmak (kusursuz) sallantıyı söndürür ve bonus verir.
const double kDkGravity = 0.9, kDkPerfect = 10, kDkGround = 1350, kDkMaxLean = 0.024;
const int kDkHold = 45, kDkCool = 30;

/// Parça türü: 0 kutu, 1 kalas, 2 kesik piramit (üstü dar), 3 kâse (altı dar), 4 sütun.
class DkPiece {
  final int kind;
  final double w, h, bh, th;
  final bool heavy;
  const DkPiece(this.kind, this.w, this.h, this.bh, this.th, this.heavy);
  double get mass => (bh + th) * h * (heavy ? 2 : 1);
}

class DkBlock {
  final DkPiece p;
  final double x, y; // merkez x, alt kenar yüksekliği
  final double cl, cr; // alttaki yüzeyle temas aralığı
  DkBlock(this.p, this.x, this.y, this.cl, this.cr);
  double get top => y + p.h;
}

class DkFall {
  final DkPiece p;
  double x, y, vx = 0, vy = 0;
  DkFall(this.p, this.x, this.y);
}

class DkDebris {
  final DkPiece p;
  double x, y, vx, vy, rot = 0;
  final double vr;
  final int born;
  DkDebris(this.p, this.x, this.y, this.vx, this.vy, this.vr, this.born);
}

class BalanceSim extends ArcadeSim {
  final ALevel level;
  final List<DkBlock> blocks = [];
  final List<DkDebris> debris = [];
  final List<Fx> fx = [];
  DkFall? fall;
  late DkPiece next;
  int cool = 20, hold = 0, combo = 0, perfects = 0, placed = 0, topples = 0, best = 0, lastEvent = 0;
  int perfectAt = -100;
  double lean = 0, leanV = 0, cam = 0;
  late final int goalN = level.target(8, 2);
  late final double baseHalf = level.lerp(200, 130) * (level.has('narrow') ? 0.75 : 1);
  late final double amp = level.lerp(170, 300);
  late final double spd = level.lerp(0.030, 0.055);
  double ph0 = 0, windPh = 0;
  late final double windAmp = level.has('wind') ? level.lerp(0.35, 0.9) : 0;

  BalanceSim(this.level) : super(level.meta) {
    ph0 = rng.nextDouble() * 6.28;
    windPh = rng.nextDouble() * 6.28;
    next = _make();
  }

  DkPiece _make() {
    final r = rng.nextDouble();
    final int kind;
    if (level.d <= 2) {
      kind = r < 0.5 ? 0 : (r < 0.8 ? 1 : 2);
    } else {
      kind = r < 0.32 ? 0 : (r < 0.5 ? 1 : (r < 0.7 ? 2 : (r < 0.85 ? 3 : 4)));
    }
    final sc = level.lerp(1.0, 0.8);
    final v = rng.nextDouble();
    final heavy = level.has('heavy') && rng.chance(0.25);
    final (double w, double h, double bf, double tf) = switch (kind) {
      0 => ((150 + v * 50) * sc, 70.0, 0.5, 0.5),
      1 => ((240 + v * 60) * sc, 40.0, 0.5, 0.5),
      2 => ((180 + v * 40) * sc, 70.0, 0.5, 0.3),
      3 => ((190 + v * 30) * sc, 70.0, 0.2, 0.5),
      _ => ((100 + v * 20) * sc, 130.0, 0.5, 0.5),
    };
    return DkPiece(kind, w, h, w * bf, w * tf, heavy);
  }

  /// Rüzgâr: tike bağlı saf fonksiyon (bot önceden hesaplayabilir).
  double windAt(int t) => windAmp == 0 ? 0 : windAmp * math.sin(t / 97 + windPh) * (0.6 + 0.4 * math.sin(t / 37));

  double hookX(int t) => 500 + amp * math.sin(t * spd + ph0);

  double get topH => blocks.isEmpty ? 0 : blocks.last.top;
  double get supportX => blocks.isEmpty ? 500 : blocks.last.x;
  double get supportHalf => blocks.isEmpty ? baseHalf : blocks.last.p.th;
  bool get goalReached => goalN > 0 && blocks.length >= goalN;
  bool get ready => fall == null && cool <= 0 && !goalReached;

  /// Devrilen ilk katın indeksi (yoksa -1). Eğim, ağırlık merkezini kaydırır.
  int unstableFrom() {
    for (var i = 0; i < blocks.length; i++) {
      var m = 0.0, mx = 0.0, my = 0.0;
      for (var j = i; j < blocks.length; j++) {
        final b = blocks[j];
        final bm = b.p.mass;
        m += bm;
        mx += bm * b.x;
        my += bm * (b.y + b.p.h / 2);
      }
      final cx = mx / m + lean * (my / m - blocks[i].y);
      if (cx < blocks[i].cl || cx > blocks[i].cr) return i;
    }
    return -1;
  }

  void _topple(int from) {
    final dir = blocks.last.x >= blocks[from].x + lean * 100 ? 1.0 : -1.0;
    for (var j = from; j < blocks.length; j++) {
      final b = blocks[j];
      debris.add(DkDebris(b.p, b.x, b.y, dir * (3 + (j - from) * 0.8), -4, dir * 0.06, ticks));
    }
    blocks.removeRange(from, blocks.length);
    topples++;
    combo = 0;
    hold = 0;
    leanV *= 0.3;
    lastEvent = 4;
    hit();
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    final t = ticks;
    final w = windAt(t);
    // Kule salınımı: yay + sönüm + dengesiz yük + rüzgâr.
    if (blocks.isNotEmpty) {
      var m = 0.0, mx = 0.0;
      for (final b in blocks) {
        m += b.p.mass;
        mx += b.p.mass * b.x;
      }
      final acc = -0.004 * lean - 0.06 * leanV + 0.0008 * (mx / m - 500) / 1000 + 0.00003 * w * (topH / 1000) * 8;
      leanV += acc;
      lean = clampD(lean + leanV, -kDkMaxLean, kDkMaxLean);
    } else {
      lean = 0;
      leanV = 0;
    }
    final u = unstableFrom();
    if (u >= 0) _topple(u);
    // Düşen parça
    final f = fall;
    if (f != null) {
      f.vy += kDkGravity;
      f.y -= f.vy;
      f.vx += w * 0.012;
      f.x += f.vx;
      final top = topH;
      if (f.y <= top) {
        fall = null;
        cool = kDkCool;
        final sx = supportX, sh = supportHalf;
        var x = f.x;
        if ((x - sx).abs() <= kDkPerfect) {
          x = sx;
          perfects++;
          combo++;
          perfectAt = ticks;
          leanV *= 0.3;
          score += 20 + 5 * math.min(combo, 10);
          lastEvent = 2;
        } else {
          combo = 0;
          leanV += (x - sx) * 0.00002;
          score += 10;
          lastEvent = 1;
        }
        final cl = math.max(x - f.p.bh, sx - sh), cr = math.min(x + f.p.bh, sx + sh);
        if (cr - cl < 6) {
          // Kenara çarpıp düştü
          debris.add(DkDebris(f.p, x, top, x >= sx ? 4 : -4, -3, x >= sx ? 0.07 : -0.07, ticks));
          combo = 0;
          lastEvent = 3;
          hit();
        } else {
          blocks.add(DkBlock(f.p, x, top, cl, cr));
          placed++;
          best = math.max(best, blocks.length);
          fx.add(Fx(x, top, ticks, lastEvent == 2 ? 1 : 0));
        }
      }
    }
    if (cool > 0) {
      cool--;
    } else if (fall == null && !goalReached && (input.tap || input.swipe == 2)) {
      final p = next;
      next = _make();
      fall = DkFall(p, hookX(t), topH + 400 - p.h);
    }
    if (goalReached && fall == null) {
      if (++hold >= kDkHold) {
        score += 100 + lives * 50;
        win();
      }
    } else {
      hold = 0;
    }
    for (final d in debris) {
      d.vy += kDkGravity;
      d.y -= d.vy;
      d.x += d.vx;
      d.rot += d.vr;
    }
    debris.removeWhere((d) => ticks - d.born > 120);
    pruneFx(fx, ticks);
    final camTarget = math.max(0.0, topH - 600);
    cam += (camTarget - cam) * 0.08;
  }

  /// Şimdi bırakılırsa parçanın ineceği x (bot ve yardımcı gölge için).
  double predictLanding(int releaseTick) {
    final p = next;
    var x = hookX(releaseTick), y = topH + 400 - p.h, vx = 0.0, vy = 0.0;
    final top = topH;
    var t = releaseTick;
    while (true) {
      t++;
      vy += kDkGravity;
      y -= vy;
      vx += windAt(t) * 0.012;
      x += vx;
      if (y <= top) return x;
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : math.min(1.0, blocks.length / goalN);
  @override
  String get goalText => goalN == 0 ? '${blocks.length}' : '${blocks.length}/$goalN';
  @override
  Map<String, int> get stats => {'pieces_placed': placed, 'perfect_drops': perfects, 'tower_height': best};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput balanceBot(ArcadeSim sim) {
  final s = sim as BalanceSim;
  if (!s.ready) return ArcadeInput.idle;
  final sx = s.supportX;
  final a = (s.predictLanding(s.ticks + 1) - sx).abs();
  final b = (s.predictLanding(s.ticks + 2) - sx).abs();
  return a <= b && a < kDkPerfect * 0.95 ? tapAny : ArcadeInput.idle;
}

Color _dkColor(DkPiece p, ArcadePalette pal) =>
    p.heavy ? const Color(0xFF495057) : pal.piece(p.kind + 1);

Path _dkShape(DkPiece p, double cx, double bottomY) {
  final top = bottomY - p.h;
  return Path()
    ..moveTo(cx - p.bh, bottomY)
    ..lineTo(cx + p.bh, bottomY)
    ..lineTo(cx + p.th, top)
    ..lineTo(cx - p.th, top)
    ..close();
}

void _paintPiece(Canvas c, DkPiece p, double cx, double bottomY, ArcadePalette pal, {double alpha = 1}) {
  final col = _dkColor(p, pal).withValues(alpha: alpha);
  final path = _dkShape(p, cx, bottomY);
  c.drawPath(path.shift(const Offset(5, 6)), Paint()..color = Colors.black26.withValues(alpha: 0.26 * alpha));
  final r = Rect.fromLTRB(cx - math.max(p.bh, p.th), bottomY - p.h, cx + math.max(p.bh, p.th), bottomY);
  c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(col, Colors.white, 0.25)!, Color.lerp(col, Colors.black, 0.2)!],
        ).createShader(r));
  c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: 0.18 * alpha));
  if (p.kind == 1) {
    // Kalas: tahta damarları
    final g = Paint()
      ..color = Colors.black.withValues(alpha: 0.12 * alpha)
      ..strokeWidth = 2;
    c.drawLine(Offset(cx - p.bh + 12, bottomY - p.h * 0.4), Offset(cx + p.bh - 30, bottomY - p.h * 0.4), g);
  }
  if (p.heavy) paintText(c, '⚓', Offset(cx, bottomY - p.h / 2), 30, Colors.white70);
}

void paintBalance(Canvas c, ArcadeSim sim, ArcadePalette p, double tt) {
  final s = sim as BalanceSim;
  paintSky(c, const Color(0xFF8ECAE6), const Color(0xFFFFF1D0));
  final cam = s.cam;
  double sy(double h) => kDkGround - (h - cam);
  // Uzak tepeler
  final hill = Paint()..color = const Color(0xFF90BE6D).withValues(alpha: 0.5);
  c.drawOval(Rect.fromCenter(center: Offset(220, sy(-40) + 40), width: 700, height: 260), hill);
  c.drawOval(Rect.fromCenter(center: Offset(820, sy(-40) + 60), width: 760, height: 300), hill);
  // Zemin ve kaide
  c.drawRect(Rect.fromLTRB(0, sy(0) + 30, kWorldW, kWorldH + 40), Paint()..color = const Color(0xFF6A994E));
  paintBox(c, Rect.fromLTRB(500 - s.baseHalf, sy(0), 500 + s.baseHalf, sy(0) + 40), const Color(0xFF7F5539), radius: 6);
  // Kule (eğimle döner)
  c.save();
  c.translate(500, sy(0));
  c.rotate(s.lean * 1.5);
  c.translate(-500, -sy(0));
  for (final b in s.blocks) {
    _paintPiece(c, b.p, b.x, sy(b.y), p);
  }
  c.restore();
  for (final d in s.debris) {
    c.save();
    c.translate(d.x, sy(d.y) - d.p.h / 2);
    c.rotate(d.rot);
    _paintPiece(c, d.p, 0, d.p.h / 2, p, alpha: clampD(1 - (s.ticks - d.born) / 120, 0, 1));
    c.restore();
  }
  // Vinç: sarkaç halatı ve kanca
  final hx = s.hookX(s.ticks);
  final hy = sy(s.topH + 400);
  const pivot = Offset(500, -260);
  c.drawLine(pivot, Offset(hx, hy - 20), Paint()
    ..color = const Color(0xFF343A40)
    ..strokeWidth = 5);
  c.drawCircle(Offset(hx, hy - 20), 12, Paint()..color = const Color(0xFFFFB703));
  final f = s.fall;
  if (f != null) {
    _paintPiece(c, f.p, f.x, sy(f.y), p);
  } else if (!s.goalReached) {
    _paintPiece(c, s.next, hx, hy + s.next.h, p, alpha: s.cool > 0 ? 0.4 : 1);
    if (s.cool <= 0 && !s.level.has('wind')) {
      // Yardımcı gölge: inilecek nokta
      final lx = s.predictLanding(s.ticks);
      c.drawLine(Offset(lx, hy + s.next.h + 10), Offset(lx, sy(s.topH) - 4), Paint()
        ..color = Colors.white38
        ..strokeWidth = 3);
    }
  }
  paintFxList(c, s.fx, s.ticks, p);
  // Rüzgâr göstergesi
  if (s.windAmp > 0) {
    final w = s.windAt(s.ticks);
    final arrow = w > 0.05 ? '→' * (1 + (w.abs() * 3).floor()) : (w < -0.05 ? '←' * (1 + (w.abs() * 3).floor()) : '·');
    paintText(c, '${at(arcadeLang, 'wind')} $arrow', const Offset(500, 190), 40, const Color(0xFF023047));
  }
  if (s.ticks - s.perfectAt < 50) {
    paintText(c, s.combo >= 2 ? '${at(arcadeLang, 'perfect')} x${s.combo}' : at(arcadeLang, 'perfect'), const Offset(500, 260), 52,
        const Color(0xFFFB8500));
  }
  // Eğim ölçer
  final lr = (s.lean / kDkMaxLean).clamp(-1.0, 1.0);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(300, 1540, 400, 18), const Radius.circular(9)), Paint()..color = Colors.black26);
  c.drawCircle(Offset(500 + lr * 190, 1549), 16, Paint()..color = Color.lerp(const Color(0xFF2A9D8F), const Color(0xFFE63946), lr.abs())!);
  if (s.goalReached) {
    c.drawArc(Rect.fromCircle(center: const Offset(500, 340), radius: 40), -math.pi / 2, math.pi * 2 * s.hold / kDkHold, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = const Color(0xFF2A9D8F));
  }
}

Sfx? balanceSound(ArcadeSim sim) => switch ((sim as BalanceSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.combo,
      3 => Sfx.error,
      4 => Sfx.lose,
      _ => null,
    };

KitRules balanceRules(String id) => KitRules(
      id,
      optionalMechanics: const ['wind', 'heavy', 'narrow'],
      gameStats: const [
        GameStat('pieces_placed', 'Yerleşen parça', 'Pieces placed', scale: 500),
        GameStat('perfect_drops', 'Kusursuz bırakış', 'Perfect drops', scale: 200),
        GameStat('tower_height', 'En yüksek kule', 'Tallest tower', scale: 40),
      ],
      missionTemplates: const [
        MissionTemplate('pieces_placed', 'pieces_placed', [30, 80, 200]),
        MissionTemplate('perfect_drops', 'perfect_drops', [10, 25, 60]),
      ],
      make: BalanceSim.new,
      botFn: balanceBot,
    );
