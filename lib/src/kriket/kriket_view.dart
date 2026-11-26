import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import '../kit/kit.dart';
import '../texts.dart';
import 'kriket.dart';

const double _y0 = 380, _y1 = 1380;

double _f(double u) => u * u * 0.35 + u * 0.65;
double _sy(double u) => _y0 + (_y1 - _y0) * _f(u);
double _hw(double u) => 60 + 210 * _f(u);

void _figure(Canvas c, Offset feet, double s, Color shirt, {double bat = 0, bool batter = false}) {
  final skin = Paint()..color = const Color(0xFFE0AC69);
  c.drawOval(Rect.fromCenter(center: feet + Offset(0, 4 * s), width: 60 * s, height: 14 * s), Paint()..color = Colors.black26);
  final legs = Paint()
    ..color = Colors.white
    ..strokeWidth = 10 * s
    ..strokeCap = StrokeCap.round;
  c.drawLine(feet + Offset(-10 * s, 0), feet + Offset(-6 * s, -50 * s), legs);
  c.drawLine(feet + Offset(10 * s, 0), feet + Offset(6 * s, -50 * s), legs);
  final body = RRect.fromRectAndRadius(Rect.fromCenter(center: feet + Offset(0, -78 * s), width: 40 * s, height: 60 * s), Radius.circular(12 * s));
  c.drawRRect(body, Paint()..color = shirt);
  c.drawCircle(feet + Offset(0, -122 * s), 15 * s, skin);
  c.drawArc(Rect.fromCircle(center: feet + Offset(0, -126 * s), radius: 16 * s), math.pi, math.pi, true, Paint()..color = const Color(0xFF1D3557));
  if (batter) {
    c.save();
    c.translate(feet.dx + 14 * s, feet.dy - 84 * s);
    c.rotate(0.9 - bat * 2.2);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-6 * s, 0, 12 * s, 80 * s), Radius.circular(4 * s)), Paint()..color = const Color(0xFFDDB892));
    c.drawLine(Offset.zero, Offset(0, 22 * s), Paint()
      ..color = const Color(0xFF343A40)
      ..strokeWidth = 7 * s);
    c.restore();
  }
}

void _stumps(Canvas c, double u, double s) {
  final y = _sy(u);
  final p = Paint()
    ..color = const Color(0xFFFFF3B0)
    ..strokeWidth = 5 * s
    ..strokeCap = StrokeCap.round;
  for (final dx in [-12.0, 0.0, 12.0]) {
    c.drawLine(Offset(500 + dx * s, y), Offset(500 + dx * s, y - 60 * s), p);
  }
  c.drawLine(Offset(500 - 15 * s, y - 62 * s), Offset(500 + 15 * s, y - 62 * s), p..strokeWidth = 3 * s);
}

