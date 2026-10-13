enum TremorClass {
  sinTemblor, // 0
  leve,       // 1
  moderado,   // 2
  grave,      // 3
  voluntario, // 4
}

enum EstadoTemblor {
  analizando,
  sinTemblor,
  voluntario,
  leve,
  moderado,
  grave,
}

extension EstadoTemblorExtension on EstadoTemblor {
  String get nameEs {
    switch (this) {
      case EstadoTemblor.analizando:
        return 'ANALIZANDO';
      case EstadoTemblor.sinTemblor:
        return 'SIN_TEMBLOR';
      case EstadoTemblor.voluntario:
        return 'VOLUNTARIO';
      case EstadoTemblor.leve:
        return 'LEVE';
      case EstadoTemblor.moderado:
        return 'MODERADO';
      case EstadoTemblor.grave:
        return 'GRAVE';
    }
  }

  String get description {
    switch (this) {
      case EstadoTemblor.analizando:
        return 'Analizando…';
      case EstadoTemblor.sinTemblor:
        return 'Sin temblor detectado';
      case EstadoTemblor.voluntario:
        return 'Movimiento voluntario';
      case EstadoTemblor.leve:
        return 'Temblor leve (< 1.5° / < 0.8 cm)';
      case EstadoTemblor.moderado:
        return 'Temblor moderado (1.5° - 4.5° / 0.8 - 2.4 cm)';
      case EstadoTemblor.grave:
        return 'Temblor severo (>= 4.5° / >= 2.4 cm)';
    }
  }
}

extension TremorClassExtension on TremorClass {
  String get nameEs {
    switch (this) {
      case TremorClass.sinTemblor:
        return 'SIN_TEMBLOR';
      case TremorClass.leve:
        return 'LEVE';
      case TremorClass.moderado:
        return 'MODERADO';
      case TremorClass.grave:
        return 'GRAVE';
      case TremorClass.voluntario:
        return 'VOLUNTARIO';
    }
  }

  String get description {
    switch (this) {
      case TremorClass.sinTemblor:
        return 'Sin temblor detectado';
      case TremorClass.leve:
        return 'Temblor leve (< 1.5° / < 0.8 cm)';
      case TremorClass.moderado:
        return 'Temblor moderado (1.5° - 4.5° / 0.8 - 2.4 cm)';
      case TremorClass.grave:
        return 'Temblor severo (>= 4.5° / >= 2.4 cm)';
      case TremorClass.voluntario:
        return 'Movimiento voluntario';
    }
  }

  static TremorClass fromInt(int val) {
    switch (val & 0x07) {
      case 0:
        return TremorClass.sinTemblor;
      case 1:
        return TremorClass.leve;
      case 2:
        return TremorClass.moderado;
      case 3:
        return TremorClass.grave;
      case 4:
        return TremorClass.voluntario;
      default:
        return TremorClass.sinTemblor;
    }
  }
}

class TremorSample {
  final int tMs;
  final double roll;
  final double pitch;
  final double linAcc;
  final double gyroMag;
  final double tremorAmp;

  TremorSample({
    required this.tMs,
    required this.roll,
    required this.pitch,
    required this.linAcc,
    required this.gyroMag,
    required this.tremorAmp,
  });

  @override
  String toString() {
    return 'Sample(t: $tMs, roll: ${roll.toStringAsFixed(2)}, pitch: ${pitch.toStringAsFixed(2)}, amp: ${tremorAmp.toStringAsFixed(2)})';
  }
}

class TremorStatus {
  final int tMs;
  final bool tremorPresent; // bit0: temblor confirmado (la clase se mantuvo ~2s)
  final bool freqStable;    // bit1: frecuencia estable
  final bool detected;      // bit2: temblor detectado en esta ventana
  final bool isAnalyzing;   // bit6: analizando (calculando bias, llenando ventana 5s, estabilizando)
  final TremorClass tremorClass; // bits3-5: clase (0..4)
  final double domFreq;     // dom_freq_ddhz / 10.0
  final double tremorAmp;   // tremor_amp_ddps / 10.0
  final double movement;    // movement_ddps / 10.0
  final int bandFrac;      // band_frac_pct
  final int duty;          // duty_pct
  final int episode;       // episode_s

  TremorStatus({
    required this.tMs,
    required this.tremorPresent,
    required this.freqStable,
    required this.detected,
    required this.isAnalyzing,
    required this.tremorClass,
    required this.domFreq,
    required this.tremorAmp,
    required this.movement,
    required this.bandFrac,
    required this.duty,
    required this.episode,
  });

