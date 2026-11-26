import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kalabalık Koşusu: koşan kalabalığı parmakla sağa sola yönlendir.
/// Her sırada iki kapıdan birini seç (+10, ×2, −5, ÷2 …); kalabalık sayısı
/// ona göre değişir. Yoldaki rakip gruplar şiddetsiz bir itişmeyle
/// sayını azaltır. Sonda rakip kuleyi itip devirmek için ondan kalabalık
/// olmalısın. Düşük zorlukta yalnızca toplama ve ×2 kapıları çıkar
/// (sayı öğretici).
const double kKlRowGap = 900, kKlFirst = 700, kKlRunnerY = 1250;
const double kKlL = 150, kKlR = 850;
const int kKlCap = 9999;

/// Kapı işlemi: 0 topla, 1 çarp, 2 çıkar, 3 böl.
class KlGate {
  final int op, v;
  const KlGate(this.op, this.v);
  int apply(int n) => switch (op) {
        0 => n + v,
        1 => n * v,
        2 => n - v,
        _ => n ~/ v,
      }.clamp(-kKlCap, kKlCap);
  bool get good => op <= 1;
  String get label => switch (op) { 0 => '+$v', 1 => '×$v', 2 => '−$v', _ => '÷$v' };
}

class KlRow {
  final double at;
  final KlGate left, right;
  final int rivalSide; // -1 yok, 0 sol, 1 sağ
  final int rival;
  final int barSide; // -1 yok
  bool passed = false, rivalDone = false, barDone = false;
  int chosen = -1;
  KlRow(this.at, this.left, this.right, this.rivalSide, this.rival, this.barSide);
}

class CrowdSim extends ArcadeSim {
  final ALevel level;
  final List<KlRow> rows = [];
  late final int rowCount = level.goal ? 6 + level.d : 0;
  late final double speed = level.lerp(9, 12);
  double dist = 0, cx = 500;
  int n = 5, best = 5, gatesTaken = 0, rivalsPushed = 0, peak = 5;
  int finalTower = 0;
  int bump = -100, lastEvent = 0, lastDelta = 0, deltaAt = -100;
  bool finale = false;
  int finaleT = 0;
  int _est = 5; // üretim için tahmini en iyi sayı

  CrowdSim(this.level) : super(level.meta) {
    if (level.goal) {
      for (var i = 0; i < rowCount; i++) {
        _addRow();
      }
      finalTower = math.max(3, (_est * (0.5 + 0.035 * level.d)).floor());
    } else {
      for (var i = 0; i < 4; i++) {
        _addRow();
      }
    }
  }

  double get finishAt => kKlFirst + rowCount * kKlRowGap + 200;

  double split(double t) => level.has('moving') ? 500 + 140 * math.sin(t / 50) : 500;

  KlGate _gate(bool good) {
    final e = _est;
    if (good) {
      if (rng.chance(level.d <= 2 ? 0.35 : 0.3) && e < 3000) return KlGate(1, rng.chance(0.75) || level.d <= 3 ? 2 : 3);
      return KlGate(0, math.max(2, (e * (0.3 + rng.nextDouble() * 0.7)).round()));
    }
    final div = level.has('divide') && e >= 8;
    if (div && rng.chance(0.5)) return const KlGate(3, 2);
    return KlGate(2, math.max(2, (e * (0.2 + rng.nextDouble() * 0.4)).round()));
  }

  void _addRow() {
    final at = kKlFirst + rows.length * kKlRowGap;
    final bad = level.d >= 3 || level.has('minus') || level.has('divide');
    final a = _gate(true);
    final b = _gate(!bad || rng.chance(0.3));
    final flip = rng.chance(0.5);
    final l = flip ? b : a, r = flip ? a : b;
    final bestOpt = math.max(l.apply(_est), r.apply(_est));
    var rivalSide = -1, rival = 0, barSide = -1;
    if (level.has('rivals') || level.d >= 2) {
      if (rng.chance(0.6)) {
        rivalSide = rng.nextInt(2);
        rival = math.max(2, (bestOpt * (0.15 + rng.nextDouble() * 0.25)).round());
      }
    }
    if (level.has('barriers') && rng.chance(0.4)) barSide = rivalSide >= 0 ? 1 - rivalSide : rng.nextInt(2);
    rows.add(KlRow(at, l, r, rivalSide, rival, barSide));
    _est = math.min(kKlCap, math.max(1, bestOpt));
  }

