import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Atış galerisi: üç rafta kayan tahta figürler. Ördek/teneke/yıldız vur,
/// "vurma" levhalı figürlerden kaçın. Şarjör 6 atış; boş rafa dokunmak
/// şarjörü doldurur (alttaki şerit).
class Figure {
  double x;
  final int row, kind; // kind: 0 ördek, 1 teneke, 2 yıldız, 3 vurma
  final double speed;
  bool down = false;
  int downAt = 0;
  Figure(this.x, this.row, this.kind, this.speed);
}

const double kReloadY = 1420;

class GallerySim extends ArcadeSim {
  final ALevel level;
  final List<Figure> figs = [];
  final List<Fx> fx = [];
  int ammo = 6, hitsN = 0, stars3 = 0, spawnIn = 0, reloads = 0, lastEvent = 0;
  late final int goalN = level.target(18, 5);
  final List<int> rowTimers = [0, 0, 0];

  GallerySim(this.level) : super(level.meta);

  double rowY(int r) => 420.0 + r * 300;
  int rowDir(int r) => r.isEven ? 1 : -1;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    for (var r = 0; r < 3; r++) {
      if (--rowTimers[r] <= 0) {
        final roll = rng.nextDouble();
        final kind = roll < 0.08 ? 2 : (level.has('decoys') && roll < 0.28 ? 3 : (roll < 0.6 ? 0 : 1));
        final sp = (2.2 + level.d * 0.35 + r * 0.4);
        figs.add(Figure(rowDir(r) > 0 ? -80 : kWorldW + 80, r, kind, sp));
        rowTimers[r] = math.max(30, 100 - level.d * 6) + rng.nextInt(40);
      }
    }
    for (final f in figs) {
      f.x += f.speed * rowDir(f.row);
    }
    if (input.tap && input.hasPointer) {
      if (input.y > kReloadY - 60) {
        if (ammo < 6) {
          ammo = 6;
          reloads++;
          lastEvent = 4;
        }
      } else if (ammo > 0) {
        ammo--;
        Figure? hitF;
        for (final f in figs) {
          if (!f.down && (input.x - f.x).abs() < 62 && (input.y - (rowY(f.row) - 70)).abs() < 80) hitF = f;
        }
        if (hitF != null) {
          hitF.down = true;
          hitF.downAt = ticks;
          fx.add(Fx(hitF.x, rowY(hitF.row) - 70, ticks, hitF.kind));
          if (hitF.kind == 3) {
            lastEvent = 3;
            hit();
          } else {
            hitsN++;
            if (hitF.kind == 2) stars3++;
            score += [10, 15, 50][hitF.kind] + hitF.row * 5;
            lastEvent = hitF.kind == 2 ? 2 : 1;
            if (goalN > 0 && hitsN >= goalN) win();
          }
        } else {
          lastEvent = 5;
        }
      } else {
        lastEvent = 3;
      }
    }
    // Kaçan ördek/teneke sayılmaz ama yıldız kaçarsa seri bozulmaz; yalnız
    // zamanlı/sonsuz modda baskı: sonsuzda 5 kaçan figür = can.
    figs.removeWhere((f) => (f.down && ticks - f.downAt > 20) || f.x < -120 || f.x > kWorldW + 120);
    pruneFx(fx, ticks);
  }

  @override
  double get progress => goalN == 0 ? 0 : hitsN / goalN;
  @override
  String get goalText => goalN == 0 ? '$hitsN' : '$hitsN/$goalN';
  @override
  Map<String, int> get stats => {'figures_hit': hitsN, 'stars_hit': stars3};
  @override
  int get stars {
    if (!won) return 0;
    final base = lifeStars(this, 3);
    return reloads > goalN ~/ 4 + 2 ? math.max(1, base - 1) : base;
  }
}

ArcadeInput galleryBot(ArcadeSim sim) {
  final s = sim as GallerySim;
  if (s.ticks % 5 != 0) return ArcadeInput.idle;
  if (s.ammo == 0) return tapAt(500, kReloadY);
  Figure? best;
  for (final f in s.figs) {
    if (f.down || f.kind == 3 || f.x < 60 || f.x > kWorldW - 60) continue;
    // Vurma levhası çok yakınsa atlama.
    final x = f.x + f.speed * s.rowDir(f.row);
    final clash = s.figs.any((o) => o != f && !o.down && o.row == f.row && o.kind == 3 && (o.x - x).abs() < 140);
    if (clash) continue;
    if (best == null || f.kind == 2 || (best.kind != 2 && f.row > best.row)) best = f;
  }
  if (best == null) return ArcadeInput.idle;
  return tapAt(best.x + best.speed * s.rowDir(best.row), s.rowY(best.row) - 70);
}

