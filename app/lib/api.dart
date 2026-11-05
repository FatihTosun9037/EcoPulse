import 'package:dio/dio.dart';

import 'session.dart';

class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.role,
    required this.displayName,
  });

  final String accessToken;
  final String role;
  final String displayName;
}

class Machine {
  const Machine({
    required this.id,
    required this.name,
    required this.location,
    required this.meta,
    required this.faultActive,
    required this.voltageText,
    required this.currentText,
    required this.temperatureText,
    required this.powerText,
    required this.voltageSeries,
    required this.currentSeries,
    required this.temperatureSeries,
    this.flowText = '—',
    this.flowSeries = const [],
    this.nominalFlowText = '—',
    this.domain = '',
    this.domainLabel = '',
    this.personnelId,
    this.assigneeName = '',
    this.expertiseMismatch = false,
  });

  final int id;
  final String name;
  final String location;
  final String meta;
  final bool faultActive;
  final String voltageText;
  final String currentText;
  final String temperatureText;
  final String powerText;
  final List<double> voltageSeries;
  final List<double> currentSeries;
  final List<double> temperatureSeries;
  final String flowText;
  final List<double> flowSeries;
  final String nominalFlowText;
  final String domain;
  final String domainLabel;
  final int? personnelId;
  final String assigneeName;
  final bool expertiseMismatch;

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      id: json['id'] as int,
      name: json['name'] as String,
      location: json['location'] as String,
      meta: json['meta'] as String,
      faultActive: json['faultActive'] as bool? ?? false,
      voltageText: json['voltageText'] as String? ?? '—',
      currentText: json['currentText'] as String? ?? '—',
      temperatureText: json['temperatureText'] as String? ?? '—',
      powerText: json['powerText'] as String? ?? '—',
      voltageSeries: _doubles(json['voltageSeries']),
      currentSeries: _doubles(json['currentSeries']),
      temperatureSeries: _doubles(json['temperatureSeries']),
      flowText: json['flowText'] as String? ?? '—',
      flowSeries: _doubles(json['flowSeries']),
      nominalFlowText: json['nominalFlowText'] as String? ?? '—',
      domain: json['domain'] as String? ?? '',
      domainLabel: json['domainLabel'] as String? ?? '',
      personnelId: json['personnelId'] as int?,
      assigneeName: json['assigneeName'] as String? ?? '',
      expertiseMismatch: json['expertiseMismatch'] as bool? ?? false,
    );
  }
}

class Personnel {
  const Personnel({
    required this.id,
    required this.fullName,
    required this.expertise,
    required this.expertiseLabel,
  });

  final int id;
  final String fullName;
  final String expertise;
  final String expertiseLabel;

  factory Personnel.fromJson(Map<String, dynamic> json) {
    return Personnel(
      id: json['id'] as int,
      fullName: json['fullName'] as String,
      expertise: json['expertise'] as String,
      expertiseLabel: json['expertiseLabel'] as String,
    );
  }
}

class AssignmentResult {
  const AssignmentResult({
    required this.saved,
    required this.expertiseMismatch,
    required this.message,
  });

  final bool saved;
  final bool expertiseMismatch;
  final String message;

