import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Pong: alt raket oyuncunun, üst raket rakibin. Topu raketin kenarıyla
/// karşılamak açıyı sertleştirir. Rakip sayı alırsa can gider.
const double kPadY = 1400, kAiY = 200, kPadH = 28, kBallR = 22;

class PongSim extends ArcadeSim {
  final ALevel level;
  late double padW = level.has('small') ? 170 : 210;
  double px = 500, ax = 500;
  double bx = 500, by = 800, bvx = 0, bvy = 0;
  int me = 0, them = 0, rally = 0, longest = 0, returns = 0, serveIn = 50, lastEvent = 0;
  late final int goalPts = level.target(3, 1) == 0 ? 0 : 3 + (level.d + 1) ~/ 2;
  late final double aiSpeed = 7 + level.d * 0.4;
  double aiErr = 0;
  late final double baseSpeed = 11 + level.d * 0.45;
  final List<double> obstacles = []; // orta bloklar (x merkezleri)

  PongSim(this.level) : super(level.meta) {
    if (level.has('blocks')) {
      obstacles.addAll([250, 750]);
    }
  }

  void _serve(int dir) {
    bx = 500;
    by = 800;
    final a = (rng.nextDouble() - 0.5) * 0.8;
    bvx = math.sin(a) * baseSpeed;
    bvy = math.cos(a) * baseSpeed * dir;
    rally = 0;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.hasPointer && input.down) {
      px = moveToward(px, input.x, 42);
    } else if (input.dirX != 0) {
      px += input.dirX * 18;
    }
    px = clampD(px, padW / 2, kWorldW - padW / 2);
    if (serveIn > 0) {
      serveIn--;
      if (serveIn == 0) _serve(rng.chance(0.5) ? 1 : -1);
      return;
    }
    // Rakip: top kendine geliyorsa izler, gecikmeli.
    final target = bvy < 0 ? predictX(kAiY + kPadH / 2 + kBallR) + aiErr : 500.0;
    ax = moveToward(ax, target, aiSpeed);
    ax = clampD(ax, padW / 2, kWorldW - padW / 2);
    bx += bvx;
    by += bvy;
    if (bx < kBallR) {
      bx = kBallR;
      bvx = bvx.abs();
    } else if (bx > kWorldW - kBallR) {
      bx = kWorldW - kBallR;
      bvx = -bvx.abs();
    }
    for (final ox in obstacles) {
      if ((bx - ox).abs() < 70 + kBallR && (by - 800).abs() < 20 + kBallR) {
        bvy = -bvy;
        by += bvy;
      }
    }
    // Oyuncu raketi
    if (bvy > 0 && by + kBallR >= kPadY - kPadH / 2 && by < kPadY + kPadH && (bx - px).abs() < padW / 2 + kBallR) {
      _bounce(px, -1);
      returns++;
      // Rakip her karşılamada biraz yanılır; sert açılar daha zor.
      final off = clampD(((bx - px) / (padW / 2)).abs(), 0, 1);
      final errMax = padW * (1.2 - 0.3 * level.k) * (0.6 + off * 0.6);
      aiErr = (rng.nextDouble() * 2 - 1) * errMax;
      lastEvent = 1;
    }
    if (bvy < 0 && by - kBallR <= kAiY + kPadH / 2 && by > kAiY - kPadH && (bx - ax).abs() < padW / 2 + kBallR) {
      _bounce(ax, 1);
      lastEvent = 1;
    }
    if (by > kWorldH + 40) {
      them++;
      serveIn = 60;
      lastEvent = 3;
      hit();
    } else if (by < -40) {
      me++;
      score += 100 + rally * 10;
      serveIn = 60;
      lastEvent = 2;
      if (goalPts > 0 && me >= goalPts) win();
    }
  }

  void _bounce(double padX, int dir) {
    final off = clampD((bx - padX) / (padW / 2), -1, 1);
    final sp = math.min(baseSpeed + rally * 0.5, baseSpeed * 1.8);
    final a = off * 1.05;
    bvx = math.sin(a) * sp;
    bvy = math.cos(a) * sp * dir;
    rally++;
    if (rally > longest) longest = rally;
  }

  /// Topun y hizasına geldiğinde x'i (duvar yansımalarıyla).
  double predictX(double yLine) {
    if (bvy == 0) return bx;
    final t = (yLine - by) / bvy;
    if (t < 0) return bx;
    final span = kWorldW - 2 * kBallR;
    var x = bx - kBallR + bvx * t;
    x = x % (2 * span);
    if (x < 0) x += 2 * span;
    if (x > span) x = 2 * span - x;
    return x + kBallR;
  }

  @override
  void onLifeLost() {
    serveIn = 60;
  }

  @override
  double get progress => goalPts == 0 ? 0 : me / goalPts;
  @override
  String get goalText => '$me : $them';
  @override
  Map<String, int> get stats => {'points_won': me, 'returns': returns, 'longest_rally': longest};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput pongBot(ArcadeSim sim) {
  final s = sim as PongSim;
  if (s.bvy > 0) {
    final x = s.predictX(kPadY - kPadH / 2 - kBallR);
    // Rakibin uzak tarafına sert açı: raketin kenarıyla vur.
    final aim = s.ax > 500 ? -1.0 : 1.0;
    return holdAt(x - aim * s.padW * 0.38, kPadY);
  }
  return holdAt(500, kPadY);
}

