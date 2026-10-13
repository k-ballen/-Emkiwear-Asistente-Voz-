class BiquadSection {
  final double b0, b1, b2, a1, a2;
  double z1 = 0.0;
  double z2 = 0.0;

  BiquadSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  double process(double x) {
    final y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    z1 = 0.0;
    z2 = 0.0;
  }
}

class TremorAxisFilter {
  late final BiquadSection _hp;
  late final BiquadSection _bp1;
  late final BiquadSection _bp2;
  late final BiquadSection _bp3;

  TremorAxisFilter() {
    // HP 0.3 Hz
    _hp = BiquadSection(
      b0: 0.9736948117,
      b1: -1.947389623,
      b2: 0.9736948117,
      a1: -1.946697541,
      a2: 0.9480817061,
    );

    // BP 2.5-8 Hz - Sección 1
    _bp1 = BiquadSection(
      b0: 0.02303355220,
      b1: 0.04606710439,
      b2: 0.02303355220,
      a1: -1.234985108,
      a2: 0.4705642812,
    );

    // BP 2.5-8 Hz - Sección 2
    _bp2 = BiquadSection(
      b0: 1.0,
      b1: 0.0,
      b2: -1.0,
      a1: -0.9299606635,
      a2: 0.6219943598,
    );

    // BP 2.5-8 Hz - Sección 3
    _bp3 = BiquadSection(
      b0: 1.0,
      b1: -2.0,
      b2: 1.0,
      a1: -1.731027913,
      a2: 0.8306046148,
    );
  }

  double process(double x) {
    double y = _hp.process(x);
    y = _bp1.process(y);
    y = _bp2.process(y);
    y = _bp3.process(y);
    return y;
  }

  void reset() {
    _hp.reset();
    _bp1.reset();
    _bp2.reset();
    _bp3.reset();
  }
}

class Tremor3AxisFilter {
  final TremorAxisFilter xFilter = TremorAxisFilter();
  final TremorAxisFilter yFilter = TremorAxisFilter();
  final TremorAxisFilter zFilter = TremorAxisFilter();

  ({double x, double y, double z}) process({
    required double x,
    required double y,
    required double z,
  }) {
    return (
      x: xFilter.process(x),
      y: yFilter.process(y),
      z: zFilter.process(z),
    );
  }

  void reset() {
    xFilter.reset();
    yFilter.reset();
    zFilter.reset();
  }
}