  int sideOf(double x) => x < split(ticks.toDouble()) ? 0 : 1;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (finale) {
      finaleT++;
      if (finaleT == 60) {
        if (n > finalTower) {
          score += 300 + n;
          win();
        } else {
          hit();
          if (!over) _restart();
        }
      }
      return;
    }
    var tx = cx;
    if (input.down && input.hasPointer) tx = input.x;
    if (input.dirX != 0) tx = cx + input.dirX * 60;
    final rad = radius;
    cx = moveToward(cx, clampD(tx, kKlL + rad * 0.5, kKlR - rad * 0.5), 22);
    dist += speed;
    if (!level.goal && rows.last.at - dist < 2600) _addRow();
    for (final r in rows) {
      if (r.at - dist > 40) break;
      if (!r.passed && dist >= r.at) {
        r.passed = true;
        final s = sideOf(cx);
        r.chosen = s;
        final g = s == 0 ? r.left : r.right;
        _change(g.apply(n) - n);
        gatesTaken++;
        lastEvent = g.good ? 1 : 2;
      }
      if (!r.barDone && r.barSide >= 0 && dist >= r.at + 200) {
        r.barDone = true;
        if (sideOf(cx) == r.barSide) {
          _change(-((n * 0.3).ceil()));
          lastEvent = 2;
          bump = ticks;
        }
      }
      if (!r.rivalDone && r.rivalSide >= 0 && dist >= r.at + 550) {
        r.rivalDone = true;
        if (sideOf(cx) == r.rivalSide) {
          _change(-r.rival);
          rivalsPushed++;
          lastEvent = 3;
          bump = ticks;
        }
      }
    }
    if (!level.goal) rows.removeWhere((r) => r.at < dist - 1600);
    if (n <= 0) {
      n = 0;
      hit();
      if (!over) n = 10;
      return;
    }
    if (level.goal && dist >= finishAt) {
      finale = true;
      finaleT = 0;
      lastEvent = 4;
    }
  }

  void _change(int d) {
    n = (n + d).clamp(-kKlCap, kKlCap);
    lastDelta = d;
    deltaAt = ticks;
    if (d > 0) score += d;
    peak = math.max(peak, n);
    best = math.max(best, n);
  }

  void _restart() {
    dist = 0;
    n = 5;
    finale = false;
    for (final r in rows) {
      r.passed = false;
      r.rivalDone = false;
      r.barDone = false;
      r.chosen = -1;
    }
  }

  @override
  void onLifeLost() {}

  double get radius => math.min(190.0, 36 + 7 * math.sqrt(math.max(1, n)));

  @override
  bool useBooster() {
    if (over || finale) return false;
    _change(math.max(5, n ~/ 2));
    shield = 300;
    return true;
  }

  @override
  double get progress => !level.goal ? 0 : math.min(1.0, dist / finishAt);
  @override
  String get goalText => level.goal ? '$n · ${(math.min(1.0, dist / finishAt) * 100).round()}%' : '$n';
  @override
  Map<String, int> get stats => {'best_crowd': peak, 'gates_taken': gatesTaken, 'rivals_pushed': rivalsPushed};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: her sırada sonucu büyük olan kapıyı seçer, sonra rakip grup ve
/// engelden kaçar (iki tarafın uzak kenarına gider).
ArcadeInput crowdBot(ArcadeSim sim) {
  final s = sim as CrowdSim;
  if (s.finale) return ArcadeInput.idle;
  var want = 1;
  for (final r in s.rows) {
    if (r.at + 560 < s.dist) continue;
    if (!r.passed && r.at > s.dist - 1) {
      // Önce gelen engelden/rakipten kaçınma gerekiyorsa o, sonra kapı.
      want = r.left.apply(s.n) >= r.right.apply(s.n) ? 0 : 1;
      break;
    }
    final threat = (!r.barDone && r.barSide >= 0) ? r.barSide : ((!r.rivalDone && r.rivalSide >= 0) ? r.rivalSide : -1);
    if (threat >= 0) {
      want = 1 - threat;
      break;
    }
  }
  final x = want == 0 ? 230.0 : 770.0;
  return holdAt(x, 1250);
}

KitRules crowdRules(String id) => KitRules(
      id,
      optionalMechanics: const ['rivals', 'minus', 'divide', 'barriers', 'moving'],
      gameStats: const [
        GameStat('best_crowd', 'En büyük kalabalık', 'Biggest crowd', scale: 2000),
        GameStat('gates_taken', 'Geçilen kapı', 'Gates passed', scale: 1000),
        GameStat('rivals_pushed', 'İtilen rakip grup', 'Rival groups pushed', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('gates_taken', 'gates_taken', [100, 300, 1000]),
        MissionTemplate('best_crowd', 'best_crowd', [100, 500, 2000]),
      ],
      make: CrowdSim.new,
      botFn: crowdBot,
    );
