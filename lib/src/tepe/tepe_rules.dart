import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../surus/hill_engine.dart';
import '../surus/hill_rules.dart';

/// Tepe Tırmanışı: yakıtlı cip ile prosedürel tepelerde 2B fizik sürüş.
/// Gaz/fren (sağ/sol yarı), havada eğilme, ters inişte devrilme; yakıt
/// bidonları, rampa, çamur ve kaya parçaları bölüm mekanikleridir.
const hillClimbSpec = HillSpec(
  vehicle: 'jeep',
  goal: HGoal.finish,
  accel: 0.25,
  fuel: true,
  mechanics: ['steep', 'ramps', 'scarce_fuel', 'mud', 'rocks'],
);

HillRules hillClimbRules(String id) => HillRules(hillClimbSpec, id, const [
      GameStat('distance_m', 'Gidilen yol (m)', 'Distance (m)', scale: 5000),
      GameStat('coins', 'Jeton', 'Coins', scale: 300),
      GameStat('flips', 'Takla', 'Flips', scale: 60),
      GameStat('air_time', 'En uzun uçuş (sn)', 'Longest air time (s)', scale: 10),
    ], const [
      MissionTemplate('distance_m', 'distance_m', [1666, 3333, 5000]),
      MissionTemplate('coins', 'coins', [100, 200, 300]),
      MissionTemplate('flips', 'flips', [10, 25, 60]),
    ]);
