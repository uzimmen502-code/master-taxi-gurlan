/// Ҳайдовчи рейсидаги бўш ўринлар (real-time `intercity_drivers`).
class DriverSeatLive {
  const DriverSeatLive({
    required this.seatsLeft,
    required this.seatCapacity,
  });

  final int seatsLeft;
  final int seatCapacity;

  String get display => '$seatsLeft/$seatCapacity';
}
