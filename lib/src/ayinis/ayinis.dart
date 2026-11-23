import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Ay'a iniş: basılı tut = ana motor; parmağın gemiye göre sağda/solda
/// olması gemiyi o yöne eğer. İniş pistine yavaş ve dik in. Yakıt sınırlı;
/// rüzgârlı bölümlerde yan itki vardır.
class LanderSim extends ArcadeSim {
  final ALevel level;
  late List<double> terrain; // 41 nokta, x = i * 25
  late double padL, padR, padY;
  double x = 200, y = 250, vx = 1.5, vy = 0, tilt = 0, fuel = 1;
  bool thrust = false;
  int landed = 0, softLandings = 0, crashT = -1, lastEvent = 0, landedAt = -1;
  late final int goalN = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;
  late final double g = 0.045 + level.d * 0.004;
  double wind = 0;

  LanderSim(this.level) : super(level.meta) {
    _newMap();
  }

  static const int kPts = 41;

  double groundAt(double px) {
    final fx = clampD(px / 25, 0, kPts - 1.001);
    final i = fx.floor();
    final f = fx - i;
    return terrain[i] * (1 - f) + terrain[i + 1] * f;
  }

  void _newMap() {
    terrain = List<double>.filled(kPts, 1300);
    var h = 1250.0;
    for (var i = 0; i < kPts; i++) {
      h = clampD(h + (rng.nextDouble() - 0.5) * (120 + level.d * 18), 900, 1450);
      terrain[i] = h;
    }
    final w = math.max(5, 9 - level.d ~/ 2);
    final start = 3 + rng.nextInt(kPts - w - 6);
    padY = terrain[start];
    for (var i = start; i <= start + w; i++) {
      terrain[i] = padY;
    }
    padL = start * 25.0;
    padR = (start + w) * 25.0;
    x = padL > 500 ? 150 : 850;
    y = 220;
    vx = 0;
    vy = 0;
    tilt = 0;
    fuel = 1;
    wind = level.has('wind') ? (rng.nextDouble() - 0.5) * 0.03 : 0;
    landedAt = -1;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (landedAt >= 0) {
      if (ticks - landedAt > 60) {
        _newMap();
      }
      return;
    }
    thrust = false;
    var targetTilt = 0.0;
    if (input.down && input.hasPointer) {
      thrust = fuel > 0;
      targetTilt = clampD((input.x - x) / 400, -0.6, 0.6);
    } else if (input.dirY < 0 || input.dirX != 0) {
      thrust = fuel > 0 && input.dirY < 0;
      targetTilt = input.dirX * 0.5;
    }
    tilt = moveToward(tilt, targetTilt, 0.04);
    if (thrust) {
      vx += math.sin(tilt) * 0.12;
      vy -= math.cos(tilt) * 0.12;
      fuel = math.max(0.0, fuel - (0.0011 + level.d * 0.00008));
    }
    vy += g;
    vx += wind;
    x += vx;
    y += vy;
    if (x < 30 || x > kWorldW - 30) {
      x = clampD(x, 30, kWorldW - 30);
      vx = -vx * 0.3;
    }
    if (y < 60) {
      y = 60;
      vy = math.max(vy, 0.0);
    }
    final ground = groundAt(x);
    if (y + 30 >= ground) {
      final onPad = x - 26 >= padL && x + 26 <= padR;
      final soft = vy < 2.2 && vx.abs() < 1.4 && tilt.abs() < 0.2;
      if (onPad && soft) {
        landed++;
        if (vy < 1.2) softLandings++;
        score += 100 + (fuel * 100).round();
        lastEvent = 2;
        y = ground - 30;
        landedAt = ticks;
        if (goalN > 0 && landed >= goalN) win();
      } else {
        lastEvent = 3;
        crashT = ticks;
        hit();
        if (!over) _respawn();
      }
    }
  }

  void _respawn() {
    x = padL > 500 ? 150 : 850;
    y = 220;
    vx = vy = 0;
    tilt = 0;
    fuel = math.max(fuel, 0.6);
  }

