import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/arcade_duel.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Uçurtma Savaşı: iki uçurtma, iki yarış ipi. Parmağını basılı tutarak
/// uçurtmanı o noktaya doğru uçur; bırakırsan rüzgârla sürüklenip alçalır.
/// İpler kesişince sürtünme başlar: o sırada uçurtmasını daha hızlı
/// oynatan taraf ipi "sürter" ve karşı ipi keser. Uçurtman yere ya da
/// çatılara değerse sayı rakibe gider. Camlı ip yoktur (gerçekte
/// tehlikelidir); yalnızca oyun içi "yarış ipi" vardır. Bayrak ya da ülke
/// düellosu yok, takımlar renklidir.
const double kUcGround = 1400, kUcTop = 150, kUcLen = 1350;
const double kUcAx0 = 230, kUcAx1 = 770, kUcAy = 1480;
const double kUcPlayerV = 12, kUcCut = 240;
const int kUcPause = 70;

class UcKite {
  double x, y, vx = 0, vy = 0;
  bool free = false; // kesildi, sürükleniyor
  int stun = 0;
  UcKite(this.x, this.y);
  double get speed => math.sqrt(vx * vx + vy * vy);
}

class KiteSim extends ArcadeSim implements DuelSim {
  final ALevel level;
  late UcKite me, foe;
  double saw = 0; // >0: oyuncu üstün, <0: rakip üstün
  bool contact = false;
  double cxp = 0, cyp = 0; // kesişme noktası
  int myCuts = 0, foeCuts = 0, pause = 0, rounds = 0;
  late final int toWin = level.d <= 3 ? 2 : (level.d <= 7 ? 3 : 4);
  late final double foeV = level.lerp(6.2, 10);
  int cuts = 0, downs = 0, bestStreak = 0, streak = 0, contactTicks = 0;
  int lastEvent = 0, flash = 0, flashTicks = 0; // 1 KESTİN, 2 KESİLDİN, 3 YERE DÜŞTÜ, 4 RAKİP DÜŞTÜ
  final List<(double, double, double)> birds = [];
  ArcadeInput? _rival;
  bool duel = false;
  int _osc = 0;

  KiteSim(this.level) : super(level.meta) {
    _round();
  }

  bool get matchMode => meta.goal;

  void _round() {
    me = UcKite(360, 700 + rng.nextDouble() * 120);
    foe = UcKite(640, 700 + rng.nextDouble() * 120);
    saw = 0;
    contact = false;
    contactTicks = 0;
    pause = kUcPause;
    rounds++;
  }

  double wind(int t) {
    final g = level.has('gust') ? 1.6 : 0.7;
    return g * math.sin(t / 140 + meta.seed % 7) + (level.has('gust') ? 1.2 * math.sin(t / 23) * math.max(0, math.sin(t / 300)) : 0);
  }

  void _steer(UcKite k, ArcadeInput i, double vmax, {bool mirror = false}) {
    final w = wind(ticks);
    if (k.free) {
      k.vx = k.vx * 0.98 + w * 0.05;
      k.vy = k.vy * 0.98 + 0.12;
    } else if (k.stun > 0) {
      k.stun--;
      k.vx *= 0.95;
      k.vy = k.vy * 0.95 + 0.25;
    } else if (i.down && i.hasPointer) {
      final tx = mirror ? kWorldW - i.x : i.x;
      final ty = i.y;
      var dx = (tx - k.x) * 0.12, dy = (ty - k.y) * 0.12;
      final l = math.sqrt(dx * dx + dy * dy);
      if (l > vmax) {
        dx = dx / l * vmax;
        dy = dy / l * vmax;
      }
      k.vx += (dx - k.vx) * 0.22 + w * 0.03;
      k.vy += (dy - k.vy) * 0.22;
    } else {
      k.vx = k.vx * 0.96 + w * 0.04;
      k.vy = k.vy * 0.96 + 0.09;
    }
    k.x += k.vx;
    k.y += k.vy;
    if (!k.free) {
      k.x = clampD(k.x, 40, kWorldW - 40);
      if (k.y < kUcTop) {
        k.y = kUcTop;
        k.vy = math.max(0, k.vy);
      }
    }
  }

