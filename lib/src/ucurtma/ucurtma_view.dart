import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import '../kit/kit.dart';
import '../texts.dart';
import 'ucurtma.dart';

void _string(Canvas c, double ax, double ay, UcKite k, Color col) {
  if (k.free) return;
  final mid = Offset((ax + k.x) / 2, (ay + k.y) / 2 + 40);
  c.drawPath(
      Path()
        ..moveTo(ax, ay)
        ..quadraticBezierTo(mid.dx, mid.dy, k.x, k.y),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = col);
}

void _kite(Canvas c, UcKite k, Color col, double t, int seed) {
  c.save();
  c.translate(k.x, k.y);
  c.rotate(clampD(k.vx * 0.04, -0.5, 0.5) + (k.free ? t * 3 : 0) + (k.stun > 0 ? math.sin(t * 30) * 0.4 : 0));
  // Kuyruk
  final tail = Path()..moveTo(0, 60);
  for (var i = 1; i <= 6; i++) {
    tail.lineTo(math.sin(t * 6 + i + seed) * 18, 60 + i * 28.0);
  }
  c.drawPath(tail, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..color = col.withValues(alpha: 0.8));
  final body = Path()
    ..moveTo(0, -60)
    ..lineTo(46, 0)
    ..lineTo(0, 60)
    ..lineTo(-46, 0)
    ..close();
  c.drawPath(body.shift(const Offset(6, 8)), Paint()..color = Colors.black12);
  c.drawPath(body, Paint()..color = col);
  final half = Path()
    ..moveTo(0, -60)
    ..lineTo(46, 0)
    ..lineTo(0, 60)
    ..close();
  c.drawPath(half, Paint()..color = Colors.white.withValues(alpha: 0.25));
  final frame = Paint()
    ..color = const Color(0xFF6C584C)
    ..strokeWidth = 3;
  c.drawLine(const Offset(0, -60), const Offset(0, 60), frame);
  c.drawLine(const Offset(-46, 0), const Offset(46, 0), frame);
  c.restore();
}

void paintKite(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as KiteSim;
  final lang = arcadeLang;
  paintSky(c, const Color(0xFF48CAE4), const Color(0xFFFFE8D6));
  c.drawCircle(const Offset(820, 300), 70, Paint()..color = const Color(0xFFFFD166).withValues(alpha: 0.8));
  // Bulutlar
  for (var i = 0; i < 5; i++) {
    final x = ((i * 260 + s.ticks * (0.3 + i * 0.08)) % 1300) - 150;
    final y = 260.0 + i * 170;
    final cl = Paint()..color = Colors.white.withValues(alpha: 0.7);
    c.drawCircle(Offset(x, y), 40, cl);
    c.drawCircle(Offset(x + 45, y - 15), 50, cl);
    c.drawCircle(Offset(x + 95, y), 38, cl);
  }
  // Kuşlar
  for (final b in s.birds) {
    final x = b.$1 + (s.ticks - b.$3) * 4;
    final y = b.$2 + math.sin(s.ticks / 9) * 12;
    final w = math.sin(s.ticks / 5) * 10;
    c.drawPath(
        Path()
          ..moveTo(x - 26, y - w)
          ..quadraticBezierTo(x - 10, y - 12, x, y)
          ..quadraticBezierTo(x + 10, y - 12, x + 26, y - w),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF343A40));
  }
  // Çatılar
  final roofs = [(0.0, 1420.0, 300.0), (270.0, 1460.0, 230.0), (480.0, 1430.0, 200.0), (660.0, 1450.0, 340.0)];
  for (final (x, y, w) in roofs) {
    c.drawRect(Rect.fromLTWH(x, y, w, kWorldH - y), Paint()..color = const Color(0xFFB08968));
    c.drawRect(Rect.fromLTWH(x, y - 14, w, 14), Paint()..color = const Color(0xFF7F5539));
    for (var wx = x + 30; wx < x + w - 30; wx += 70) {
      c.drawRect(Rect.fromLTWH(wx, y + 50, 30, 40), Paint()..color = const Color(0xFFFFF3B0).withValues(alpha: 0.6));
    }
  }
  // Uçurtmacılar
  for (final (ax, col) in [(kUcAx0, p.piece(0)), (kUcAx1, p.piece(3))]) {
    c.drawCircle(Offset(ax, kUcAy - 40), 22, Paint()..color = col);
    c.drawCircle(Offset(ax, kUcAy - 78), 16, Paint()..color = const Color(0xFFE0AC69));
    c.drawCircle(Offset(ax + (ax < 500 ? 22 : -22), kUcAy - 30), 12, Paint()..color = const Color(0xFFDDB892));
  }
  _string(c, kUcAx0, kUcAy - 30, s.me, Colors.white);
  _string(c, kUcAx1, kUcAy - 30, s.foe, const Color(0xFF1D3557));
  _kite(c, s.foe, p.piece(3), t, 7);
  _kite(c, s.me, p.piece(0), t, 1);
  // Sürtünme kıvılcımı ve üstünlük göstergesi
  if (s.contact) {
    for (var i = 0; i < 6; i++) {
      final a = s.ticks * 0.7 + i;
      c.drawCircle(Offset(s.cxp + math.cos(a) * 18, s.cyp + math.sin(a) * 18), 5, Paint()..color = const Color(0xFFFFB703));
    }
  }
  if (s.contact || s.saw.abs() > 5) {
    final k = clampD(s.saw / kUcCut, -1, 1);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(250, 180, 500, 26), const Radius.circular(13)), Paint()..color = Colors.black26);
    c.drawRect(Rect.fromLTRB(500, 182, 500 + k * 248, 204), Paint()..color = k >= 0 ? p.piece(0) : p.piece(3));
    c.drawLine(const Offset(500, 172), const Offset(500, 214), Paint()
      ..color = Colors.white
      ..strokeWidth = 4);
  }
  // Rüzgâr
  final w = s.wind(s.ticks);
  final na = math.min(3, 1 + (w.abs() * 1.5).floor());
  final arrow = w > 0.15 ? '→' * na : (w < -0.15 ? '←' * na : '·');
  paintText(c, '${at(lang, 'wind')} $arrow', const Offset(150, 250), 32, const Color(0xFF023047));
  if (s.flashTicks > 0) {
    final good = s.flash == 1 || s.flash == 4;
    final key = switch (s.flash) { 1 => 'cut', 2 => 'got_cut', 3 => 'kite_down', _ => 'foe_down' };
    paintText(c, at(lang, key), const Offset(500, 620), 64, good ? const Color(0xFFFFD60A) : const Color(0xFFE63946));
  }
}

Sfx? kiteSound(ArcadeSim sim) => switch ((sim as KiteSim).lastEvent) {
      1 => Sfx.combo,
      2 => Sfx.lose,
      5 => Sfx.tap,
      _ => null,
    };
