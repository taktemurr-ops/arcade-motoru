import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Bıçak fırlatma: dönen kütüğe dokunarak bıçak at. Saplı bıçağa çarparsan
/// can gider. Elma isabeti bonus. Her kütükte belli sayıda bıçak saplanınca
/// kütük parçalanır ve sıradaki gelir; beşinci kütük "patron" kütüktür.
const double kLogX = 500, kLogY = 560, kLogR = 190, kKnifeStartY = 1350, kKnifeSpeed = 60, kKnifeLen = 150;

class KnifeSim extends ArcadeSim {
  final ALevel level;
  double angle = 0; // derece
  final List<double> stuck = []; // kütük koordinatında açı
  final List<double> apples = [];
  double? flyY; // uçan bıçağın ucu
  int stage = 0, left = 0, thrown = 0, applesHit = 0, logsBroken = 0, lastEvent = 0, t = 0;
  int breakAt = -100;
  late final int stagesGoal = level.target(3, 0) == 0 ? 0 : 3 + level.d ~/ 3;

  KnifeSim(this.level) : super(level.meta) {
    _newLog();
  }

  bool get boss => (stage + 1) % 5 == 0;

  void _newLog() {
    stuck.clear();
    apples.clear();
    left = 4 + level.d ~/ 4 + stage % 3 + (boss ? 2 : 0);
    final pre = math.min(level.d ~/ 4 + stage % 2, 3);
    for (var i = 0; i < pre; i++) {
      stuck.add(rng.nextDouble() * 360);
    }
    if (rng.chance(0.6)) apples.add(rng.nextDouble() * 360);
  }

  /// Kütüğün açısal hızı (derece/tik): saf, zamana göre.
  double speedAt(int tt) {
    final base = 1.6 + level.d * 0.25 + stage * 0.1;
    if (boss || level.has('reverse')) {
      // Dalgalı hız ve yön değişimi
      return base * math.sin(tt / 70) * 1.6;
    }
    return base;
  }

  /// Bıçağın değeceği açı (kütük koordinatı, alt nokta = 90°).
  double hitAngleIn(int ticksAhead) {
    var a = angle;
    for (var k = 1; k <= ticksAhead; k++) {
      a += speedAt(t + k);
    }
    return ((90 - a) % 360 + 360) % 360;
  }

  int get flightTicks => ((kKnifeStartY - (kLogY + kLogR)) / kKnifeSpeed).ceil();

  static double angDiff(double a, double b) {
    final d = ((a - b) % 360 + 360) % 360;
    return math.min(d, 360 - d);
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    t++;
    angle = (angle + speedAt(t)) % 360;
    if (breakAt >= 0 && ticks - breakAt < 40) return;
    if (breakAt >= 0) {
      breakAt = -100;
      _newLog();
    }
    if (flyY == null && (input.tap || input.swipe == 0) && left > 0) {
      flyY = kKnifeStartY;
      thrown++;
      lastEvent = 1;
    }
    final fy = flyY;
    if (fy != null) {
      final ny = fy - kKnifeSpeed;
      if (ny <= kLogY + kLogR) {
        flyY = null;
        final a = ((90 - angle) % 360 + 360) % 360;
        if (stuck.any((s) => angDiff(s, a) < 11)) {
          lastEvent = 3;
          hit();
          return;
        }
        stuck.add(a);
        left--;
        score += 10;
        lastEvent = 2;
        for (final ap in [...apples]) {
          if (angDiff(ap, a) < 14) {
            apples.remove(ap);
            applesHit++;
            score += 30;
            lastEvent = 4;
          }
        }
        if (left == 0) {
          logsBroken++;
          stage++;
          score += 50;
          lastEvent = 5;
          if (stagesGoal > 0 && stage >= stagesGoal) {
            win();
            return;
          }
          breakAt = ticks;
        }
      } else {
        flyY = ny;
      }
    }
  }

