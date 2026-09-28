import 'package:flutter/services.dart';

/// Pont vers le code Kotlin (MainActivity) : réglages Samsung/Android,
/// sélecteur de fichiers système (SAF) et raccourcis du widget.
class SystemChannel {
  SystemChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAction' && call.arguments is String) {
        onLaunchAction?.call(call.arguments as String);
      }
    });
  }

  static const _channel = MethodChannel('coffre/system');

  /// Appelé quand le widget relance l'app déjà ouverte.
  void Function(String uri)? onLaunchAction;

  /// Action reçue au démarrage (widget), consommée une seule fois.
  Future<String?> takeLaunchAction() => _call<String>('takeLaunchAction');

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _call<bool>('isIgnoringBatteryOptimizations') ?? false;

  /// Boîte de dialogue système « Autoriser en arrière-plan sans restriction ».
  Future<void> requestIgnoreBatteryOptimizations() =>
      _call<void>('requestIgnoreBatteryOptimizations');

  /// Page « Infos sur l'appli » (Batterie > Non restreinte chez Samsung).
  Future<void> openAppSettings() => _call<void>('openAppSettings');

  Future<void> openNotificationSettings() =>
      _call<void>('openNotificationSettings');

  Future<void> openExactAlarmSettings() =>
      _call<void>('openExactAlarmSettings');

  Future<String> appVersion() async => await _call<String>('appVersion') ?? '?';

  /// « Enregistrer sous » système : l'utilisateur choisit le dossier.
  Future<bool> saveDocument({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async =>
      await _call<bool>('saveDocument', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      }) ??
      false;

  Future<Uint8List?> openDocument({List<String> mimeTypes = const ['*/*']}) =>
      _call<Uint8List>('openDocument', {'mimeTypes': mimeTypes});

  Future<bool> openUrl(String url) async =>
      await _call<bool>('openUrl', {'url': url}) ?? false;

  // --- Agenda du téléphone ---

  Future<bool> hasCalendarPermission() async =>
      await _call<bool>('calendarPermission') ?? false;

  Future<bool> requestCalendarPermission() async =>
      await _call<bool>('requestCalendarPermission') ?? false;

  Future<List<PhoneCalendar>> listCalendars() async {
    final raw = await _call<List<Object?>>('listCalendars') ?? const [];
    return raw.whereType<Map>().map(PhoneCalendar.fromMap).toList();
  }

  Future<List<CalendarEvent>> calendarEvents(
    DateTime begin,
    DateTime end,
  ) async {
    final raw =
        await _call<List<Object?>>('calendarEvents', {
          'begin': begin.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
        }) ??
        const [];
    return raw.whereType<Map>().map(CalendarEvent.fromMap).toList();
  }

  Future<int?> insertEvent({
    required int calendarId,
    required String title,
    required String description,
    required DateTime begin,
    required DateTime end,
  }) => _call<int>('insertEvent', {
    'calendarId': calendarId,
    'title': title,
    'description': description,
    'begin': begin.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
  });

  Future<void> openEvent(int id) => _call<void>('openEvent', {'id': id});

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // tests / plateforme non Android
    }
  }
}

class PhoneCalendar {
  const PhoneCalendar({
    required this.id,
    required this.name,
    required this.account,
    required this.writable,
    required this.isGoogle,
    required this.color,
  });

  factory PhoneCalendar.fromMap(Map m) => PhoneCalendar(
    id: (m['id'] as num).toInt(),
    name: '${m['name'] ?? 'Agenda'}',
    account: '${m['account'] ?? ''}',
    writable: m['writable'] == true,
    isGoogle: '${m['accountType']}' == 'com.google',
    color: (m['color'] as num?)?.toInt() ?? 0xFF8FC1B1,
  );

  final int id;
  final String name;
  final String account;
  final bool writable;
  final bool isGoogle;
  final int color;
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.begin,
    required this.end,
    required this.allDay,
    this.location,
    required this.color,
  });

  factory CalendarEvent.fromMap(Map m) {
    final allDay = m['allDay'] == true;
    DateTime at(Object? v) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        (v as num).toInt(),
        isUtc: allDay,
      );
      // Journée entière : stockée en UTC minuit ; on garde la date locale.
      return allDay ? DateTime(t.year, t.month, t.day) : t;
    }

    return CalendarEvent(
      id: (m['id'] as num).toInt(),
      title: '${m['title'] ?? ''}'.trim().isEmpty
          ? '(Sans titre)'
          : '${m['title']}',
      begin: at(m['begin']),
      end: at(m['end']),
      allDay: allDay,
      location: (m['location'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['location'] as String,
      color: (m['color'] as num?)?.toInt() ?? 0xFF8FC1B1,
    );
  }

  final int id;
  final String title;
  final DateTime begin;
  final DateTime end;
  final bool allDay;
  final String? location;
  final int color;
}
