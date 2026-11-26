import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kriket Vuruşu: vurucunun arkasından bakılan sahada atıcı topu atar; top
/// kale çizgisine geldiği anda dokunarak vurulur. Dokunulan yer vuruşu
/// seçer: ekranın sol/orta/sağ bölümü yönü, üst yarı havadan (altılık şansı,
/// ama derindeki saha oyuncusu tutabilir), alt yarı yerden (dörtlük).
/// Zamanlama kusursuzsa top sınırı geçer; geç ya da erken kalırsa kenar
/// vuruşu olur ya da ıska geçilir. Kaleye giden topu ıskalamak "kale yıkıldı"
/// demektir ve bir can (wicket) gider. Hedef: verilen top sayısında hedef
/// koşuya ulaşmak. Takımlar, ligler ve oyuncular tamamen uydurmadır.
const int kCrGap = 70; // iki top arası (atıcı koşusu)
const double kCrReady = 0.6; // sopanın hazır olduğu ilerleme

/// Atış türü: 0 normal, 1 yorker (dibe), 2 bouncer (kısa, yüksek), 3 spin, 4 swing.
class CrBall {
  final int kind;
  final int t; // atıştan kale çizgisine tik sayısı
  final double ub; // sekme noktası (0..1)
  final double x0, xb, xf; // yanal konum: çıkış, sekme, çizgi
  final double hEnd; // çizgideki yükseklik
  final double swing;
  const CrBall(this.kind, this.t, this.ub, this.x0, this.xb, this.xf, this.hEnd, this.swing);

  bool get onStumps => xf.abs() < 0.22;

  /// u ilerlemesindeki yanal konum ve yükseklik.
  (double, double) at(double u) {
    if (u <= ub) {
      final k = u / ub;
      final x = x0 + (xb - x0) * k + swing * math.sin(k * math.pi) * 0.25;
      final h = 230 * (1 - k) + 60 * math.sin(k * math.pi);
      return (x, math.max(0.0, h));
    }
    final k = ((u - ub) / (1 - ub)).clamp(0.0, 1.4);
    final x = xb + (xf - xb) * k;
    final h = hEnd * math.sin(math.min(k, 1.0) * math.pi / 2);
    return (x, h);
  }
}

class CricketSim extends ArcadeSim {
  final ALevel level;
  late final int balls = level.goal ? 6 * (2 + level.d ~/ 4) : 0;
  late final int target = level.goal ? (balls * (1.4 + 0.16 * level.d)).round() : 0;
  int bowled = 0, runs = 0, fours = 0, sixes = 0, outs = 0, extra = 0, perfects = 0;
  int wait = 50; // sonraki atışa kalan tik
  int bt = -1; // atıştan bu yana tik (-1: top yok)
  CrBall? ball;
  bool swung = false;
  // vuruş sonucu ve canlandırma
  int shotDir = 1; // 0 sol, 1 orta, 2 sağ
  bool shotAir = false;
  int shotQ = 0; // 0 ıska, 1 kenar, 2 iyi, 3 kusursuz
  int shotAt = -100, result = -1; // result: koşu, -2 kale, -3 tutuldu, -4 boş geçti
  int resultAt = -100, swingAt = -100, lastEvent = 0;
  final List<bool> deep = [false, false, false], ring = [false, false, false];

  CricketSim(this.level) : super(level.meta) {
    _field();
  }

  int get ballsLeft => balls + extra - bowled;

  void _field() {
    final dn = level.has('field') ? 2 : 1;
    for (var s = 0; s < 3; s++) {
      deep[s] = false;
      ring[s] = false;
    }
    // Derin saha: en az bir boşluk bırakılır.
    final open = rng.nextInt(3);
    for (var i = 0; i < dn; i++) {
      final s = (open + 1 + i) % 3;
      deep[s] = true;
    }
    for (var s = 0; s < 3; s++) {
      ring[s] = rng.chance(0.25 + level.k * 0.35);
    }
  }

  CrBall _make() {
    final kinds = <int>[0];
    if (level.has('yorker') || level.d >= 6) kinds.add(1);
    if (level.has('bouncer') || level.d >= 4) kinds.add(2);
    if (level.has('spin')) kinds.add(3);
    if (level.has('swing') || level.d >= 8) kinds.add(4);
    final kind = kinds[rng.nextInt(kinds.length)];
    final base = level.lerp(64, 40);
    final x0 = (rng.nextDouble() * 2 - 1) * 0.35;
    var xf = (rng.nextDouble() * 2 - 1) * 0.55;
    switch (kind) {
      case 1:
        return CrBall(1, (base * 0.95).round(), 0.97, x0, xf, xf, 8, 0);
      case 2:
        return CrBall(2, (base * 1.05).round(), 0.45, x0, x0 * 0.5, xf, 240, 0);
      case 3:
        final xb = (rng.nextDouble() * 2 - 1) * 0.3;
        xf = xb + (rng.chance(0.5) ? 1 : -1) * (0.25 + rng.nextDouble() * 0.3);
        return CrBall(3, (base * 1.35).round(), 0.72, x0, xb, xf, 70, 0);
      case 4:
        return CrBall(4, base.round(), 0.75, x0, xf * 0.6, xf, 80, rng.chance(0.5) ? 1.2 : -1.2);
      default:
        return CrBall(0, base.round(), 0.7, x0, (x0 + xf) / 2, xf, 85, 0);
    }
  }

