import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'snake_engine.dart';

void paintSnake(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as SnakeSim;
  final cs = s.cellSize, top = s.top;
  final board = Rect.fromLTWH(0, top, kWorldW, s.rows * cs);
  c.drawRRect(RRect.fromRectAndRadius(board, const Radius.circular(18)), Paint()..color = Colors.black26);
  // checker
  final light = Paint()..color = Colors.white.withValues(alpha: 0.04);
  for (var y = 0; y < s.rows; y++) {
    for (var x = 0; x < s.cols; x++) {
      if ((x + y).isEven) c.drawRect(Rect.fromLTWH(x * cs, top + y * cs, cs, cs), light);
    }
  }
  Rect cell(int i, [double inset = 2]) =>
      Rect.fromLTWH((i % s.cols) * cs + inset, top + (i ~/ s.cols) * cs + inset, cs - inset * 2, cs - inset * 2);
  final wall = Paint()..color = const Color(0xFF6B7A8F);
  for (final w in s.level.walls) {
    c.drawRRect(RRect.fromRectAndRadius(cell(w), const Radius.circular(6)), wall);
  }
  for (var i = 0; i < s.level.portals.length; i++) {
    final col = i < 2 ? const Color(0xFF9B5DE5) : const Color(0xFF00BBF9);
    c.drawCircle(cell(s.level.portals[i]).center, cs * 0.42, Paint()..color = col.withValues(alpha: 0.35));
    c.drawCircle(cell(s.level.portals[i]).center, cs * 0.42,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
  }
  if (s.moverCell >= 0) {
    c.drawRRect(RRect.fromRectAndRadius(cell(s.moverCell), const Radius.circular(10)),
        Paint()..color = const Color(0xFFE63946));
    paintText(c, '!', cell(s.moverCell).center, cs * 0.6, Colors.white);
  }
  if (s.food >= 0) {
    final pulse = 1 + 0.08 * (t * 6).remainder(2).abs();
    c.drawCircle(cell(s.food).center, cs * 0.36 * pulse, Paint()..color = const Color(0xFFFF595E));
    c.drawCircle(cell(s.food).center.translate(-cs * 0.1, -cs * 0.12), cs * 0.08, Paint()..color = Colors.white70);
  }
  if (s.golden >= 0) {
    c.drawCircle(cell(s.golden).center, cs * 0.4, Paint()..color = const Color(0xFFFFCA3A));
    paintText(c, '★', cell(s.golden).center, cs * 0.55, Colors.white);
  }
  if (s.poisonCell >= 0) {
    c.drawCircle(cell(s.poisonCell).center, cs * 0.34, Paint()..color = const Color(0xFF6A994E));
    paintText(c, '☠', cell(s.poisonCell).center, cs * 0.5, Colors.white);
  }
  final head = p.piece(0);
  for (var i = s.body.length - 1; i >= 0; i--) {
    final k = i / s.body.length;
    final col = Color.lerp(head, p.piece(1), k)!;
    final blink = s.shield > 0 && (s.ticks ~/ 6).isOdd;
    c.drawRRect(RRect.fromRectAndRadius(cell(s.body[i], i == 0 ? 1 : 3), Radius.circular(cs * 0.3)),
        Paint()..color = blink ? col.withValues(alpha: 0.4) : col);
  }
  // eyes
  final h = cell(s.head).center;
  const ex = [0.0, 1.0, 0.0, -1.0], ey = [-1.0, 0.0, 1.0, 0.0];
  final fx = ex[s.dir], fy = ey[s.dir];
  for (final side in [-1.0, 1.0]) {
    final o = Offset(h.dx + fx * cs * 0.15 + -fy * side * cs * 0.18, h.dy + fy * cs * 0.15 + fx * side * cs * 0.18);
    c.drawCircle(o, cs * 0.1, Paint()..color = Colors.white);
    c.drawCircle(o + Offset(fx * cs * 0.04, fy * cs * 0.04), cs * 0.05, Paint()..color = Colors.black);
  }
}

Sfx? snakeSound(ArcadeSim sim) => switch ((sim as SnakeSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.coin,
      3 => Sfx.error,
      4 => Sfx.lose,
      _ => null,
    };

