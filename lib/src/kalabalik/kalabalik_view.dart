import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import '../texts.dart';
import 'kalabalik.dart';

void _crowd(Canvas c, Offset o, int n, Color col, double t, {double spread = 1}) {
  final m = math.min(n, 90);
  const ga = 2.399963;
  for (var i = 0; i < m; i++) {
    final r = 13.0 * math.sqrt(i + 0.5) * spread;
    final a = i * ga;
    final bob = math.sin(t * 12 + i) * 3;
    final p = o + Offset(math.cos(a) * r, math.sin(a) * r * 0.7 + bob);
    c.drawCircle(p + const Offset(2, 4), 10, Paint()..color = Colors.black26);
    c.drawCircle(p, 10, Paint()..color = col);
    c.drawCircle(p - const Offset(3, 3), 3.5, Paint()..color = Colors.white38);
  }
}

void _bubble(Canvas c, Offset o, String s, Color bg) {
  final w = 40.0 + s.length * 22;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: w, height: 64), const Radius.circular(32)), Paint()..color = bg);
  paintText(c, s, o, 40, Colors.white);
}

void paintCrowd(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as CrowdSim;
  final lang = arcadeLang;
  double sy(double d) => kKlRunnerY - (d - s.dist);
  // Çimen ve yol
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = const Color(0xFF95D5B2));
  c.drawRect(const Rect.fromLTRB(kKlL, 0, kKlR, kWorldH), Paint()..color = const Color(0xFF5C677D));
  final edge = Paint()..color = Colors.white;
  c.drawRect(const Rect.fromLTRB(kKlL - 10, 0, kKlL, kWorldH), edge);
  c.drawRect(const Rect.fromLTRB(kKlR, 0, kKlR + 10, kWorldH), edge);
  final off = s.dist % 160;
  for (var y = -160.0 + off; y < kWorldH; y += 160) {
    c.drawRect(Rect.fromLTWH(495, y, 10, 70), Paint()..color = Colors.white24);
  }
  for (var y = -220.0 + (s.dist * 0.9) % 220; y < kWorldH; y += 220) {
    c.drawCircle(Offset(70, y), 34, Paint()..color = const Color(0xFF52B788));
    c.drawCircle(Offset(930, y + 110), 34, Paint()..color = const Color(0xFF52B788));
  }
  final split = s.split(s.ticks.toDouble());
  for (final r in s.rows) {
    final gy = sy(r.at);
    if (gy > kWorldH + 120 || gy < -900) continue;
    // Kapılar
    for (var side = 0; side < 2; side++) {
      final g = side == 0 ? r.left : r.right;
      final rect = side == 0 ? Rect.fromLTRB(kKlL, gy - 70, split - 6, gy) : Rect.fromLTRB(split + 6, gy - 70, kKlR, gy);
      final faded = r.passed && r.chosen != side;
      final col = (g.good ? const Color(0xFF00B4D8) : const Color(0xFFE63946)).withValues(alpha: faded ? 0.15 : 0.55);
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = col);
      if (!r.passed) paintText(c, g.label, rect.center, 54, Colors.white);
    }
    c.drawRect(Rect.fromLTRB(split - 6, gy - 90, split + 6, gy + 6), Paint()..color = Colors.white70);
    // Engel
    if (r.barSide >= 0 && !r.barDone) {
      final by = sy(r.at + 200);
      final x0 = r.barSide == 0 ? kKlL : split, x1 = r.barSide == 0 ? split : kKlR;
      for (var x = x0; x < x1; x += 40) {
        c.drawRect(Rect.fromLTWH(x, by - 24, 20, 24), Paint()..color = const Color(0xFFFF8800));
        c.drawRect(Rect.fromLTWH(x + 20, by - 24, 20, 24), Paint()..color = Colors.white);
      }
    }
    // Rakip grup
    if (r.rivalSide >= 0 && !r.rivalDone) {
      final ry = sy(r.at + 550);
      final rx = r.rivalSide == 0 ? (kKlL + split) / 2 : (split + kKlR) / 2;
      _crowd(c, Offset(rx, ry), r.rival, const Color(0xFFD62828), t, spread: 0.8);
      _bubble(c, Offset(rx, ry - 90), '${r.rival}', const Color(0xFFD62828));
    }
  }
  // Rakip kule (son)
  if (s.level.goal) {
    final fy = sy(s.finishAt);
    if (fy > -300 && fy < kWorldH + 200) {
      c.drawRect(Rect.fromLTRB(kKlL, fy - 8, kKlR, fy + 8), Paint()..color = Colors.white);
      final h = math.min(420.0, 80 + math.sqrt(s.finalTower) * 14);
      final tower = Rect.fromCenter(center: Offset(500, fy - 40 - h / 2), width: 260, height: h);
      final shake = s.finale ? math.sin(s.ticks * 1.3) * 6 : 0.0;
      c.drawRRect(RRect.fromRectAndRadius(tower.shift(Offset(shake, 0)), const Radius.circular(18)), Paint()..color = const Color(0xFFD62828));
      for (var y = tower.top + 20; y < tower.bottom - 10; y += 34) {
        for (var x = tower.left + 22; x < tower.right - 10; x += 34) {
          c.drawCircle(Offset(x + shake, y), 9, Paint()..color = Colors.white24);
        }
      }
      _bubble(c, Offset(500 + shake, tower.top - 50), '${s.finalTower}', const Color(0xFF9D0208));
    }
  }
  // Kalabalık
  final o = Offset(s.cx, kKlRunnerY - 60);
  _crowd(c, o, math.max(0, s.n), p.piece(0), t);
  _bubble(c, o + Offset(0, -s.radius - 70), '${s.n}', const Color(0xFF1D4E89));
  final age = s.ticks - s.deltaAt;
  if (age < 40 && s.lastDelta != 0) {
    final d = s.lastDelta;
    paintText(c, d > 0 ? '+$d' : '$d', o + Offset(170, -120 - age * 2.0), 60, d > 0 ? const Color(0xFFFFD60A) : const Color(0xFFE63946));
  }
  if (s.finale) {
    paintText(c, at(lang, 'push'), const Offset(500, 420), 110, const Color(0xFFFFD60A));
    paintText(c, '${s.n}  vs  ${s.finalTower}', const Offset(500, 540), 60, Colors.white);
  }
}

Sfx? crowdSound(ArcadeSim sim) => switch ((sim as CrowdSim).lastEvent) {
      1 => Sfx.coin,
      2 => Sfx.error,
      3 => Sfx.place,
      4 => Sfx.combo,
      _ => null,
    };