  factory AssignmentResult.fromJson(Map<String, dynamic> json) {
    return AssignmentResult(
      saved: json['saved'] as bool? ?? false,
      expertiseMismatch: json['expertiseMismatch'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class Notice {
  const Notice({
    required this.id,
    required this.alarmId,
    required this.title,
    required this.body,
  });

  final int id;
  final int alarmId;
  final String title;
  final String body;

  factory Notice.fromJson(Map<String, dynamic> json) {
    return Notice(
      id: json['id'] as int,
      alarmId: json['alarmId'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }
}

class Alarm {
  const Alarm({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.typeLabel,
    required this.severityLabel,
    required this.status,
    required this.lossText,
    required this.metaText,
  });

  final int id;
  final int machineId;
  final String machineName;
  final String typeLabel;
  final String severityLabel;
  final String status;
  final String lossText;
  final String metaText;

  bool get canMaintain => status == 'ACTIVE';

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as int,
      machineId: json['machineId'] as int,
      machineName: json['machineName'] as String,
      typeLabel: json['typeLabel'] as String,
      severityLabel: json['severityLabel'] as String,
      status: json['status'] as String,
      lossText: json['lossText'] as String,
      metaText: json['metaText'] as String,
    );
  }
}

class Dashboard {
  const Dashboard({
    required this.machineCount,
    required this.activeAlarms,
    required this.openWorkOrders,
    required this.verifyingWorkOrders,
    required this.totalPowerText,
    required this.activeLossText,
    required this.verifiedSavingsText,
    required this.verifiedCo2Text,
    required this.machines,
    required this.alarms,
    this.verifiedAnnualText = '—',
    this.totalFlowText = '—',
    this.totalFlowSeries = const [],
    this.nominalFlowText = '—',
    this.water,
  });

  final int machineCount;
  final int activeAlarms;
  final int openWorkOrders;
  final int verifyingWorkOrders;
  final String totalPowerText;
  final String activeLossText;
  final String verifiedSavingsText;
  final String verifiedCo2Text;
  final List<Machine> machines;
  final List<Alarm> alarms;
  final String verifiedAnnualText;
  final String totalFlowText;
  final List<double> totalFlowSeries;
  final String nominalFlowText;
  final WaterImpact? water;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    return Dashboard(
      machineCount: json['machineCount'] as int,
      activeAlarms: json['activeAlarms'] as int,
      openWorkOrders: json['openWorkOrders'] as int,
      verifyingWorkOrders: json['verifyingWorkOrders'] as int? ?? 0,
      totalPowerText: json['totalPowerText'] as String? ?? '—',
      activeLossText: json['activeLossText'] as String? ?? '—',
      verifiedSavingsText: json['verifiedSavingsText'] as String? ?? '—',
      verifiedCo2Text: json['verifiedCo2Text'] as String? ?? '—',
      machines: _machines(json['machines']),
      alarms: _alarms(json['alarms']),
      verifiedAnnualText: json['verifiedAnnualText'] as String? ?? '—',
      totalFlowText: json['totalFlowText'] as String? ?? '—',
      totalFlowSeries: _doubles(json['totalFlowSeries']),
      nominalFlowText: json['nominalFlowText'] as String? ?? '—',
      water: json['water'] is Map<String, dynamic>
          ? WaterImpact.fromJson(json['water'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Doğrulanan enerji tasarrufunun santral soğutmasında önlediği su ve katsayının kaynağı.
class WaterImpact {
  const WaterImpact({
    required this.configured,
    required this.avoidedText,
    required this.avoidedKwhText,
    required this.factorText,
    required this.scopeText,
    required this.sourceText,
    required this.sourceUrl,
    required this.formulaText,
    this.co2FactorText = '',
    this.co2SourceText = '',
    this.co2SourceUrl = '',
  });

  final bool configured;
  final String avoidedText;
  final String avoidedKwhText;
  final String factorText;
  final String scopeText;
  final String sourceText;
  final String sourceUrl;
  final String formulaText;
  final String co2FactorText;
  final String co2SourceText;
  final String co2SourceUrl;

  factory WaterImpact.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] as String? ?? '';
    return WaterImpact(
      configured: json['configured'] as bool? ?? false,
      avoidedText: text('avoidedText'),
      avoidedKwhText: text('avoidedKwhText'),
      factorText: text('factorText'),
      scopeText: text('scopeText'),
      sourceText: text('sourceText'),
      sourceUrl: text('sourceUrl'),
      formulaText: text('formulaText'),
      co2FactorText: text('co2FactorText'),
      co2SourceText: text('co2SourceText'),
      co2SourceUrl: text('co2SourceUrl'),
    );
  }
}

List<double> _doubles(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => (item as num).toDouble())
      .toList();
}

List<Machine> _machines(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => Machine.fromJson(item as Map<String, dynamic>))
      .toList();
}

List<Alarm> _alarms(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => Alarm.fromJson(item as Map<String, dynamic>))
      .toList();
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, required this.session})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.token;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // Süresi dolan veya API yeniden başlarken geçersizleşen oturumda
          // kullanıcıyı hata ekranında bırakmak yerine girişe döndür.
          final isLogin = error.requestOptions.path == '/auth/login';
          if (!isLogin && error.response?.statusCode == 401) {
            session.signOut();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final Session session;

  Future<LoginResult> login(String username, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      final body = response.data;
      if (body == null) {
        throw const ApiException('API boş yanıt verdi.');
      }
      return LoginResult(
        accessToken: body['accessToken'] as String,
        role: body['role'] as String,
        displayName: body['displayName'] as String,
      );
    } on DioException catch (error) {
      throw ApiException(
        _message(error, unauthorized: 'Kullanıcı adı veya parola hatalı.'),
      );
    }
  }

  Future<List<Machine>> machines() async {
    try {
      final response = await _dio.get<List<dynamic>>('/machines');
      return (response.data ?? const [])
          .map((item) => Machine.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException(_message(error, unauthorized: 'Oturum geçersiz.'));
    }
  }

  Future<List<Alarm>> alarms() async {
    try {
      final response = await _dio.get<List<dynamic>>('/alarms');
      return _alarms(response.data);
    } on DioException catch (error) {
      throw ApiException(_message(error, unauthorized: 'Oturum geçersiz.'));
    }
  }

  Future<String> fault(int machineId) => _action('/machines/$machineId/fault');

  Future<String> normal(int machineId) =>
      _action('/machines/$machineId/normal');

  Future<String> maintenance(int alarmId) =>
      _action('/alarms/$alarmId/maintenance');

  Future<void> registerDevice(String token) async {
    try {
      await _dio.post('/devices', data: {'token': token});
    } on DioException {
      return;
    }
  }

  Future<void> unregisterDevice(String token) async {
    try {
      await _dio.delete('/devices/$token');
    } on DioException {
      return;
    }
  }

  Future<List<Notice>> notifications() async {
    try {
      // Bildirim kuyruğu cihaza özeldir: masaüstü ve telefon aynı alarmı ayrı ayrı alır.
      final response = await _dio.get<List<dynamic>>(
        '/notifications',
        queryParameters: {'device': session.deviceToken},
      );
      return (response.data ?? const [])
          .map((item) => Notice.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException(_message(error, unauthorized: 'Oturum geçersiz.'));
    }
  }

  Future<void> ack(int id) async {
    try {
      await _dio.post(
        '/notifications/$id/ack',
        queryParameters: {'device': session.deviceToken},
      );
    } on DioException {
      return;
    }
  }

  Future<String> _action(String path) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path);
      return response.data?['message'] as String? ?? 'Tamam.';
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['message'] is String) {
        throw ApiException(body['message'] as String);
      }
      throw ApiException(
        _message(error, unauthorized: 'Bu işlem için yetkiniz yok.'),
      );
    }
  }

  Future<Dashboard> dashboard() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/dashboard');
      final body = response.data;
      if (body == null) {
        throw const ApiException('API boş yanıt verdi.');
      }
      return Dashboard.fromJson(body);
    } on DioException catch (error) {
      throw ApiException(
        _message(error, unauthorized: 'Bu ekran yalnızca yöneticiye açık.'),
      );
    }
  }

  Future<List<Personnel>> personnel() async {
    try {
      final response = await _dio.get<List<dynamic>>('/personnel');
      return (response.data ?? const [])
          .map((item) => Personnel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException(
        _message(error, unauthorized: 'Personel yalnızca yöneticiye açık.'),
      );
    }
  }

  Future<AssignmentResult> assignMachine(int personnelId, int machineId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/personnel/$personnelId/assign/$machineId',
      );
      final body = response.data;
      if (body == null) {
        throw const ApiException('API boş yanıt verdi.');
      }
      return AssignmentResult.fromJson(body);
    } on DioException catch (error) {
      throw ApiException(
        _message(error, unauthorized: 'Atama yalnızca yöneticiye açık.'),
      );
    }
  }

  Future<AssignmentResult> unassignMachine(int machineId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/machines/$machineId/unassign',
      );
      final body = response.data;
      if (body == null) {
        throw const ApiException('API boş yanıt verdi.');
      }
      return AssignmentResult.fromJson(body);
    } on DioException catch (error) {
      throw ApiException(
        _message(error, unauthorized: 'Atama yalnızca yöneticiye açık.'),
      );
    }
  }

  String _message(DioException error, {required String unauthorized}) {
    if (error.response?.statusCode == 401 ||
        error.response?.statusCode == 403) {
      return unauthorized;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'API kapalı. EcoPulse kısayolunu yeniden açın.';
    }
    return 'İstek tamamlanamadı.';
  }
}
