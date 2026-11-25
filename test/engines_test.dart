import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_motoru/arena.dart' as arena;
import 'package:arcade_motoru/atis.dart' as atis;
import 'package:arcade_motoru/balik.dart' as balik;
import 'package:arcade_motoru/futbol.dart' as futbol;
import 'package:arcade_motoru/istila.dart' as istila;
import 'package:arcade_motoru/kanat.dart' as kanat;
import 'package:arcade_motoru/kosu.dart' as kosu;
import 'package:arcade_motoru/kovalamaca.dart' as kovalamaca;
import 'package:arcade_motoru/kule.dart' as kule;
import 'package:arcade_motoru/savunma.dart' as savunma;
import 'package:arcade_motoru/surus.dart' as surus;
import 'package:arcade_motoru/tenis.dart' as tenis;
import 'package:arcade_motoru/tugla.dart' as tugla;
import 'package:arcade_motoru/yilan.dart' as yilan;
import 'package:arcade_motoru/yolgecme.dart' as yolgecme;
import 'package:arcade_motoru/ziplama.dart' as ziplama;
import 'package:arcade_motoru/asteroit.dart' as asteroit;
import 'package:arcade_motoru/pong.dart' as pong;
import 'package:arcade_motoru/balon.dart' as balon;
import 'package:arcade_motoru/meyve.dart' as meyve;
import 'package:arcade_motoru/kostebek.dart' as kostebek;
import 'package:arcade_motoru/refleks.dart' as refleks;
import 'package:arcade_motoru/nisan.dart' as nisan;
import 'package:arcade_motoru/galeri.dart' as galeri;
import 'package:arcade_motoru/dinozor.dart' as dinozor;
import 'package:arcade_motoru/kaykay.dart' as kaykay;
import 'package:arcade_motoru/kayak.dart' as kayak;
import 'package:arcade_motoru/ucak.dart' as ucak;
import 'package:arcade_motoru/helezon.dart' as helezon;
import 'package:arcade_motoru/renk.dart' as renk;
import 'package:arcade_motoru/bicak.dart' as bicak;
import 'package:arcade_motoru/ayinis.dart' as ayinis;
import 'package:arcade_motoru/fuze.dart' as fuze;
import 'package:arcade_motoru/topcu.dart' as topcu;
import 'package:arcade_motoru/sapan.dart' as sapan;
import 'package:arcade_motoru/ipkesme.dart' as ipkesme;
import 'package:arcade_motoru/egik.dart' as egik;
import 'package:arcade_motoru/delik.dart' as delik;
import 'package:arcade_motoru/voleybol.dart' as voleybol;
import 'package:arcade_motoru/pinbol.dart' as pinbol;
import 'package:arcade_motoru/isik.dart' as isik;
import 'package:arcade_motoru/bomba.dart' as bomba;
import 'package:arcade_motoru/kazi.dart' as kazi;
import 'package:arcade_motoru/kaya.dart' as kaya;
import 'package:arcade_motoru/alan.dart' as alan;
import 'package:arcade_motoru/yolcu.dart' as yolcu;
import 'package:arcade_motoru/kirkayak.dart' as kirkayak;
import 'package:arcade_motoru/mermi.dart' as mermi;
import 'package:arcade_motoru/platform.dart' as platform;
import 'package:arcade_motoru/tank.dart' as tank;
import 'package:arcade_motoru/yilanio.dart' as yilanio;
import 'package:arcade_motoru/hiper.dart' as hiper;
import 'package:arcade_motoru/denge.dart' as denge;
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';