  void _leash(UcKite k, double ax) {
    if (k.free) return;
    final dx = k.x - ax, dy = k.y - kUcAy;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l > kUcLen) {
      k.x = ax + dx / l * kUcLen;
      k.y = kUcAy + dy / l * kUcLen;
    }
  }

  /// İki ip (çapa-uçurtma doğru parçaları) kesişiyor mu; kesişme noktası.
  (double, double)? cross() {
    if (me.free || foe.free) return null;
    final x1 = kUcAx0, y1 = kUcAy, x2 = me.x, y2 = me.y;
    final x3 = kUcAx1, y3 = kUcAy, x4 = foe.x, y4 = foe.y;
    final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (den.abs() < 1e-6) return null;
    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
    final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / den;
    if (t <= 0.05 || t >= 0.98 || u <= 0.05 || u >= 0.98) return null;
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  ArcadeInput _cpu() {
    if (foe.free) return ArcadeInput.idle;
    _osc++;
    final c = cross();
    // Kaçınma: yüksek zorlukta kaybederken ipi ayırmaya çalışır.
    if (c != null && level.d >= 6 && saw > kUcCut * 0.55) {
      return holdAt(clampD(me.x + 220, 60, 940), clampD(foe.y - 120, 200, 1200));
    }
    if (c != null) {
      final up = (_osc ~/ 14).isEven;
      return holdAt(clampD(me.x - 130, 60, 940), clampD(c.$2 - 260 + (up ? -150 : 150), 200, 1200));
    }
    return holdAt(clampD(me.x - 150, 60, 940), clampD(me.y - 30, 220, 1150));
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    final rv = _rival;
    final foeIn = rv ?? _cpu();
    if (pause > 0) {
      pause--;
      // Bekleme: uçurtmalar çapaya yakın süzülür.
      _steer(me, input.down ? input : const ArcadeInput(down: true, x: 360, y: 760), kUcPlayerV);
      _steer(foe, rv != null && rv.down ? rv : const ArcadeInput(down: true, x: 360, y: 760), kUcPlayerV, mirror: true);
      me.x = math.min(me.x, 470);
      foe.x = math.max(foe.x, 530);
      _leash(me, kUcAx0);
      _leash(foe, kUcAx1);
      if (pause == 0) {
        me.free = false;
        foe.free = false;
      }
      return;
    }
    _steer(me, input, kUcPlayerV);
    _steer(foe, foeIn, rv != null ? kUcPlayerV : foeV, mirror: rv != null);
    _leash(me, kUcAx0);
    _leash(foe, kUcAx1);
    _birds();
    final c = cross();
    contact = c != null;
    if (c != null) {
      cxp = c.$1;
      cyp = c.$2;
      contactTicks++;
      saw += me.speed - foe.speed;
      if (ticks % 18 == 0) lastEvent = 5;
    } else {
      saw *= 0.985;
    }
    if (saw >= kUcCut) {
      _cut(true);
    } else if (saw <= -kUcCut) {
      _cut(false);
    } else if (me.y > kUcGround) {
      _down(true);
    } else if (foe.y > kUcGround) {
      _down(false);
    }
  }

  void _birds() {
    if (!level.has('birds')) return;
    if (ticks % 200 == 0) birds.add((-60.0, 300 + rng.nextDouble() * 600, ticks.toDouble()));
    for (var i = birds.length - 1; i >= 0; i--) {
      final b = birds[i];
      final x = b.$1 + (ticks - b.$3) * 4;
      if (x > kWorldW + 80) {
        birds.removeAt(i);
        continue;
      }
      final y = b.$2 + math.sin(ticks / 9) * 12;
      for (final k in [me, foe]) {
        if (k.stun == 0 && dist(k.x, k.y, x, y) < 60) k.stun = 40;
      }
    }
  }

  void _cut(bool mine) {
    (mine ? foe : me).free = true;
    (mine ? foe : me).vy = -3;
    _award(mine, mine ? 1 : 2);
  }

  void _down(bool meDown) {
    if (meDown) {
      downs++;
    }
    _award(!meDown, meDown ? 3 : 4);
  }

  void _award(bool mine, int f) {
    flash = f;
    flashTicks = 70;
    saw = 0;
    if (mine) {
      myCuts++;
      if (f == 1) cuts++;
      streak++;
      bestStreak = math.max(bestStreak, streak);
      score += f == 1 ? 150 : 80;
      lastEvent = 1;
    } else {
      foeCuts++;
      streak = 0;
      lastEvent = 2;
    }
    if (!matchMode) {
      if (!mine && !meta.zen) {
        shield = 0;
        hit();
      }
      _round();
      return;
    }
    if (myCuts >= toWin) {
      score += 300 + 50 * lives;
      win();
      return;
    }
    if (foeCuts >= toWin) {
      if (meta.zen) {
        myCuts = foeCuts = 0;
      } else {
        shield = 0;
        hit();
        if (over) return;
        myCuts = foeCuts = 0;
      }
    }
    _round();
  }

  @override
  void onLifeLost() {}

  @override
  bool useBooster() {
    if (over) return false;
    saw = math.max(saw, 0) + kUcCut * 0.4;
    shield = 300;
    return true;
  }

  // ---- DuelSim ----
  @override
  set rivalInput(ArcadeInput? input) => _rival = input;

  @override
  void enableDuel() {
    duel = true;
    lives = 1;
  }

  @override
  int get duelWinner => won ? 0 : (dead ? 1 : -1);

  @override
  List<double> netState() => [
        ticks.toDouble(), me.x, me.y, me.vx, me.vy, foe.x, foe.y, foe.vx, foe.vy, //
        me.free ? 1.0 : 0.0, foe.free ? 1.0 : 0.0, me.stun.toDouble(), foe.stun.toDouble(),
        saw, contact ? 1.0 : 0.0, cxp, cyp, myCuts.toDouble(), foeCuts.toDouble(), pause.toDouble(),
        flash.toDouble(), flashTicks.toDouble(), lastEvent.toDouble(), score.toDouble(),
        won ? 1.0 : 0.0, dead ? 1.0 : 0.0,
      ];

  @override
  void applyNetState(List<double> s) {
    if (s.length < 26) return;
    int n(int i) => s[i].round();
    ticks = n(0);
    me
      ..x = s[1]
      ..y = s[2]
      ..vx = s[3]
      ..vy = s[4]
      ..free = s[9] > 0.5
      ..stun = n(11);
    foe
      ..x = s[5]
      ..y = s[6]
      ..vx = s[7]
      ..vy = s[8]
      ..free = s[10] > 0.5
      ..stun = n(12);
    saw = s[13];
    contact = s[14] > 0.5;
    cxp = s[15];
    cyp = s[16];
    myCuts = n(17);
    foeCuts = n(18);
    pause = n(19);
    flash = n(20);
    flashTicks = n(21);
    lastEvent = n(22);
    score = n(23);
    if (s[24] > 0.5 && !won) win();
    if (s[25] > 0.5 && !dead) {
      lives = 1;
      shield = 0;
      hit();
    }
  }

  @override
  List<double> lerpNet(List<double> a, List<double> b, double f) => lerpAt(a, b, f, const [1, 2, 5, 6, 15, 16]);

  @override
  void mirrorView() {
    final m = me;
    me = foe;
    foe = m;
    for (final k in [me, foe]) {
      k.x = kWorldW - k.x;
      k.vx = -k.vx;
    }
    cxp = kWorldW - cxp;
    saw = -saw;
    final c = myCuts;
    myCuts = foeCuts;
    foeCuts = c;
    const swap = {1: 2, 2: 1, 3: 4, 4: 3};
    flash = swap[flash] ?? flash;
    if (lastEvent == 1) {
      lastEvent = 2;
    } else if (lastEvent == 2) {
      lastEvent = 1;
    }
  }

  @override
  double get progress => matchMode ? (myCuts / toWin).clamp(0.0, 1.0) : 0;
  @override
  String get goalText => matchMode ? '$myCuts-$foeCuts' : '$cuts';
  @override
  Map<String, int> get stats => {'kites_cut': cuts, 'best_streak': bestStreak, 'duels_won': won ? 1 : 0};
  @override
  int get stars {
    if (!won) return 0;
    return math.min(lifeStars(this, 3), foeCuts == 0 ? 3 : (foeCuts == 1 ? 2 : 1));
  }
}