void paintCricket(Canvas c, ArcadeSim sim, ArcadePalette p, double tt) {
  final s = sim as CricketSim;
  final lang = arcadeLang;
  // Saha ve tribün
  paintSky(c, const Color(0xFF2D6A4F), const Color(0xFF74C69D));
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, 250), Paint()..color = const Color(0xFF1B263B));
  for (var i = 0; i < 60; i++) {
    final x = (i * 37 % 1000).toDouble(), y = 60.0 + (i * 53 % 170);
    c.drawCircle(Offset(x, y), 7, Paint()..color = p.piece(i).withValues(alpha: 0.55));
  }
  c.drawArc(Rect.fromCenter(center: const Offset(500, 1500), width: 1900, height: 2500), math.pi * 1.06, math.pi * 0.88, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white70);
  // Biçilmiş çim şeritleri
  for (var i = 0; i < 8; i++) {
    c.drawRect(Rect.fromLTWH(0, 260.0 + i * 170, kWorldW, 85), Paint()..color = Colors.white.withValues(alpha: 0.04));
  }
  // Vuruş bölgeleri (soluk kılavuz)
  final guide = Paint()
    ..color = Colors.white.withValues(alpha: 0.07)
    ..strokeWidth = 3;
  c.drawLine(const Offset(333, 260), const Offset(333, 1600), guide);
  c.drawLine(const Offset(667, 260), const Offset(667, 1600), guide);
  c.drawLine(const Offset(0, 1000), const Offset(kWorldW, 1000), guide);
  // Pist
  final pitch = Path()
    ..moveTo(500 - _hw(-0.05), _sy(-0.05))
    ..lineTo(500 + _hw(-0.05), _sy(-0.05))
    ..lineTo(500 + _hw(1.12), _sy(1.12))
    ..lineTo(500 - _hw(1.12), _sy(1.12))
    ..close();
  c.drawPath(pitch, Paint()..color = const Color(0xFFD4A373));
  final crease = Paint()
    ..color = Colors.white
    ..strokeWidth = 4;
  for (final u in [0.02, 1.0]) {
    c.drawLine(Offset(500 - _hw(u) * 1.15, _sy(u)), Offset(500 + _hw(u) * 1.15, _sy(u)), crease);
  }
  _stumps(c, -0.02, 0.55);
  // Atıcı
  final b = s.ball;
  final run = b == null ? clampD((kCrGap - s.wait) / kCrGap, 0, 1) : 1.0;
  final bowlerY = _sy(-0.2 + 0.18 * run);
  _figure(c, Offset(470, bowlerY), 0.45, const Color(0xFFE63946));
  // Saha oyuncuları haritası (sağ üst)
  const mc = Offset(860, 175);
  c.drawOval(Rect.fromCenter(center: mc, width: 230, height: 150), Paint()..color = const Color(0xFF40916C));
  c.drawOval(Rect.fromCenter(center: mc, width: 230, height: 150), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.white70);
  final bat = mc + const Offset(0, 55);
  c.drawCircle(bat, 6, Paint()..color = Colors.white);
  for (var i = 0; i < 3; i++) {
    final a = -math.pi / 2 + (i - 1) * 0.85;
    final deep = bat + Offset(math.cos(a) * 118, math.sin(a) * 108);
    final ring = bat + Offset(math.cos(a) * 60, math.sin(a) * 55);
    if (s.deep[i]) c.drawCircle(deep, 9, Paint()..color = const Color(0xFF1D3557));
    if (s.ring[i]) c.drawCircle(ring, 8, Paint()..color = const Color(0xFF457B9D));
  }
  if (s.level.goal) {
    paintText(c, '${s.ballsLeft} ${at(lang, 'balls')}', const Offset(150, 175), 42, Colors.white);
  }
  // Vurucu ve yakın kale
  _stumps(c, 1.04, 1.25);
  final swing = clampD((s.ticks - s.swingAt) / 14, 0, 1);
  _figure(c, Offset(415, _sy(1.0) + 40), 1.25, const Color(0xFF1D4E89), bat: s.ticks - s.swingAt < 14 ? swing : 0, batter: true);
  // Top
  if (b != null && s.bt >= 0 && !(s.swung && s.shotQ > 0)) {
    final u = s.u;
    final (lx, h) = b.at(u);
    final x = 500 + lx * _hw(u) * 0.9;
    final y = _sy(u);
    final sc = 0.4 + 0.6 * _f(u);
    paintShadow(c, Offset(x, y), 26 * sc + 6);
    paintBall(c, Offset(x, y - h * sc), 9 + 13 * _f(u), const Color(0xFFC1121F));
    // Rehber (güçlendirici): ideal ana kalan süre halkası
    if (s.shield > 0 && u >= kCrReady) {
      final left = (b.t - s.bt).clamp(0, 30);
      c.drawCircle(Offset(x, y - h * sc), 22.0 + left * 5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFFD60A));
    }
  }
  // Vurulan top uçuşu
  if (s.shotQ > 0 && s.ticks - s.shotAt < 45) {
    final k = (s.ticks - s.shotAt) / 45;
    final dir = (s.shotDir - 1).toDouble();
    final x = 470 + dir * 520 * k;
    final y = _sy(1.0) - 900 * k;
    final lift = s.shotAir ? math.sin(k * math.pi) * 260 : 0.0;
    final r = s.shotAir ? 22 - 8 * k + math.sin(k * math.pi) * 10 : 20 - 10 * k;
    paintShadow(c, Offset(x, y), r * 2);
    paintBall(c, Offset(x, y - lift), r, const Color(0xFFC1121F));
  }
  // Sonuç
  final age = s.ticks - s.resultAt;
  if (age < 60 && s.result != -4) {
    final (String txt, Color col) = switch (s.result) {
      -2 => (at(lang, 'bowled'), const Color(0xFFE63946)),
      -3 => (at(lang, 'caught'), const Color(0xFFE63946)),
      -5 => (at(lang, 'extra_over'), const Color(0xFFFFB703)),
      6 => ('6!', const Color(0xFFFFD60A)),
      4 => ('4!', const Color(0xFFFFD60A)),
      _ => ('${s.result}', Colors.white),
    };
    final sz = s.result >= 4 ? 150.0 : 80.0;
    paintText(c, txt, Offset(500, 620 - age * 1.5), sz * (0.8 + 0.2 * math.min(1.0, age / 8)), col);
  }
  if (s.bowled < 2 && !s.meta.zen) {
    paintText(c, at(lang, 'cr_hint'), const Offset(500, 1555), 27, Colors.white70);
  }
}

Sfx? cricketSound(ArcadeSim sim) => switch ((sim as CricketSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.combo,
      3 => Sfx.lose,
      4 => Sfx.error,
      5 => Sfx.tap,
      _ => null,
    };