  @override
  double get progress => goalN == 0 ? 0 : landed / goalN;
  @override
  String get goalText => goalN == 0 ? '$landed' : '$landed/$goalN';
  @override
  Map<String, int> get stats => {'landings': landed, 'soft_landings': softLandings};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: PD denetleyici — önce güvenli irtifada piste doğru git, sonra alçal.
ArcadeInput landerBot(ArcadeSim sim) {
  final s = sim as LanderSim;
  if (s.landedAt >= 0) return ArcadeInput.idle;
  final px = (s.padL + s.padR) / 2;
  final dx = px - s.x;
  // En yüksek tepe (aradaki)
  var peak = s.padY;
  final lo = math.min(s.x, px), hi = math.max(s.x, px);
  for (var xx = lo; xx <= hi; xx += 20) {
    peak = math.min(peak, s.groundAt(xx));
  }
  for (final off in [-60.0, 60.0]) {
    peak = math.min(peak, s.groundAt(s.x + off));
  }
  final overPad = dx.abs() < 30;
  // Hedef yatay hız
  final wantVx = overPad ? 0.0 : clampD(dx * 0.012, -2.6, 2.6);
  // Hedef dikey hız
  final alt = s.groundAt(s.x) - (s.y + 30);
  double wantVy;
  if (!overPad && s.y + 30 > peak - 160) {
    wantVy = -1.2; // tırman
  } else if (overPad || dx.abs() < 120) {
    wantVy = clampD(alt * 0.02, 0.4, 1.4);
  } else {
    wantVy = 0.3;
  }
  final ax = (wantVx - s.vx) * 0.6;
  final tiltWant = alt < 110 ? clampD(ax * 2.5, -0.1, 0.1) : clampD(ax * 2.5, -0.5, 0.5);
  // Motor: dikey hız hedefin üstündeyse ya da eğim gerekiyorsa
  final needUp = s.vy > wantVy;
  final needSide = (wantVx - s.vx).abs() > 0.3 && alt > 80;
  if (needUp || needSide) {
    return holdAt(s.x + tiltWant * 400, s.y + 200);
  }
  // Motor kapalıyken eğimi düzelt: dokunmadan eğim 0'a döner.
  return ArcadeInput.idle;
}

void paintLander(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as LanderSim;
  paintSky(c, const Color(0xFF03071E), const Color(0xFF1B263B));
  final star = Paint()..color = Colors.white54;
  for (var i = 0; i < 60; i++) {
    c.drawCircle(Offset((i * 157.0) % kWorldW, (i * 263.0) % 900), (i % 3) * 0.8 + 1, star);
  }
  c.drawCircle(const Offset(820, 220), 70, Paint()..color = const Color(0xFF4CC9F0).withValues(alpha: 0.5));
  final path = Path()..moveTo(0, kWorldH);
  for (var i = 0; i < LanderSim.kPts; i++) {
    path.lineTo(i * 25.0, s.terrain[i]);
  }
  path
    ..lineTo(kWorldW, kWorldH)
    ..close();
  c.drawPath(path, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFADB5BD), Color(0xFF495057)]).createShader(const Rect.fromLTWH(0, 800, kWorldW, 800)));
  for (var i = 0; i < 12; i++) {
    final cx = (i * 211.0) % kWorldW;
    c.drawOval(Rect.fromCenter(center: Offset(cx, s.groundAt(cx) + 60), width: 60, height: 18), Paint()..color = Colors.black12);
  }
  // pist
  c.drawRect(Rect.fromLTRB(s.padL, s.padY - 6, s.padR, s.padY + 8), Paint()..color = const Color(0xFFFFB703));
  final blinkOn = (s.ticks ~/ 20).isEven;
  for (final px in [s.padL + 6, s.padR - 6]) {
    c.drawCircle(Offset(px, s.padY - 14), 8, Paint()..color = blinkOn ? const Color(0xFF06D6A0) : Colors.white24);
  }
  // gemi
  c.save();
  c.translate(s.x, s.y);
  c.rotate(s.tilt);
  if (s.thrust) {
    final fl = Path()
      ..moveTo(-14, 26)
      ..lineTo(0, 60 + (s.ticks % 5) * 6.0)
      ..lineTo(14, 26)
      ..close();
    c.drawPath(fl, Paint()..color = const Color(0xFFFF9F1C));
  }
  final legs = Paint()
    ..color = const Color(0xFFDEE2E6)
    ..strokeWidth = 5;
  c.drawLine(const Offset(-18, 14), const Offset(-32, 30), legs);
  c.drawLine(const Offset(18, 14), const Offset(32, 30), legs);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  paintBox(c, const Rect.fromLTWH(-26, -10, 52, 28), blink ? Colors.white38 : const Color(0xFFCED4DA), radius: 8, shade: false);
  c.drawArc(const Rect.fromLTWH(-22, -38, 44, 52), math.pi, math.pi, true, Paint()..color = p.piece(0));
  c.drawCircle(const Offset(0, -18), 9, Paint()..color = const Color(0xFF90E0EF));
  c.restore();
  // yakıt çubuğu
  paintBox(c, const Rect.fromLTWH(60, 60, 300, 26), Colors.white12, radius: 13, shade: false);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(60, 60, 300 * s.fuel, 26), const Radius.circular(13)), Paint()..color = s.fuel < 0.25 ? const Color(0xFFE63946) : const Color(0xFF06D6A0));
  paintText(c, '⛽', const Offset(30, 73), 34, Colors.white70);
  if (s.landedAt >= 0) paintText(c, '✓', Offset(s.x, s.y - 90), 80, const Color(0xFF06D6A0));
}

Sfx? landerSound(ArcadeSim sim) => switch ((sim as LanderSim).lastEvent) {
      2 => Sfx.win,
      3 => Sfx.lose,
      _ => null,
    };

KitRules landerRules(String id) => KitRules(
      id,
      optionalMechanics: const ['wind'],
      gameStats: const [
        GameStat('landings', 'İniş', 'Landings', scale: 50),
        GameStat('soft_landings', 'Yumuşak iniş', 'Soft landings', scale: 30),
      ],
      missionTemplates: const [
        MissionTemplate('landings', 'landings', [5, 10, 20]),
        MissionTemplate('soft_landings', 'soft_landings', [3, 6, 12]),
      ],
      make: LanderSim.new,
      botFn: landerBot,
    );