/// Bot: rakip uçurtmanın sağına geçip ipleri kesiştirir, sonra kesişmeyi
/// koruyarak uçurtmasını hızla aşağı yukarı oynatır.
ArcadeInput kiteBot(ArcadeSim sim) {
  final s = sim as KiteSim;
  if (s.pause > 0 || s.me.free) return holdAt(360, 760);
  final f = s.foe;
  final c = s.cross();
  // Yere çok yaklaştıysa yüksel.
  if (s.me.y > 1150) return holdAt(clampD(f.x + 150, 60, 940), 700);
  if (c == null) {
    return holdAt(clampD(f.x + 170, 60, 940), clampD(f.y - 60, 200, 1000));
  }
  final up = (s.ticks ~/ 12).isEven;
  return holdAt(clampD(f.x + 140, 60, 940), clampD(c.$2 - 300 + (up ? -170 : 170), 200, 1050));
}

class KiteRules extends KitRules {
  KiteRules(super.gameId)
      : super(
          optionalMechanics: const ['gust', 'birds'],
          gameStats: const [
            GameStat('kites_cut', 'Kesilen uçurtma', 'Kites cut', scale: 300),
            GameStat('best_streak', 'Üst üste kesiş', 'Best cut streak', scale: 20),
            GameStat('duels_won', 'Kazanılan düello', 'Duels won', scale: 60),
          ],
          missionTemplates: const [
            MissionTemplate('kites_cut', 'kites_cut', [50, 150, 300]),
            MissionTemplate('duels_won', 'duels_won', [10, 25, 60], coinReward: 80),
          ],
          make: KiteSim.new,
          botFn: kiteBot,
        );

  /// Bilgisayara karşı ve çevrimiçi düello.
  @override
  int get localPlayers => 2;
}

KiteRules kiteRules(String id) => KiteRules(id);
