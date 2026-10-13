import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primer_app/models/ble_device_data.dart';
import 'package:mi_primer_app/services/tremor_repository.dart';
import 'package:mi_primer_app/services/tremor_filter.dart';

void main() {
  group('Protocolo BLE Firmware ParkinsonWatch', () {
    late TremorRepository repository;

    setUp(() {
      repository = TremorRepository();
    });

    test('Decode STATUS v2.0.0 - 14 bytes', () {
      final List<int> statusBytes = [
        0xE8, 0x03, 0x00, 0x00, // t_ms = 1000
        0x15,                   // flags: bit0=1 (confirmado), bit1=0, bit2=1 (detectado), bits3-5=2 (MODERADO)
        0x32,                   // dom_freq_ddhz = 50 -> 5.0 Hz
        0xC0, 0x00,             // tremor_amp_ddps = 192 -> 19.2 °/s
        0x1F, 0x00,             // movement_ddps = 31 -> 3.1 °/s
        0x50,                   // band_frac_pct = 80
        0x2D,                   // duty_pct = 45
        0x0C, 0x00,             // episode_s = 12
      ];

      final status = repository.decodeStatus(statusBytes);

      expect(status, isNotNull);
      expect(status!.tMs, equals(1000));
      expect(status.tremorPresent, isTrue);
      expect(status.freqStable, isFalse);
      expect(status.detected, isTrue);
      expect(status.isAnalyzing, isFalse);
      expect(status.estado, equals(EstadoTemblor.moderado));
      expect(status.tremorClass, equals(TremorClass.moderado));
      expect(status.domFreq, closeTo(5.0, 0.01));
      expect(status.tremorAmp, closeTo(19.2, 0.01));
      expect(status.movement, closeTo(3.1, 0.01));
      expect(status.bandFrac, equals(80));
      expect(status.duty, equals(45));
      expect(status.episode, equals(12));
    });

    test('Decode STATUS con bit6 = 1 (ANALIZANDO)', () {
      final List<int> statusBytes = [
        0xE8, 0x03, 0x00, 0x00, // t_ms = 1000
        0x55,                   // flags: bit6=1 (0x40), bit4=1 (clase 2)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
      ];

      final status = repository.decodeStatus(statusBytes);

      expect(status, isNotNull);
      expect(status!.isAnalyzing, isTrue);
      expect(status.estado, equals(EstadoTemblor.analizando));
    });

    test('Decode EXT v2.0.0 - 12 bytes', () {
      final List<int> extBytes = [
        0xE8, 0x03, 0x00, 0x00, // t_ms = 1000
        0x78, 0x00,             // accel_amp_mg = 120
        0x71, 0x02,             // accel_gyro_x100 = 625 -> ratio 6.25
        0xC8, 0x00,             // ang_disp_cdeg = 200 -> 2.00 deg
        0x01,                   // flags2: bit0=1 (rotacional)
        0x02,                   // category: 2 (MODERADO)
      ];

      final ext = repository.decodeExt(extBytes);

      expect(ext, isNotNull);
      expect(ext!.tMs, equals(1000));
      expect(ext.accelAmpMg, equals(120));
      expect(ext.ratio, closeTo(6.25, 0.01));
      expect(ext.angDeg, closeTo(2.00, 0.01));
      expect(ext.isRotational, isTrue);
      expect(ext.tremorClass, equals(TremorClass.moderado));
    });

    test('Decode SEV v2.2.0 - 8 bytes', () {
      final List<int> sevBytes = [
        0xE8, 0x03, 0x00, 0x00, // t_ms = 1000
        0x4E, 0x02,             // theta_cdeg = 590 -> 5.90°
        0x21, 0x00,             // desplaz_mm = 33 -> 3.3 cm
      ];

      final sev = repository.decodeSev(sevBytes);

      expect(sev, isNotNull);
      expect(sev!.tMs, equals(1000));
      expect(sev.thetaDeg, closeTo(5.90, 0.01));
      expect(sev.desplazCm, closeTo(3.3, 0.1));
    });

    test('Decode DIAG v2.1.0 - 16 bytes', () {
      final List<int> diagBytes = [
        0xE8, 0x03, 0x00, 0x00, // t_ms = 1000
        0x02,                   // ruta = 2
        0x00,                   // votos = 0
        0x03,                   // ejes_activos = 3
        0x07,                   // flags: bit0=1 (detectado), bit1=1 (rotacional), bit2=1 (compuerta)
        0xE5, 0x03,             // lin_x1000 = 997 -> 0.997
        0x58,                   // prel3_pct = 88%
        0x08,                   // vol110_pct = 8%
        0x6E, 0x00,             // sigma_min_x100 = 110 -> 1.10 Hz
        0x33, 0x04,             // rms_pc_ddps = 1075 -> 107.5 °/s
      ];

      final diag = repository.decodeDiag(diagBytes);

      expect(diag, isNotNull);
      expect(diag!.tMs, equals(1000));
      expect(diag.ruta, equals(2));
      expect(diag.votos, equals(0));
      expect(diag.ejesActivos, equals(3));
      expect(diag.detectado, isTrue);
      expect(diag.rotacional, isTrue);
      expect(diag.compuerta, isTrue);
      expect(diag.lin, closeTo(0.997, 0.001));
      expect(diag.prel3Pct, equals(88));
      expect(diag.vol110Pct, equals(8));
      expect(diag.sigmaMin, closeTo(1.10, 0.01));
      expect(diag.rmsPc, closeTo(107.5, 0.1));
    });

    test('Filtro IIR Biquad (HP 0.3Hz + BP 2.5-8Hz) - Prueba con Seno 5 Hz y 1 Hz', () {
      final filter5Hz = TremorAxisFilter();
      const double fs = 50.0;
      const int numSamples = 500;
      final List<double> filtered5Hz = [];

      for (int i = 0; i < numSamples; i++) {
        final double t = i / fs;
        final double x = 28.28 * sin(2 * pi * 5.0 * t);
        filtered5Hz.add(filter5Hz.process(x));
      }

      final last5s5Hz = filtered5Hz.sublist(250);
      final double sumSq5Hz = last5s5Hz.fold(0.0, (acc, v) => acc + v * v);
      final double rms5Hz = sqrt(sumSq5Hz / last5s5Hz.length);

      expect(rms5Hz, closeTo(20.0, 0.5));

      final filter1Hz = TremorAxisFilter();
      final List<double> filtered1Hz = [];

      for (int i = 0; i < numSamples; i++) {
        final double t = i / fs;
        final double x = 28.28 * sin(2 * pi * 1.0 * t);
        filtered1Hz.add(filter1Hz.process(x));
      }

      final last5s1Hz = filtered1Hz.sublist(250);
      final double sumSq1Hz = last5s1Hz.fold(0.0, (acc, v) => acc + v * v);
      final double rms1Hz = sqrt(sumSq1Hz / last5s1Hz.length);

      expect(rms1Hz, closeTo(0.52, 0.1));
    });
  });
}
