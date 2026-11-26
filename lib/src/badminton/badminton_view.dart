import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import '../texts.dart';
import 'badminton.dart';

void _racketPlayer(Canvas c, double x, double y, Color col, double swing, bool top) {
  final dir = top ? 1.0 : -1.0;
  c.drawOval(Rect.fromCenter(center: Offset(x + 6, y + 14), width: 74, height: 34), Paint()..color = Colors.black26);
  c.drawCircle(Offset(x, y), 30, Paint()..color = col);
  c.drawCircle(Offset(x, y + dir * 6), 13, Paint()..color = const Color(0xFFE0AC69));
  final a = -0.6 + swing * 1.6;
  final hand = Offset(x + 30, y + dir * 6);
  final head = hand + Offset(math.cos(a) * 56, dir * math.sin(a).abs() * 40 + dir * 30);
  c.drawLine(hand, head, Paint()
    ..color = const Color(0xFF343A40)
    ..strokeWidth = 5);
  c.drawOval(Rect.fromCenter(center: head, width: 40, height: 50), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = const Color(0xFFF1FAEE));
}

void _shuttle(Canvas c, Offset o, double r, double ang) {
  c.save();
  c.translate(o.dx, o.dy);
  c.rotate(ang);
  final skirt = Path()
    ..moveTo(0, -r * 0.5)
    ..lineTo(-r * 2.2, -r * 1.2)
    ..lineTo(-r * 2.2, r * 1.2)
    ..lineTo(0, r * 0.5)
    ..close();
  c.drawPath(skirt, Paint()..color = Colors.white);
  c.drawPath(skirt, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.black26);
  c.drawCircle(Offset.zero, r * 0.7, Paint()..color = const Color(0xFFFFB703));
  c.restore();
}

void paintBadminton(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as BadmintonSim;
  final lang = arcadeLang;
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = const Color(0xFF3A5A40));
  const court = Rect.fromLTRB(kBdL, kBdT, kBdR, kBdB);
  c.drawRect(court.inflate(30), Paint()..color = const Color(0xFF52796F));
  c.drawRect(court, Paint()..color = const Color(0xFF2D6A4F));
  final line = Paint()
    ..color = Colors.white
    ..strokeWidth = 5
    ..style = PaintingStyle.stroke;
  c.drawRect(court, line);
  // Kısa servis çizgileri ve orta çizgi
  for (final y in [kBdNet - 180, kBdNet + 180]) {
    c.drawLine(Offset(kBdL, y), Offset(kBdR, y), line);
  }
  c.drawLine(const Offset(500, kBdT), const Offset(500, kBdNet - 180), line);
  c.drawLine(const Offset(500, kBdNet + 180), const Offset(500, kBdB), line);
  c.drawLine(const Offset(kBdL + 40, kBdT), const Offset(kBdL + 40, kBdB), line..strokeWidth = 3);
  c.drawLine(const Offset(kBdR - 40, kBdT), const Offset(kBdR - 40, kBdB), line);
  // Rakip
  final rs = clampD((s.ticks - s.rivalSwingAt) / 12, 0, 1);
  _racketPlayer(c, s.cx, s.cy, p.piece(3), s.ticks - s.rivalSwingAt < 12 ? rs : 0, true);
  // File
  c.drawRect(const Rect.fromLTRB(kBdL - 40, kBdNet - 4, kBdR + 40, kBdNet + 18), Paint()..color = Colors.black26);
  c.drawRect(const Rect.fromLTRB(kBdL - 40, kBdNet - 10, kBdR + 40, kBdNet + 6), Paint()..color = const Color(0xFFF1FAEE));
  for (var x = kBdL - 30; x < kBdR + 40; x += 20) {
    c.drawLine(Offset(x, kBdNet - 10), Offset(x, kBdNet + 6), Paint()
      ..color = Colors.black26
      ..strokeWidth = 2);
  }
  c.drawCircle(const Offset(kBdL - 40, kBdNet - 2), 10, Paint()..color = const Color(0xFF6C584C));
  c.drawCircle(const Offset(kBdR + 40, kBdNet - 2), 10, Paint()..color = const Color(0xFF6C584C));
  // Oyuncu
  final ms = clampD((s.ticks - s.swingAt) / 12, 0, 1);
  _racketPlayer(c, s.px, s.py, p.piece(0), s.ticks - s.swingAt < 12 ? ms : 0, false);
  if (s.power > 0) paintText(c, at(lang, 'smash'), Offset(s.px, s.py + 70), 30, const Color(0xFFFFD60A));
  if (s.power < 0) paintText(c, '↓', Offset(s.px, s.py + 70), 40, const Color(0xFF90E0EF));
  // Tüy top: gölge yerde, top yüksekliğe göre yukarıda
  final sh = Offset(s.bx, s.by);
  c.drawOval(Rect.fromCenter(center: sh, width: 26, height: 12), Paint()..color = Colors.black38);
  final up = Offset(s.bx, s.by - s.bz * 0.75);
  final r = 9 + s.bz / 40;
  final ang = s.live ? math.atan2(-s.vy + s.vz * 0.75, -s.vx) : -math.pi / 2;
  _shuttle(c, up, r, ang);
  // Yazılar
  if (s.flashTicks > 0) {
    final (String txt, Color col) = switch (s.flash) {
      1 => (at(lang, 'point'), const Color(0xFFFFD60A)),
      2 => (at(lang, 'out'), Colors.white),
      3 => ('${at(lang, 'point')} ×', const Color(0xFFE63946)),
      4 => (at(lang, 'set'), const Color(0xFFFFD60A)),
      5 => ('${at(lang, 'set')} ×', const Color(0xFFE63946)),
      6 => (at(lang, 'net'), Colors.white),
      _ => ('', Colors.white),
    };
    if (txt.isNotEmpty) paintText(c, txt, const Offset(500, 700), 76, col);
  }
}

Sfx? badmintonSound(ArcadeSim sim) => switch ((sim as BadmintonSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      4 => Sfx.combo,
      _ => null,
    };