  EstadoTemblor get estado {
    if (isAnalyzing) return EstadoTemblor.analizando;
    switch (tremorClass) {
      case TremorClass.sinTemblor:
        return EstadoTemblor.sinTemblor;
      case TremorClass.leve:
        return EstadoTemblor.leve;
      case TremorClass.moderado:
        return EstadoTemblor.moderado;
      case TremorClass.grave:
        return EstadoTemblor.grave;
      case TremorClass.voluntario:
        return EstadoTemblor.voluntario;
    }
  }

  @override
  String toString() {
    return 'Status(t: $tMs, estado: ${estado.nameEs}, confirmed: $tremorPresent, detected: $detected, freq: ${domFreq.toStringAsFixed(1)}Hz)';
  }
}

class TremorExt {
  final int tMs;
  final int accelAmpMg;     // accel_amp_mg
  final double ratio;       // accel_gyro_x100 / 100.0
  final double angDeg;      // ang_disp_cdeg / 100.0
  final int flags2;
  final bool isRotational;  // (flags2 & 0x01) != 0
  final TremorClass tremorClass; // category (0..4)

  TremorExt({
    required this.tMs,
    required this.accelAmpMg,
    required this.ratio,
    required this.angDeg,
    required this.flags2,
    required this.isRotational,
    required this.tremorClass,
  });

  @override
  String toString() {
    return 'Ext(t: $tMs, accel: ${accelAmpMg}mg, ratio: $ratio, ang: ${angDeg}deg, class: ${tremorClass.nameEs})';
  }
}

class TremorSev {
  final int tMs;
  final double thetaDeg;  // theta_cdeg / 100.0 (grados)
  final double desplazCm; // desplaz_mm / 10.0 (cm)

  TremorSev({
    required this.tMs,
    required this.thetaDeg,
    required this.desplazCm,
  });

  @override
  String toString() {
    return 'Sev(t: $tMs, theta: ${thetaDeg.toStringAsFixed(2)}°, desplaz: ${desplazCm.toStringAsFixed(1)} cm)';
  }
}

class TremorDiag {
  final int tMs;
  final int ruta;        // 0, 1, 2
  final int votos;
  final int ejesActivos;
  final int flags;
  final bool detectado;   // (flags & 0x01) != 0
  final bool rotacional;  // (flags & 0x02) != 0
  final bool compuerta;   // (flags & 0x04) != 0
  final double lin;       // lin_x1000 / 1000.0
  final int prel3Pct;     // prel3_pct (%)
  final int vol110Pct;    // vol110_pct (%)
  final double sigmaMin;  // sigma_min_x100 / 100.0 (Hz)
  final double rmsPc;     // rms_pc_ddps / 10.0 (°/s)

  TremorDiag({
    required this.tMs,
    required this.ruta,
    required this.votos,
    required this.ejesActivos,
    required this.flags,
    required this.detectado,
    required this.rotacional,
    required this.compuerta,
    required this.lin,
    required this.prel3Pct,
    required this.vol110Pct,
    required this.sigmaMin,
    required this.rmsPc,
  });

  @override
  String toString() {
    return 'Diag(t: $tMs, ruta: $ruta, det: $detectado, rot: $rotacional, comp: $compuerta, lin: $lin, prel3: $prel3Pct%, vol110: $vol110Pct%, sigma: ${sigmaMin}Hz, rms: ${rmsPc}°/s)';
  }
}

class RawAxisData {
  final int tMs;
  final double axG;   // ax_mg / 1000.0
  final double ayG;   // ay_mg / 1000.0
  final double azG;   // az_mg / 1000.0
  final double gxDps; // gx_ddps / 10.0
  final double gyDps; // gy_ddps / 10.0
  final double gzDps; // gz_ddps / 10.0

  RawAxisData({
    required this.tMs,
    required this.axG,
    required this.ayG,
    required this.azG,
    required this.gxDps,
    required this.gyDps,
    required this.gzDps,
  });
}

class RawSample {
  final int ax, ay, az, gx, gy, gz;
  RawSample(this.ax, this.ay, this.az, this.gx, this.gy, this.gz);
}

class RawFifoPacket {
  final int seqPrimera;
  final int t0Us;
  final int nMuestras;
  final List<RawSample> samples;

  RawFifoPacket(this.seqPrimera, this.t0Us, this.nMuestras, this.samples);
}
