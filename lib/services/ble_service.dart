import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'tremor_repository.dart';
import '../models/device_info.dart';

class BleService {
  final TremorRepository repository;
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastDevice;
  String? _lastDeviceId;

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _lastSampleSub;
  StreamSubscription? _lastStatusSub;
  StreamSubscription? _lastExtSub;
  StreamSubscription? _lastSevSub;
  StreamSubscription? _lastDiagSub;
  StreamSubscription? _lastRawSub;
  StreamSubscription? _lastRawFifoSub;

  bool _isConnecting = false;
  bool _isReconnecting = false;
  bool _userDisconnected = false;
  DeviceInfo? deviceInfo;

  BleService(this.repository);

  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get lastDeviceId => _lastDeviceId;
  bool get userDisconnected => _userDisconnected;
  bool get isReconnecting => _isReconnecting;
  bool get isConnecting => _isConnecting;

  Future<void> disconnectManual() async {
    print("BLE: Desconexión manual iniciada por el usuario.");
    _userDisconnected = true;
    _isReconnecting = false;
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }
    _cleanupConnection();
  }

  Future<void> startScanAndConnect() async {
    if (_connectedDevice != null || _isConnecting) return;
    _userDisconnected = false;
    
    _isConnecting = true;
    print("BLE: Iniciando escaneo...");
    
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    var subscription = FlutterBluePlus.onScanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.platformName;
        if (name.isEmpty) name = r.advertisementData.localName;
        
        if (name == "ParkinsonWatch") {
          print("BLE: ¡Dispositivo encontrado! ($name)");
          await FlutterBluePlus.stopScan();
          await connectToDevice(r.device);
          break;
        }
      }
    }, onError: (e) => print("BLE Scan Error: $e"));

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      print("BLE: Error al iniciar escaneo: $e");
      _isConnecting = false;
    }
    
    Future.delayed(const Duration(seconds: 16), () {
      subscription.cancel();
      _isConnecting = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_connectedDevice != null && _connectedDevice!.remoteId == device.remoteId) return;

    _userDisconnected = false;
    _isConnecting = true;
    _lastDevice = device;
    _lastDeviceId = device.remoteId.str;

    try {
      print("BLE: Conectando a ${device.platformName} (${device.remoteId.str})...");
      await device.connect(autoConnect: false);
      _connectedDevice = device;
      _isConnecting = false;

      // 1. Pedir MTU 247
      try {
        await device.requestMtu(247);
        print("BLE: MTU 247 solicitado.");
      } catch (e) {
        print("BLE: Error MTU: $e");
      }

      // 2. En Android pedir prioridad de conexión alta
      try {
        await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
        print("BLE: Connection Priority High solicitada.");
      } catch (e) {
        print("BLE: Error Connection Priority: $e");
      }

      // 3. Suscripción a eventos de desconexión
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("BLE: Desconectado de ${device.platformName}.");
          _cleanupConnection();
          if (!_userDisconnected) {
            _startAutoReconnect();
          }
        }
      });

      print("BLE: Descubriendo servicios...");
      List<BluetoothService> services = await device.discoverServices();
      
      BluetoothCharacteristic? cmdChar;
      BluetoothCharacteristic? rawFifoChar;

      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == TremorRepository.serviceUuid) {
          for (var char in service.characteristics) {
            final uuid = char.uuid.toString().toUpperCase();
            if (uuid == TremorRepository.sampleCharUuid) {
              await char.setNotifyValue(true);
              _lastSampleSub = char.onValueReceived.listen((value) => repository.decodeSample(value));
            } else if (uuid == TremorRepository.statusCharUuid) {
              await char.setNotifyValue(true);
              _lastStatusSub = char.onValueReceived.listen((value) => repository.decodeStatus(value));
            } else if (uuid == TremorRepository.extCharUuid) {
              await char.setNotifyValue(true);
              _lastExtSub = char.onValueReceived.listen((value) => repository.decodeExt(value));
            } else if (uuid == TremorRepository.sevCharUuid) {
              try {
                await char.setNotifyValue(true);
                _lastSevSub = char.onValueReceived.listen((value) => repository.decodeSev(value));
              } catch (e) {
                print("BLE: Opcional SEV no disponible: $e");
              }
            } else if (uuid == TremorRepository.diagCharUuid) {
              try {
                await char.setNotifyValue(true);
                _lastDiagSub = char.onValueReceived.listen((value) => repository.decodeDiag(value));
              } catch (e) {
                print("BLE: Opcional DIAG no disponible: $e");
              }
            } else if (uuid == TremorRepository.summaryCharUuid) {
              await char.setNotifyValue(true);
              char.onValueReceived.listen((value) async {
                repository.decodeSummary(value, "actual_user");
                if (value.length >= 2) {
                  int seq = value[0] | (value[1] << 8);
                  await repository.sendSummaryAck(seq);
                }
              });
            } else if (uuid == TremorRepository.rawCharUuid) {
              await char.setNotifyValue(true);
              _lastRawSub = char.onValueReceived.listen((value) => repository.decodeRawImu(value));
            } else if (uuid == TremorRepository.rawFifoCharUuid) {
              rawFifoChar = char;
            } else if (uuid == TremorRepository.cmdCharUuid) {
              cmdChar = char;
              repository.setCmdCharacteristic(char);
            }
          }
        }
      }

      if (cmdChar != null) {
        await cmdChar.setNotifyValue(true);
        cmdChar.onValueReceived.listen((value) {
          final text = utf8.decode(value, allowMalformed: true);
          if (text.startsWith("FW=")) {
            deviceInfo = DeviceInfo.parse(text);
            print("BLE: INFO Recibida: $deviceInfo");
            if (rawFifoChar != null) {
              _subscribeToRawFifo(rawFifoChar);
            }
          }
        });

        Future.delayed(const Duration(seconds: 1), () {
          repository.sendTimeSync();
          repository.sendInfoRequest();
        });
      }
      
      print("BLE: Suscripciones iniciales completadas.");
    } catch (e) {
      print("BLE Connection Error: $e");
      _isConnecting = false;
    }
  }

  Future<void> _startAutoReconnect() async {
    if (_userDisconnected || _isReconnecting || _connectedDevice != null) return;
    _isReconnecting = true;

    final backoffSteps = [1, 2, 4];
    int stepIndex = 0;

    print("BLE: Iniciando reconexión automática para $_lastDeviceId...");

    while (!_userDisconnected && _connectedDevice == null) {
      final delaySec = stepIndex < backoffSteps.length ? backoffSteps[stepIndex] : 5;
      stepIndex++;

      print("BLE: Reintentando conexión en $delaySec s (intento $stepIndex)...");
      await Future.delayed(Duration(seconds: delaySec));

      if (_userDisconnected || _connectedDevice != null) break;

      try {
        final adapter = await FlutterBluePlus.adapterState.first;
        if (adapter != BluetoothAdapterState.on) {
          print("BLE: Adaptador Bluetooth apagado. Esperando...");
          continue;
        }
      } catch (_) {}

      if (_lastDevice != null) {
        try {
          await connectToDevice(_lastDevice!);
          if (_connectedDevice != null) break;
        } catch (e) {
          print("BLE: Reintento directo falló: $e");
        }
      } else if (_lastDeviceId != null && _lastDeviceId!.isNotEmpty) {
        try {
          final device = BluetoothDevice.fromId(_lastDeviceId!);
          await connectToDevice(device);
          if (_connectedDevice != null) break;
        } catch (e) {
          print("BLE: Reintento por ID falló: $e");
        }
      }
    }

    _isReconnecting = false;
  }

  Future<void> _subscribeToRawFifo(BluetoothCharacteristic char) async {
    print("BLE: Suscribiendo a RAWFIFO...");
    await char.setNotifyValue(true);
    _lastRawFifoSub = char.onValueReceived.listen((value) {
      repository.decodeRawFifo(value);
    });
  }

  void _cleanupConnection() {
    _connectionSubscription?.cancel();
    _lastSampleSub?.cancel();
    _lastStatusSub?.cancel();
    _lastExtSub?.cancel();
    _lastSevSub?.cancel();
    _lastDiagSub?.cancel();
    _lastRawSub?.cancel();
    _lastRawFifoSub?.cancel();
    _connectedDevice = null;
    _isConnecting = false;
  }

  void dispose() {
    _cleanupConnection();
  }
}
