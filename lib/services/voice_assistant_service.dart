 import 'dart:async';

import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'firebase_service.dart';

/// Callback invoked with the words recognized by the microphone and whether
/// they are the final transcription for the current utterance.
typedef OnSpeechResult = void Function(String recognizedWords, bool isFinal);

/// Possible navigation or app actions the assistant can execute.
enum AppVoiceAction {
  none,
  openTremor,
  openMedication,
  openHabits,
  openHabitsFood,
  openHabitsActivity,
  openCommunity,
  openProfile,
}

/// Stages of the sequential step-by-step registration flow.
enum StepState {
  categoryIdentified, // Step 1: Category known ('food', 'medication', 'activity'), waiting for item name
  itemNameExtracted,  // Step 2: Category & itemName known, waiting for event time
}

/// Represents stateful multi-turn conversation context for step-by-step registration.
class PendingVoiceContext {
  final String category; // 'medication', 'food', 'activity'
  StepState step;
  String? itemName;
  String? mealType;
  int? durationMinutes;

  PendingVoiceContext({
    required this.category,
    this.step = StepState.categoryIdentified,
    this.itemName,
    this.mealType,
    this.durationMinutes,
  });

  String toPromptContext() {
    return 'Contexto conversacional previo activo: {pasoActual: ${step.name}, categoría: $category, nombreElemento: ${itemName ?? "pendiente"}, tipoComida: ${mealType ?? "pendiente"}, duracionMinutos: ${durationMinutes ?? "pendiente"}}';
  }
}

/// Represents the assistant's processed response and optional action.
class VoiceAssistantResponse {
  final String textResponse;
  final AppVoiceAction action;
  final bool isRegistrationExecuted;

  const VoiceAssistantResponse({
    required this.textResponse,
    this.action = AppVoiceAction.none,
    this.isRegistrationExecuted = false,
  });
}

/// Base service for the AI voice assistant.
class VoiceAssistantService {
  VoiceAssistantService({this.geminiModel = 'gemini-1.5-flash'});

  final String geminiModel;

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final FirebaseService _firebaseService = FirebaseService();

  /// Holds multi-turn conversational context when information is missing or in progress.
  PendingVoiceContext? _pendingContext;

  GenerativeModel? _model;
  String _localeName = '';

