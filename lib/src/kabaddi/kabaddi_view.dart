import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import '../texts.dart';
import 'kabaddi.dart';

void _player(Canvas c, double x, double y, Color col, {bool ring = false, double face = 0}) {
  c.drawOval(Rect.fromCenter(center: Offset(x + 4, y + 10), width: 64, height: 30), Paint()..color = Colors.black26);
  c.drawCircle(Offset(x, y), 30, Paint()..color = col);
  c.drawCircle(Offset(x, y), 30, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..color = Colors.white70);
  c.drawCircle(Offset(x + math.cos(face) * 12, y + math.sin(face) * 12), 12, Paint()..color = const Color(0xFFE0AC69));
  if (ring) {
    c.drawCircle(Offset(x, y), 42, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFFFFD60A));
  }
}

void _dashed(Canvas c, double y, Paint p) {
  for (var x = kKbL; x < kKbR; x += 40) {
    c.drawLine(Offset(x, y), Offset(math.min(x + 22, kKbR), y), p);
  }
}

void paintKabaddi(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as KabaddiSim;
  final lang = arcadeLang;
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = const Color(0xFF264653));
  // Rakip yarı (üst) ve kendi yarın (alt): minder
  c.drawRect(const Rect.fromLTRB(kKbL, kKbTop, kKbR, kKbMid), Paint()..color = const Color(0xFFE76F51));
  c.drawRect(const Rect.fromLTRB(kKbL, kKbMid, kKbR, 1450), Paint()..color = const Color(0xFF2A9D8F));
  final line = Paint()
    ..color = Colors.white
    ..strokeWidth = 5
    ..style = PaintingStyle.stroke;
  c.drawRect(const Rect.fromLTRB(kKbL, kKbTop, kKbR, 1450), line);
  c.drawLine(const Offset(kKbL, kKbMid), const Offset(kKbR, kKbMid), Paint()
    ..color = Colors.white
    ..strokeWidth = 12);
  final thin = Paint()
    ..color = Colors.white70
    ..strokeWidth = 4;
  c.drawLine(const Offset(kKbL, kKbBaulk), const Offset(kKbR, kKbBaulk), thin);
  c.drawLine(const Offset(kKbL, 2 * kKbMid - kKbBaulk), const Offset(kKbR, 2 * kKbMid - kKbBaulk), thin);
  if (s.bonusOn) {
    final bp = Paint()
      ..color = const Color(0xFFFFD60A)
      ..strokeWidth = 4;
    _dashed(c, kKbBonus, bp);
    paintText(c, at(lang, 'bonus'), const Offset(kKbR - 90, kKbBonus - 24), 26, const Color(0xFFFFD60A));
  }
  // Oyundan çıkan savunmacılar (yedek bankı)
  final outs = s.defs.where((d) => d.out).length;
  for (var i = 0; i < outs; i++) {
    c.drawCircle(Offset(60, 200.0 + i * 70), 24, Paint()..color = p.piece(2).withValues(alpha: 0.45));
  }
  // Savunmacılar
  for (final d in s.defs) {
    if (d.out) continue;
    _player(c, d.x, d.y, p.piece(2), ring: d.touched, face: math.atan2(s.ry - d.y, s.rx - d.x));
  }
  // Akıncı
  final caught = s.ticks - s.caughtAt < 50;
  _player(c, s.rx, s.ry, caught ? Colors.grey : p.piece(0), face: -math.pi / 2);
  // Nefes çubuğu
  if (s.raiding) {
    final k = clampD(s.breath / s.breathMax, 0, 1);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(200, 1490, 600, 34), const Radius.circular(17)), Paint()..color = Colors.black38);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(200, 1490, 600 * k, 34), const Radius.circular(17)),
        Paint()..color = Color.lerp(const Color(0xFFE63946), const Color(0xFF90E0EF), k)!);
    paintText(c, at(lang, 'breath'), const Offset(500, 1550), 30, Colors.white);
  }
  // Yazılar
  if (s.ticks - s.gainAt < 60 && s.lastGain > 0) {
    paintText(c, '+${s.lastGain}', Offset(500, 1000 - (s.ticks - s.gainAt) * 2.0), 110, const Color(0xFFFFD60A));
  }
  if (s.ticks - s.allOutAt < 80) paintText(c, at(lang, 'all_out'), const Offset(500, 760), 70, const Color(0xFFFFD60A));
  if (caught) paintText(c, at(lang, 'kb_caught'), const Offset(500, 760), 70, const Color(0xFFFFFFFF));
  if (s.ticks - s.emptyAt < 50) paintText(c, at(lang, 'empty_raid'), const Offset(500, 900), 54, Colors.white70);
  if (s.raiding && s.bonusTaken) paintText(c, '${at(lang, 'bonus')} ✓', Offset(s.rx, s.ry - 70), 30, const Color(0xFFFFD60A));
}

Sfx? kabaddiSound(ArcadeSim sim) => switch ((sim as KabaddiSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.lose,
      4 => Sfx.combo,
      5 => Sfx.unlock,
      6 => Sfx.error,
      _ => null,
    };