  @override
  double get progress => stagesGoal == 0 ? 0 : stage / stagesGoal;
  @override
  String get goalText => stagesGoal == 0 ? '$logsBroken' : '${stage + 1}/$stagesGoal';
  @override
  Map<String, int> get stats => {'knives_thrown': thrown, 'logs_broken': logsBroken, 'apples_hit': applesHit};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput knifeBot(ArcadeSim sim) {
  final s = sim as KnifeSim;
  if (s.flyY != null || s.breakAt >= 0 || s.left == 0) return ArcadeInput.idle;
  // Bıçak bu tik atılırsa saplanacağı açı (atış bu tikte, uçuş sonraki tiklerde).
  final a = s.hitAngleIn(s.flightTicks);
  final clear = s.stuck.every((k) => KnifeSim.angDiff(k, a) > 12.5);
  return clear ? tapAny : ArcadeInput.idle;
}

void paintKnife(Canvas c, ArcadeSim sim, ArcadePalette p, double tt) {
  final s = sim as KnifeSim;
  paintSky(c, const Color(0xFF3D405B), const Color(0xFF22223B));
  final broken = s.breakAt >= 0;
  final age = broken ? (s.ticks - s.breakAt) / 40 : 0.0;
  c.save();
  c.translate(kLogX, kLogY);
  if (!broken) {
    c.rotate(s.angle * math.pi / 180);
    // bıçaklar (kütüğün arkasında başlar)
    for (final k in s.stuck) {
      c.save();
      c.rotate(k * math.pi / 180);
      _knife(c, Offset(kLogR + kKnifeLen * 0.45, 0), math.pi / 2);
      c.restore();
    }
    c.drawCircle(const Offset(10, 14), kLogR, Paint()..color = Colors.black38);
    c.drawCircle(Offset.zero, kLogR, Paint()..color = s.boss ? const Color(0xFF6D597A) : const Color(0xFFA0522D));
    for (var r = kLogR - 30; r > 20; r -= 34) {
      c.drawCircle(Offset.zero, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.black12);
    }
    for (final ap in s.apples) {
      final o = Offset(math.cos(ap * math.pi / 180), math.sin(ap * math.pi / 180)) * (kLogR + 28);
      paintBall(c, o, 30, const Color(0xFFD62828));
      c.drawOval(Rect.fromCenter(center: o + const Offset(6, -30), width: 18, height: 10), Paint()..color = const Color(0xFF2D6A4F));
    }
  } else {
    for (var q = 0; q < 4; q++) {
      final dir = Offset(math.cos(q * math.pi / 2 + 0.6), math.sin(q * math.pi / 2 + 0.6));
      c.drawArc(Rect.fromCircle(center: dir * (age * 600), radius: kLogR), q * math.pi / 2, math.pi / 2, true, Paint()..color = const Color(0xFFA0522D).withValues(alpha: clampD(1 - age, 0, 1)));
    }
  }
  c.restore();
  final fy = s.flyY;
  if (fy != null) _knife(c, Offset(kLogX, fy + kKnifeLen / 2), -math.pi / 2);
  if (!broken && s.left > 0 && fy == null) _knife(c, Offset(kLogX, kKnifeStartY + kKnifeLen / 2), -math.pi / 2);
  for (var i = 0; i < s.left; i++) {
    paintText(c, '▲', Offset(60, 1500 - i * 46.0), 38, i == 0 ? Colors.white : Colors.white38);
  }
  for (var i = 0; i < 5; i++) {
    final done = i < s.stage % 5;
    c.drawCircle(Offset(380.0 + i * 60, 150), 16, Paint()..color = done ? const Color(0xFFFFB703) : (i == 4 ? const Color(0xFF6D597A) : Colors.white24));
  }
}

void _knife(Canvas c, Offset center, double rot) {
  c.save();
  c.translate(center.dx, center.dy);
  c.rotate(rot);
  // x ekseni boyunca: uç +x
  final blade = Path()
    ..moveTo(kKnifeLen / 2, 0)
    ..lineTo(-5, -16)
    ..lineTo(-5, 16)
    ..close();
  c.drawPath(blade, Paint()..color = const Color(0xFFE9ECEF));
  c.drawLine(const Offset(-5, 0), Offset(kKnifeLen / 2 - 10, 0), Paint()
    ..color = Colors.black12
    ..strokeWidth = 3);
  paintBox(c, const Rect.fromLTWH(-kKnifeLen / 2, -12, kKnifeLen / 2 - 5, 24), const Color(0xFF3D2B1F), radius: 8, shade: false);
  c.restore();
}

Sfx? knifeSound(ArcadeSim sim) => switch ((sim as KnifeSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.error,
      4 => Sfx.coin,
      5 => Sfx.combo,
      _ => null,
    };

KitRules knifeRules(String id) => KitRules(
      id,
      optionalMechanics: const ['reverse'],
      gameStats: const [
        GameStat('knives_thrown', 'Atılan bıçak', 'Knives thrown', scale: 500),
        GameStat('logs_broken', 'Kırılan kütük', 'Logs broken', scale: 50),
        GameStat('apples_hit', 'Vurulan elma', 'Apples hit', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('logs_broken', 'logs_broken', [5, 10, 20]),
        MissionTemplate('apples_hit', 'apples_hit', [3, 6, 12]),
      ],
      make: KnifeSim.new,
      botFn: knifeBot,
    );