/// Her motor: bölümler üretilir, bot tarafından doğrulanır (100.000 bölüm).
void main() {
  final all = <(String, ArcadeRules Function())>[
    ('yilan-SnakeRules', () => yilan.SnakeRules('oyun-test-yilan-snakerules')),
    ('tugla-BrickRules', () => tugla.BrickRules('oyun-test-tugla-brickrules')),
    ('istila-InvadersRules', () => istila.InvadersRules('oyun-test-istila-invadersrules')),
    ('kovalamaca-MazeRules', () => kovalamaca.MazeRules('oyun-test-kovalamaca-mazerules')),
    ('kanat-FlappyRules', () => kanat.FlappyRules('oyun-test-kanat-flappyrules')),
    ('ziplama-BounceRules', () => ziplama.BounceRules('oyun-test-ziplama-bouncerules')),
    ('kule-StackRules', () => kule.StackRules('oyun-test-kule-stackrules')),
    ('yolgecme-CrossyRules', () => yolgecme.CrossyRules('oyun-test-yolgecme-crossyrules')),
    ('savunma-TdRules', () => savunma.TdRules('oyun-test-savunma-tdrules')),
    ('balik-FishRules', () => balik.FishRules('oyun-test-balik-fishrules')),
    ('kosu-NinjaRules', () => kosu.NinjaRules('oyun-test-kosu-ninjarules')),
    ('arena-ShooterRules', () => arena.ShooterRules('oyun-test-arena-shooterrules')),
    ('futbol-FootballRules', () => futbol.FootballRules('oyun-test-futbol-footballrules')),
    ('tenis-TennisRules', () => tenis.TennisRules('oyun-test-tenis-tennisrules')),
    ('atis-BasketballRules', () => atis.BasketballRules('oyun-test-atis-basketballrules')),
    ('atis-PenaltyRules', () => atis.PenaltyRules('oyun-test-atis-penaltyrules')),
    ('atis-MiniGolfRules', () => atis.MiniGolfRules('oyun-test-atis-minigolfrules')),
    ('atis-BowlingRules', () => atis.BowlingRules('oyun-test-atis-bowlingrules')),
    ('atis-ArcheryRules', () => atis.ArcheryRules('oyun-test-atis-archeryrules')),
    ('atis-DartsRules', () => atis.DartsRules('oyun-test-atis-dartsrules')),
    ('surus-TrafficRules', () => surus.TrafficRules('oyun-test-surus-trafficrules')),
    ('surus-ParkingRules', () => surus.ParkingRules('oyun-test-surus-parkingrules')),
    ('asteroit-asteroidRules', () => asteroit.asteroidRules('oyun-test-asteroit-asteroidrules')),
    ('pong-pongRules', () => pong.pongRules('oyun-test-pong-pongrules')),
    ('balon-balloonRules', () => balon.balloonRules('oyun-test-balon-balloonrules')),
    ('meyve-fruitRules', () => meyve.fruitRules('oyun-test-meyve-fruitrules')),
    ('kostebek-moleRules', () => kostebek.moleRules('oyun-test-kostebek-molerules')),
    ('refleks-reflexRules', () => refleks.reflexRules('oyun-test-refleks-reflexrules')),
    ('nisan-aimRules', () => nisan.aimRules('oyun-test-nisan-aimrules')),
    ('galeri-galleryRules', () => galeri.galleryRules('oyun-test-galeri-galleryrules')),
    ('dinozor-dinoRules', () => dinozor.dinoRules('oyun-test-dinozor-dinorules')),
    ('kaykay-skateRules', () => kaykay.skateRules('oyun-test-kaykay-skaterules')),
    ('kayak-skiRules', () => kayak.skiRules('oyun-test-kayak-skirules')),
    ('ucak-planeRules', () => ucak.planeRules('oyun-test-ucak-planerules')),
    ('helezon-helixRules', () => helezon.helixRules('oyun-test-helezon-helixrules')),
    ('renk-colorRules', () => renk.colorRules('oyun-test-renk-colorrules')),
    ('bicak-knifeRules', () => bicak.knifeRules('oyun-test-bicak-kniferules')),
    ('ayinis-landerRules', () => ayinis.landerRules('oyun-test-ayinis-landerrules')),
    ('fuze-missileRules', () => fuze.missileRules('oyun-test-fuze-missilerules')),
    ('topcu-artilleryRules', () => topcu.artilleryRules('oyun-test-topcu-artilleryrules')),
    ('sapan-slingRules', () => sapan.slingRules('oyun-test-sapan-slingrules')),
    ('ipkesme-ropeRules', () => ipkesme.ropeRules('oyun-test-ipkesme-roperules')),
    ('egik-tiltRules', () => egik.tiltRules('oyun-test-egik-tiltrules')),
    ('delik-holeRules', () => delik.holeRules('oyun-test-delik-holerules')),
    ('voleybol-volleyRules', () => voleybol.volleyRules('oyun-test-voleybol-volleyrules')),
    ('pinbol-pinballRules', () => pinbol.pinballRules('oyun-test-pinbol-pinballrules')),
    ('isik-tronRules', () => isik.tronRules('oyun-test-isik-tronrules')),
    ('bomba-bomberRules', () => bomba.bomberRules('oyun-test-bomba-bomberrules')),
    ('kazi-digRules', () => kazi.digRules('oyun-test-kazi-digrules')),
    ('kaya-boulderRules', () => kaya.boulderRules('oyun-test-kaya-boulderrules')),
    ('alan-paperRules', () => alan.paperRules('oyun-test-alan-paperrules')),
    ('yolcu-lemRules', () => yolcu.lemRules('oyun-test-yolcu-lemrules')),
    ('kirkayak-centRules', () => kirkayak.centRules('oyun-test-kirkayak-centrules')),
    ('mermi-hellRules', () => mermi.hellRules('oyun-test-mermi-hellrules')),
    ('platform-platformRules', () => platform.platformRules('oyun-test-platform-platformrules')),
    ('platform-runGunRules', () => platform.runGunRules('oyun-test-platform-rungunrules')),
    ('tank-tankRules', () => tank.tankRules('oyun-test-tank-tankrules')),
    ('yilanio-snakeIoRules', () => yilanio.snakeIoRules('oyun-test-yilanio-snakeiorules')),
    ('hiper-hyperRules', () => hiper.hyperRules('oyun-test-hiper-hyperrules')),
    ('denge-balanceRules', () => denge.balanceRules('oyun-test-denge-balancerules')),
  ];
  for (final (name, make) in all) {
    test(name, timeout: const Timeout(Duration(minutes: 15)), () {
      final r = make();
      expect(r.levelCount, 100000);
      final planner = LevelPlanner(gameId: r.gameId, optionalMechanics: r.optionalMechanics);
      for (final lv in [1, 9, 250, 5000, 77777, 100000]) {
        final gl = r.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name bölüm $lv: ${gl.validation}');
      }
    });
  }
}