  double get u => ball == null || bt < 0 ? 0 : bt / ball!.t;

  /// Zamanlama pencereleri (yorker daha dar).
  (int, int, int) get windows => ball?.kind == 1 ? (2, 4, 7) : (3, 6, 10);

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (ball == null) {
      if (wait > 0) {
        wait--;
        return;
      }
      if (level.goal && ballsLeft <= 0) {
        // Hedefe ulaşılamadı: bir can gider, ek over başlar.
        extra += 6;
        hit();
        resultAt = ticks;
        result = -5;
        lastEvent = 4;
        wait = 60;
        return;
      }
      ball = _make();
      bt = 0;
      swung = false;
      shotQ = 0;
      return;
    }
    final b = ball!;
    bt++;
    if (!swung && input.tap && u >= kCrReady) {
      swung = true;
      swingAt = ticks;
      _shot(input, bt - b.t);
    }
    if (swung && shotQ > 0) {
      if (ticks - shotAt > 45) _endBall();
      return;
    }
    if (bt >= b.t + 4) {
      // Top vurucuyu geçti.
      if (b.onStumps) {
        result = -2;
        outs++;
        lastEvent = 3;
        hit();
      } else {
        result = -4;
        lastEvent = 5;
      }
      resultAt = ticks;
      _endBall();
    }
  }

  void _shot(ArcadeInput i, int e) {
    final (wp, wg, we) = windows;
    final ae = e.abs();
    shotQ = ae <= wp ? 3 : (ae <= wg ? 2 : (ae <= we ? 1 : 0));
    if (shotQ == 0) return; // ıska: top yoluna devam eder
    shotDir = i.x < 333 ? 0 : (i.x < 667 ? 1 : 2);
    shotAir = i.y >= 0 && i.y < 1000;
    shotAt = ticks;
    final s = shotDir;
    int r;
    if (shotAir) {
      r = switch (shotQ) {
        3 => 6,
        2 => deep[s] ? -3 : 4,
        _ => ring[s] ? -3 : 1,
      };
    } else {
      r = switch (shotQ) {
        3 => 4,
        2 => ring[s] ? 1 : (deep[s] ? 2 : 4),
        _ => ring[s] ? 0 : 1,
      };
    }
    result = r;
    resultAt = ticks;
    if (shotQ == 3) perfects++;
    if (r == -3) {
      outs++;
      lastEvent = 3;
      hit();
      return;
    }
    runs += r;
    if (r == 6) sixes++;
    if (r == 4) fours++;
    score += r * 10 + (shotQ == 3 ? 5 : 0);
    lastEvent = r >= 4 ? 2 : 1;
  }

  void _endBall() {
    ball = null;
    bt = -1;
    bowled++;
    wait = kCrGap;
    if (bowled % 6 == 0) _field();
    if (level.goal && runs >= target) {
      score += 50 * lives + 20 * ballsLeft;
      win();
    }
  }

  @override
  bool useBooster() {
    if (over) return false;
    // Rehber: bu ve sonraki topların ideal anı gösterilir + koruma.
    shield = 600;
    return true;
  }

  @override
  double get progress => target == 0 ? 0 : math.min(1.0, runs / target);
  @override
  String get goalText => target == 0 ? '$runs' : '$runs/$target';
  @override
  Map<String, int> get stats => {'runs': runs, 'sixes': sixes, 'fours': fours, 'perfect_shots': perfects};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: topun çizgiye geleceği tikte, derin saha oyuncusu olmayan yöne
/// havadan vurur.
ArcadeInput cricketBot(ArcadeSim sim) {
  final s = sim as CricketSim;
  final b = s.ball;
  if (b == null || s.swung) return ArcadeInput.idle;
  if (s.bt + 1 == b.t) {
    final open = [for (var i = 0; i < 3; i++) if (!s.deep[i]) i];
    final d = open.isEmpty ? 1 : open.first;
    return tapAt(170.0 + d * 330, 600);
  }
  return ArcadeInput.idle;
}

KitRules cricketRules(String id) => KitRules(
      id,
      optionalMechanics: const ['swing', 'spin', 'bouncer', 'yorker', 'field'],
      gameStats: const [
        GameStat('runs', 'Koşu', 'Runs', scale: 2000),
        GameStat('sixes', 'Altılık', 'Sixes', scale: 200),
        GameStat('fours', 'Dörtlük', 'Fours', scale: 300),
        GameStat('perfect_shots', 'Kusursuz vuruş', 'Perfect shots', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('runs', 'runs', [200, 600, 2000]),
        MissionTemplate('sixes', 'sixes', [20, 60, 200]),
        MissionTemplate('perfect_shots', 'perfect_shots', [30, 100, 300]),
      ],
      make: CricketSim.new,
      botFn: cricketBot,
    );