void paintPong(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as PongSim;
  paintSky(c, const Color(0xFF14213D), const Color(0xFF0D1B2A));
  const court = Rect.fromLTWH(40, 120, 920, 1360);
  c.drawRRect(RRect.fromRectAndRadius(court, const Radius.circular(30)), Paint()..color = const Color(0xFF1D3557));
  final line = Paint()
    ..color = Colors.white24
    ..strokeWidth = 6;
  for (var x = 60.0; x < 950; x += 60) {
    c.drawLine(Offset(x, 800), Offset(x + 30, 800), line);
  }
  c.drawCircle(const Offset(500, 800), 120, line..style = PaintingStyle.stroke);
  for (final ox in s.obstacles) {
    paintBox(c, Rect.fromCenter(center: Offset(ox, 800), width: 140, height: 40), p.piece(4));
  }
  paintText(c, '${s.them}', const Offset(880, 680), 90, Colors.white24);
  paintText(c, '${s.me}', const Offset(880, 920), 90, Colors.white38);
  paintBox(c, Rect.fromCenter(center: Offset(s.ax, kAiY), width: s.padW, height: kPadH), p.piece(2), radius: 14);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBox(c, Rect.fromCenter(center: Offset(s.px, kPadY), width: s.padW, height: kPadH), blink ? Colors.white54 : p.piece(0), radius: 14);
  if (s.serveIn == 0) {
    for (var i = 1; i <= 3; i++) {
      c.drawCircle(Offset(s.bx - s.bvx * i * 1.5, s.by - s.bvy * i * 1.5), kBallR * (1 - i * 0.2), Paint()..color = Colors.white.withValues(alpha: 0.15));
    }
    paintBall(c, Offset(s.bx, s.by), kBallR, const Color(0xFFF1FAEE));
  }
}

Sfx? pongSound(ArcadeSim sim) => switch ((sim as PongSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules pongRules(String id) => KitRules(
      id,
      optionalMechanics: const ['small', 'blocks'],
      gameStats: const [
        GameStat('points_won', 'Kazanılan sayı', 'Points won', scale: 50),
        GameStat('returns', 'Karşılama', 'Returns', scale: 300),
        GameStat('longest_rally', 'En uzun ralli', 'Longest rally', scale: 5),
      ],
      missionTemplates: const [
        MissionTemplate('points_won', 'points_won', [5, 10, 20]),
        MissionTemplate('returns', 'returns', [20, 50, 100]),
      ],
      make: PongSim.new,
      botFn: pongBot,
    );