void paintGallery(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as GallerySim;
  paintSky(c, const Color(0xFF7F1D1D), const Color(0xFF3F0D0D));
  // perde
  for (var x = 0.0; x < kWorldW; x += 80) {
    c.drawRect(Rect.fromLTWH(x, 0, 40, 160), Paint()..color = const Color(0x22FFFFFF));
  }
  c.drawRect(const Rect.fromLTWH(0, 150, kWorldW, 20), Paint()..color = const Color(0xFFFFC300));
  for (var r = 0; r < 3; r++) {
    final y = s.rowY(r);
    paintBox(c, Rect.fromLTWH(0, y, kWorldW, 40), const Color(0xFF8B5E34), radius: 4);
    for (final f in s.figs.where((f) => f.row == r)) {
      final fall = f.down ? clampD((s.ticks - f.downAt) / 12, 0, 1) : 0.0;
      c.save();
      c.translate(f.x, y);
      c.transform(Matrix4.diagonal3Values(1, math.cos(fall * math.pi / 2) + 0.01, 1).storage);
      c.drawRect(const Rect.fromLTWH(-6, -40, 12, 40), Paint()..color = const Color(0xFF5C3D2E));
      switch (f.kind) {
        case 0:
          c.drawOval(const Rect.fromLTWH(-55, -110, 100, 64), Paint()..color = const Color(0xFFFFD60A));
          c.drawCircle(const Offset(30, -120), 28, Paint()..color = const Color(0xFFFFD60A));
          c.drawPath(Path()..moveTo(52, -124)..lineTo(78, -116)..lineTo(52, -108)..close(), Paint()..color = const Color(0xFFFF8800));
          c.drawCircle(const Offset(36, -126), 5, Paint()..color = Colors.black);
        case 1:
          paintBox(c, const Rect.fromLTWH(-40, -140, 80, 100), const Color(0xFFADB5BD), radius: 8);
          c.drawRect(const Rect.fromLTWH(-40, -110, 80, 30), Paint()..color = p.piece(f.row + 1));
        case 2:
          paintText(c, '★', const Offset(0, -95), 120, const Color(0xFFFFC300));
        default:
          paintBox(c, const Rect.fromLTWH(-55, -140, 110, 100), Colors.white, radius: 10);
          c.drawCircle(const Offset(0, -90), 38, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..color = const Color(0xFFD00000));
          c.drawLine(const Offset(-26, -116), const Offset(26, -64), Paint()
            ..strokeWidth = 10
            ..color = const Color(0xFFD00000));
      }
      c.restore();
    }
  }
  paintFxList(c, s.fx, s.ticks, p);
  // şarjör şeridi
  paintBox(c, const Rect.fromLTWH(40, kReloadY - 60, 920, 120), const Color(0xFF3A2618), radius: 24);
  for (var i = 0; i < 6; i++) {
    final full = i < s.ammo;
    paintBox(c, Rect.fromLTWH(90.0 + i * 70, kReloadY - 40, 40, 80), full ? const Color(0xFFE9C46A) : Colors.white12, radius: 14, shade: false);
  }
  paintText(c, '↻', const Offset(820, kReloadY), 70, s.ammo == 0 ? const Color(0xFFFFC300) : Colors.white38);
}

Sfx? gallerySound(ArcadeSim sim) => switch ((sim as GallerySim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.coin,
      3 => Sfx.error,
      4 => Sfx.unlock,
      5 => Sfx.tap,
      _ => null,
    };

KitRules galleryRules(String id) => KitRules(
      id,
      optionalMechanics: const ['decoys'],
      gameStats: const [
        GameStat('figures_hit', 'Vurulan figür', 'Figures hit', scale: 300),
        GameStat('stars_hit', 'Vurulan yıldız', 'Stars hit', scale: 30),
      ],
      missionTemplates: const [
        MissionTemplate('figures_hit', 'figures_hit', [30, 60, 120]),
        MissionTemplate('stars_hit', 'stars_hit', [3, 6, 12]),
      ],
      make: GallerySim.new,
      botFn: galleryBot,
    );