  bool get isAvailable => _speech.isAvailable;
  bool get isListening => _speech.isListening;
  String get localeName => _localeName;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String errorMessage)? onError,
  }) async {
    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      onError?.call('error_permission');
      return false;
    }

    final bool ready = await _speech.initialize(
      onStatus: onStatus,
      onError: (error) => onError?.call(error.errorMsg),
    );
    if (!ready) return false;

    final LocaleName? locale = await _speech.systemLocale();
    _localeName = locale?.localeId ?? 'es_ES';

    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    return true;
  }

  Future<bool> listen({
    Duration duration = const Duration(seconds: 25),
    OnSpeechResult? onResult,
  }) async {
    if (!_speech.isAvailable) return false;
    if (_speech.isListening) await _speech.stop();

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'es_ES',
        listenFor: duration,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
      onResult: (result) =>
          onResult?.call(result.recognizedWords, result.finalResult),
    );
    return true;
  }

  Future<void> stopListening() async => _speech.stop();
  Future<void> speak(String text) async => _tts.speak(text);
  Future<void> stopSpeaking() async => _tts.stop();

  Future<String> askGemini(String prompt) async {
    final GenerativeModel model = _model ??=
        FirebaseVertexAI.instance.generativeModel(model: geminiModel);
    final GenerateContentResponse response =
        await model.generateContent([Content.text(prompt)]);
    return response.text ?? '';
  }

  /// Processes user's voice prompt using Gemini AI + stateful multi-turn entity extraction.
  Future<VoiceAssistantResponse> processPrompt(String userPrompt) async {
    final cleanPrompt = userPrompt.trim();
    if (cleanPrompt.isEmpty) {
      const response = VoiceAssistantResponse(
        textResponse: 'No alcancé a escucharte bien. ¿Podrías repetir?',
        action: AppVoiceAction.none,
      );
      await speak(response.textResponse);
      return response;
    }

    // Cancellation check
    final lower = cleanPrompt.toLowerCase();
    if (lower == 'cancelar' || lower == 'no' || lower == 'olvídalo' || lower == 'olvidalo') {
      _pendingContext = null;
      const response = VoiceAssistantResponse(
        textResponse: 'Operación cancelada. No se realizó ningún registro.',
        action: AppVoiceAction.none,
      );
      await speak(response.textResponse);
      return response;
    }

    AppVoiceAction detectedAction = _detectActionFromPrompt(cleanPrompt);
    String rawReply = '';

    try {
      final nowTime = TimeOfDay.now();
      final formattedNow =
          '${nowTime.hour.toString().padLeft(2, '0')}:${nowTime.minute.toString().padLeft(2, '0')}';

      final systemPrompt = '''
Eres Emki, el asistente inteligente de voz y salud de la app Emkiwear Care para personas con enfermedad de Parkinson.
Tu tarea principal es usar tu CAPACIDAD UNIVERSAL DE RECONOCIMIENTO DE ENTIDADES NOMBRADAS (NER GENERATIVO) para extraer del mensaje del usuario cualquier elemento de salud y llenar las casillas correspondientes en la base de datos.

HORA DE REFERENCIA DEL DISPOSITIVO: $formattedNow

ESTADO CONVERSACIONAL PREVIO ACTIVO:
${_pendingContext != null ? _pendingContext!.toPromptContext() : "Sin contexto previo activo."}

INSTRUCCIONES Y REGLAS DE EXTRACCIÓN DE ENTIDADES (NER):

1. EXTRACCIÓN LIMPIA DE ATRIBUTOS (CRÍTICO):
   - `name` (Medicamento): Extrae ÚNICAMENTE el nombre propio o marca del medicamento. NUNCA incluyas palabras como "pastilla", "pastilla de", "medicina", "dosis", "remedio", ni horas ("6 de la mañana", "a las 8").
     Ejemplo: "Pastilla de doble hexa a las 6 am" -> name="Doble hexa", time="06:00"
   - `food` (Alimentación): Extrae ÚNICAMENTE el nombre limpio del alimento sin categorías ("de desayuno", "de almuerzo", "de cena") ni horas.
     Ejemplo: "Cereal de desayuno a las 7" -> food="Cereal", mealType="Desayuno", time="07:00"
   - `activityType` (Ejercicio): Extrae ÚNICAMENTE el nombre del ejercicio sin palabras como "clase de", "sesión de", "hacer", ni horas ("6 de la mañana").
     Ejemplo: "Pilates 6 de la mañana" -> activityType="Pilates", time="06:00"

2. ETIQUETAS TÉCNICAS A GENERAR:
   - MEDICAMENTOS: `[REGISTER_MEDICATION|name=NOMBRE_LIMPIO|time=HH:MM]` y `[ACTION:OPEN_MEDICATION]`
   - ALIMENTACIÓN: `[REGISTER_FOOD|food=NOMBRE_LIMPIO|mealType=Desayuno/Almuerzo/Cena/Merienda|time=HH:MM]` y `[ACTION:OPEN_HABITS_FOOD]`
   - ACTIVIDAD FÍSICA: `[REGISTER_ACTIVITY|activityType=NOMBRE_LIMPIO|duration=MINUTOS|intensity=Leve/Media/Alta|time=HH:MM]` y `[ACTION:OPEN_HABITS_ACTIVITY]`

3. NAVEGACIÓN Y APRECIACIÓN CLÍNICA:
   - Monitoreo de Temblor / Síntomas: `[ACTION:OPEN_TREMOR]`
   - Comunidad / Apoyo: `[ACTION:OPEN_COMMUNITY]`
   - Perfil de Usuario: `[ACTION:OPEN_PROFILE]`

4. RESPUESTA AL USUARIO:
   Responde siempre con 1 oración breve, cálida y empática confirmando la acción, e incluye al final las etiquetas técnicas correspondientes.

Mensaje del usuario: "$cleanPrompt"
''';

      rawReply = await askGemini(systemPrompt);
    } catch (e) {
      final fallbackMsg = await _tryLocalRegistrationFallback(cleanPrompt);
      if (fallbackMsg != null) {
        rawReply = fallbackMsg;
      } else {
        rawReply = _getFallbackResponse(cleanPrompt, detectedAction);
      }
    }

    // Execute Registration Tag if present
    final regResult = await _executeDataRegistration(rawReply);
    if (regResult.executed) {
      _pendingContext = null; // Registration complete! Clear pending state.
      rawReply = regResult.cleanReply;
    } else {
      _updatePendingContextFromQuery(cleanPrompt, rawReply);
    }

    // Parse navigation action tag from AI reply
    if (rawReply.contains('[ACTION:OPEN_MEDICATION]')) {
      detectedAction = AppVoiceAction.openMedication;
    } else if (rawReply.contains('[ACTION:OPEN_TREMOR]')) {
      detectedAction = AppVoiceAction.openTremor;
    } else if (rawReply.contains('[ACTION:OPEN_HABITS_ACTIVITY]')) {
      detectedAction = AppVoiceAction.openHabitsActivity;
    } else if (rawReply.contains('[ACTION:OPEN_HABITS_FOOD]') || rawReply.contains('[ACTION:OPEN_HABITS]')) {
      detectedAction = AppVoiceAction.openHabitsFood;
    } else if (rawReply.contains('[ACTION:OPEN_COMMUNITY]')) {
      detectedAction = AppVoiceAction.openCommunity;
    } else if (rawReply.contains('[ACTION:OPEN_PROFILE]')) {
      detectedAction = AppVoiceAction.openProfile;
    }

    // Completely strip ALL technical tags before UI rendering or TTS speech!
    final cleanReply = rawReply
        .replaceAll(RegExp(r'\[ACTION:[A-Z_]+\]'), '')
        .replaceAll(RegExp(r'\[REGISTER_[A-Z_]+\|[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();

    final finalResponse = VoiceAssistantResponse(
      textResponse: cleanReply.isNotEmpty
          ? cleanReply
          : 'Entendido, procesando tu solicitud.',
      action: detectedAction,
      isRegistrationExecuted: regResult.executed,
    );

    // Speak ONLY the 100% clean conversational text
    await speak(finalResponse.textResponse);

    return finalResponse;
  }

  /// Parses and executes database inserts in Firestore when registration tags are present.
  /// Uses a flexible key-value parameter parser to handle any parameter order or omitted optional slots.
  Future<_RegistrationResult> _executeDataRegistration(String rawReply) async {
    try {
      final now = DateTime.now();

      final tagMatch = RegExp(r'\[(REGISTER_[A-Z_]+)\|([^\]]+)\]').firstMatch(rawReply);
      if (tagMatch != null) {
        final tagType = tagMatch.group(1)!;
        final rawParams = tagMatch.group(2)!;

        // Parse key-value parameters dynamically
        final Map<String, String> params = {};
        for (final pair in rawParams.split('|')) {
          final parts = pair.split('=');
          if (parts.length >= 2) {
            params[parts[0].trim()] = parts.sublist(1).join('=').trim();
          }
        }

        if (tagType == 'REGISTER_MEDICATION') {
          final rawName = params['name'] ?? params['medication'] ?? params['item'] ?? 'Medicamento';
          final name = _cleanEntityName(rawName);
          final timeStr = params['time'] ?? 'NOW';
          final eventDateTime = _resolveEventDateTime(timeStr, now);
          final eventTimeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

          await _firebaseService.addMedicationTask(name, eventDateTime, eventTimeOfDay, false);
          return _RegistrationResult(executed: true, cleanReply: rawReply);
        } else if (tagType == 'REGISTER_FOOD') {
          final rawFood = params['food'] ?? params['name'] ?? params['item'] ?? 'Alimento';
          final food = _cleanEntityName(rawFood);
          final rawMealType = params['mealType'] ?? params['meal'] ?? food;
          final mealType = _normalizeMealType(rawMealType);
          final timeStr = params['time'] ?? 'NOW';
          final eventDateTime = _resolveEventDateTime(timeStr, now);
          final eventTimeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

          await _firebaseService.logFoodHabit(food, mealType, eventDateTime, eventTimeOfDay);
          return _RegistrationResult(executed: true, cleanReply: rawReply);
        } else if (tagType == 'REGISTER_ACTIVITY') {
          final rawActivity = params['activityType'] ?? params['activity'] ?? params['name'] ?? 'Ejercicio';
          final activityType = _cleanEntityName(rawActivity);
          final duration = int.tryParse(params['duration'] ?? '15') ?? 15;
          final intensity = _normalizeIntensity(params['intensity'] ?? 'Media');
          final timeStr = params['time'] ?? 'NOW';
          final eventDateTime = _resolveEventDateTime(timeStr, now);
          final eventTimeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

          await _firebaseService.logActivityHabit(activityType, duration, intensity, eventDateTime, eventTimeOfDay);
          return _RegistrationResult(executed: true, cleanReply: rawReply);
        }
      }
    } catch (_) {}

    return const _RegistrationResult(executed: false, cleanReply: '');
  }

  void _updatePendingContextFromQuery(String query, String assistantReply) {
    final lowerQ = query.toLowerCase();
    final lowerA = assistantReply.toLowerCase();

    // Preserve or update context based on user query and assistant reply
    if (_pendingContext == null) {
      if (lowerQ.contains('comida') || lowerQ.contains('alimento') || lowerQ.contains('desayun') || lowerQ.contains('almorz') || lowerQ.contains('cen') || lowerQ.contains('comí') || lowerQ.contains('comi')) {
        _pendingContext = PendingVoiceContext(category: 'food', step: StepState.categoryIdentified);
      } else if (lowerQ.contains('medicamento') || lowerQ.contains('medicina') || lowerQ.contains('pastilla') || lowerQ.contains('remedio') || lowerQ.contains('tomé') || lowerQ.contains('tome')) {
        _pendingContext = PendingVoiceContext(category: 'medication', step: StepState.categoryIdentified);
      } else if (lowerQ.contains('actividad') || lowerQ.contains('ejercicio') || lowerQ.contains('caminata') || lowerQ.contains('estiramiento') || lowerQ.contains('hice')) {
        _pendingContext = PendingVoiceContext(category: 'activity', step: StepState.categoryIdentified);
      }
    } else {
      // If assistant asks for time or clarification, transition step
      if (lowerA.contains('a qué hora') || lowerA.contains('a que hora') || lowerA.contains('cuándo') || lowerA.contains('cuando')) {
        _pendingContext!.step = StepState.itemNameExtracted;
      }
    }
  }

  /// Local fallback registration if Gemini is offline or direct command is used
  Future<String?> _tryLocalRegistrationFallback(String prompt) async {
    final lower = prompt.toLowerCase();
    final now = DateTime.now();

    // Cancellation check
    if (lower == 'cancelar' || lower == 'no' || lower == 'olvídalo' || lower == 'olvidalo') {
      _pendingContext = null;
      return 'Operación cancelada. No se realizó ningún registro.';
    }

    // Step 1: User indicates category intent without item name
    if (lower.contains('quiero registrar una comida') || lower.contains('registra un alimento') || lower == 'registra una comida' || lower == 'registra comida') {
      _pendingContext = PendingVoiceContext(category: 'food', step: StepState.categoryIdentified);
      return '¡Claro! Vamos a registrar tu comida. ¿Qué comiste?';
    }

    if (lower.contains('quiero registrar un medicamento') || lower.contains('registra un medicamento') || lower == 'registra medicamento') {
      _pendingContext = PendingVoiceContext(category: 'medication', step: StepState.categoryIdentified);
      return 'Por supuesto, vamos a registrar tu medicamento. ¿Qué medicamento tomaste?';
    }

    if (lower.contains('quiero registrar una actividad') || lower.contains('registra actividad física') || lower.contains('registra ejercicio') || lower == 'registra actividad fisica') {
      _pendingContext = PendingVoiceContext(category: 'activity', step: StepState.categoryIdentified);
      return '¡Claro! Vamos a registrar tu actividad física. ¿Qué actividad física realizaste?';
    }

    // Step 2 & 3: Sequential Handling with Pending Context
    if (_pendingContext != null) {
      final category = _pendingContext!.category;

      if (_pendingContext!.step == StepState.categoryIdentified) {
        // User provided the item name in this turn
        final cleanName = _cleanEntityName(prompt);
        _pendingContext!.itemName = cleanName;
        _pendingContext!.step = StepState.itemNameExtracted;

        if (category == 'activity') {
          final dur = _extractDurationMinutes(prompt) ?? 30;
          _pendingContext!.durationMinutes = dur;
          return '¿A qué hora realizaste la $cleanName?';
        } else if (category == 'food') {
          final mealType = _normalizeMealType(prompt);
          _pendingContext!.mealType = mealType;
          return '¿A qué hora comiste $cleanName?';
        } else {
          return '¿A qué hora tomaste la $cleanName?';
        }
      } else if (_pendingContext!.step == StepState.itemNameExtracted) {
        // User provided the event time in this turn
        final extractedTime = _extractExplicitTimeFromPrompt(prompt) ?? 'NOW';
        final itemName = _pendingContext!.itemName ?? 'Elemento';
        final eventDateTime = _resolveEventDateTime(extractedTime, now);
        final timeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);
        final formattedTime = _formatTimeDisplay(timeOfDay);

        if (category == 'medication') {
          await _firebaseService.addMedicationTask(itemName, eventDateTime, timeOfDay, false);
          _pendingContext = null;
          return 'Registré la toma de $itemName a las $formattedTime. [ACTION:OPEN_MEDICATION]';
        } else if (category == 'food') {
          final mealType = _pendingContext!.mealType ?? 'Almuerzo';
          await _firebaseService.logFoodHabit(itemName, mealType, eventDateTime, timeOfDay);
          _pendingContext = null;
          return 'Registré $itemName a las $formattedTime. [ACTION:OPEN_HABITS_FOOD]';
        } else if (category == 'activity') {
          final duration = _pendingContext!.durationMinutes ?? 30;
          await _firebaseService.logActivityHabit(itemName, duration, 'Media', eventDateTime, timeOfDay);
          _pendingContext = null;
          return 'Registré tu $itemName a las $formattedTime. [ACTION:OPEN_HABITS_ACTIVITY]';
        }
      }
    }

    // Direct 1-shot registration attempts
    if (lower.contains('tomé') || lower.contains('tome') || lower.contains('levodopa')) {
      final itemName = _cleanEntityName(prompt);
      final explicitTime = _extractExplicitTimeFromPrompt(prompt);

      if (explicitTime == null) {
        _pendingContext = PendingVoiceContext(category: 'medication', step: StepState.itemNameExtracted, itemName: itemName);
        return '¿A qué hora tomaste la $itemName?';
      }

      final eventDateTime = _resolveEventDateTime(explicitTime, now);
      final timeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);
      final formattedTime = _formatTimeDisplay(timeOfDay);

      await _firebaseService.addMedicationTask(itemName, eventDateTime, timeOfDay, false);
      _pendingContext = null;
      return 'Registré la toma de $itemName a las $formattedTime. [ACTION:OPEN_MEDICATION]';
    }

    if (lower.contains('comí') || lower.contains('comi') || lower.contains('desayuné') || lower.contains('almorcé') || lower.contains('cené') || lower.contains('arroz')) {
      final foodName = _cleanEntityName(prompt);
      final mealType = _normalizeMealType(prompt);
      final explicitTime = _extractExplicitTimeFromPrompt(prompt);

      if (explicitTime == null) {
        _pendingContext = PendingVoiceContext(category: 'food', step: StepState.itemNameExtracted, itemName: foodName, mealType: mealType);
        return '¿A qué hora comiste $foodName?';
      }

      final eventDateTime = _resolveEventDateTime(explicitTime, now);
      final timeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);
      final formattedTime = _formatTimeDisplay(timeOfDay);

      await _firebaseService.logFoodHabit(foodName, mealType, eventDateTime, timeOfDay);
      _pendingContext = null;
      return 'Registré $foodName a las $formattedTime. [ACTION:OPEN_HABITS_FOOD]';
    }

    if (lower.contains('caminata') ||
        lower.contains('ejercicio') ||
        lower.contains('estiramiento') ||
        lower.contains('yoga') ||
        lower.contains('pilates') ||
        lower.contains('gimnasia') ||
        lower.contains('natacion') ||
        lower.contains('natación') ||
        lower.contains('bici') ||
        lower.contains('hice') ||
        lower.contains('practiqué') ||
        lower.contains('practique') ||
        lower.contains('realicé') ||
        lower.contains('realice')) {
      final activity = _cleanEntityName(prompt);
      final duration = _extractDurationMinutes(prompt) ?? 30;
      final explicitTime = _extractExplicitTimeFromPrompt(prompt) ?? 'NOW';

      final eventDateTime = _resolveEventDateTime(explicitTime, now);
      final timeOfDay = TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);
      final formattedTime = _formatTimeDisplay(timeOfDay);

      await _firebaseService.logActivityHabit(activity, duration, 'Media', eventDateTime, timeOfDay);
      _pendingContext = null;
      return 'Registré tu $activity a las $formattedTime. [ACTION:OPEN_HABITS_ACTIVITY]';
    }

    return null;
  }

  DateTime _resolveEventDateTime(String timeStr, DateTime referenceNow) {
    final cleanStr = timeStr.trim().toUpperCase();
    if (cleanStr == 'NOW' ||
        cleanStr.contains('AHORITA') ||
        cleanStr.contains('ACTUAL')) {
      return referenceNow;
    }

    final parsedTime = _parseTimeOfDay(timeStr);
    return DateTime(
      referenceNow.year,
      referenceNow.month,
      referenceNow.day,
      parsedTime.hour,
      parsedTime.minute,
    );
  }

  String _cleanEntityName(String raw) {
    var s = raw.trim();

    // 1. Remove leading conversational noise, verbs, politeness, category words, and articles
    final leadingNoise = RegExp(
      r'^(hola|por favor|buenas|buenos días|buenas tardes|porfa|me gustaría|quisiera|quiero|necesito|puedes|registra que|registra|registrar|me tomé|me tome|ya tomé|ya tome|tomé|tome|tomar|me comí|me comi|ya comí|ya comi|comí|comi|comer|hice|hacer|fui a|fui|realicé|realice|acabo de|mi|mis|el|la|los|las|un|una|unos|unas|medicamento|alimento|comida|ejercicio|actividad|pastilla de|pastillas de|pastilla|pastillas|medicina de|medicina|remedio de|remedio|dosis de|dosis|toma de|toma|clase de|sesión de|sesion de|de)\s+',
      caseSensitive: false,
    );

    while (leadingNoise.hasMatch(s)) {
      s = s.replaceAll(leadingNoise, '').trim();
    }

    // 2. Remove trailing time phrases, hour numbers, or noise
    final trailingTimeNoise = RegExp(
      r'\s+(ahorita|recien|recién|hoy|ayer|hace un momento|hace un rato|a las? \d+.*|\d{1,2}\s*(de la mañana|de la tarde|de la noche|am|pm|a\.m\.|p\.m\.|de la madrugada)?|\d{1,2}\s*hs?|\d{1,2}\s*horas?)$',
      caseSensitive: false,
    );

    while (trailingTimeNoise.hasMatch(s)) {
      s = s.replaceAll(trailingTimeNoise, '').trim();
    }

    s = s.replaceAll(RegExp(r'[.,;:!?]+$'), '').trim();

    // 3. Remove standalone category suffixes (e.g. "Cereal de desayuno" -> "Cereal")
    s = s.replaceAll(RegExp(r'\s+de\s+(desayuno|almuerzo|cena|merienda)$', caseSensitive: false), '').trim();

    if (s.isEmpty) return raw.trim();

    // Capitalize first letter while preserving multi-word phrases (e.g. "Doble hexa", "Seco de pollo")
    return s[0].toUpperCase() + s.substring(1);
  }

  int? _extractDurationMinutes(String prompt) {
    final match = RegExp(r'(\d+)\s*(minuto|minutos|min)').firstMatch(prompt.toLowerCase());
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  String? _extractExplicitTimeFromPrompt(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('acabo de') ||
        lower.contains('ahorita') ||
        lower.contains('recien') ||
        lower.contains('recién') ||
        lower.contains('hace un segundo')) {
      return 'NOW';
    }

    final timeMatch = RegExp(
            r'(\d{1,2})(:(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|de la mañana|de la tarde|de la noche)?',
            caseSensitive: false)
        .firstMatch(lower);
    if (timeMatch != null) {
      final hourStr = timeMatch.group(1)!;
      final minStr = timeMatch.group(3) ?? '00';
      final period = timeMatch.group(4)?.toLowerCase() ?? '';

      int hour = int.parse(hourStr);
      int min = int.parse(minStr);

      if ((period.contains('pm') ||
              period.contains('p.m.') ||
              period.contains('tarde') ||
              period.contains('noche')) &&
          hour < 12) {
        hour += 12;
      }
      if ((period.contains('am') ||
              period.contains('a.m.') ||
              period.contains('mañana')) &&
          hour == 12) {
        hour = 0;
      }

      return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    }

    return null;
  }

  String _formatTimeDisplay(TimeOfDay timeOfDay) {
    final hour = timeOfDay.hourOfPeriod == 0 ? 12 : timeOfDay.hourOfPeriod;
    final min = timeOfDay.minute.toString().padLeft(2, '0');
    final period = timeOfDay.period == DayPeriod.am ? 'a. m.' : 'p. m.';
    return '$hour:$min $period';
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final clean = timeStr.toLowerCase().replaceAll(' ', '');
      final isPm = clean.contains('pm') || clean.contains('p.m.');
      final digits = clean.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = digits.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (!isPm && clean.contains('am') && hour == 12) hour = 0;

      return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
    } catch (_) {
      return TimeOfDay.now();
    }
  }

  String _normalizeMealType(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('desayuno')) return 'Desayuno';
    if (lower.contains('almuerzo') || lower.contains('comida')) return 'Almuerzo';
    if (lower.contains('cena')) return 'Cena';
    if (lower.contains('merienda') || lower.contains('snack')) return 'Merienda';
    return 'Almuerzo';
  }

  String _normalizeIntensity(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('alta') || lower.contains('fuerte')) return 'Alta';
    if (lower.contains('leve') || lower.contains('baja') || lower.contains('suave')) return 'Leve';
    return 'Media';
  }

  AppVoiceAction _detectActionFromPrompt(String prompt) {
    final lower = prompt.toLowerCase();

    bool containsAny(List<String> keywords) =>
        keywords.any((k) => lower.contains(k));

    if (containsAny(['medicamento', 'medicina', 'remedio', 'pastilla', 'dosis', 'fármaco', 'farmaco'])) {
      return AppVoiceAction.openMedication;
    }
    if (containsAny(['temblor', 'gráfica', 'grafica', 'monitoreo', 'sensor', 'medir'])) {
      return AppVoiceAction.openTremor;
    }
    if (containsAny(['ejercicio', 'caminata', 'estiramiento', 'actividad física', 'actividad fisica'])) {
      return AppVoiceAction.openHabitsActivity;
    }
    if (containsAny(['hábito', 'habito', 'comida', 'alimentación', 'alimentacion', 'dieta'])) {
      return AppVoiceAction.openHabitsFood;
    }
    if (containsAny(['comunidad', 'grupo', 'compañero', 'compañeros', 'lección', 'leccion'])) {
      return AppVoiceAction.openCommunity;
    }
    if (containsAny(['perfil', 'médico', 'medico', 'especialista', 'mi cuenta'])) {
      return AppVoiceAction.openProfile;
    }

    return AppVoiceAction.none;
  }

  String _getFallbackResponse(String prompt, AppVoiceAction action) {
    switch (action) {
      case AppVoiceAction.openMedication:
        return 'Con gusto, abriendo la sección de medicamentos.';
      case AppVoiceAction.openTremor:
        return 'Claro, abriendo la gráfica de monitoreo de temblor.';
      case AppVoiceAction.openHabits:
      case AppVoiceAction.openHabitsFood:
        return 'Entendido, te llevo a la sección de hábitos de alimentación.';
      case AppVoiceAction.openHabitsActivity:
        return 'Entendido, te llevo a la sección de actividad física.';
      case AppVoiceAction.openCommunity:
        return 'Por supuesto, abriendo la sección de comunidad.';
      case AppVoiceAction.openProfile:
        return 'Abriendo tu perfil personal.';
      case AppVoiceAction.none:
        return 'Entendido tu mensaje. ¿Deseas consultar o registrar medicamentos, comidas o ejercicios?';
    }
  }

  Future<void> dispose() async {
    await _speech.stop();
    await _tts.stop();
  }
}

class _RegistrationResult {
  final bool executed;
  final String cleanReply;
  const _RegistrationResult({required this.executed, required this.cleanReply});
}
