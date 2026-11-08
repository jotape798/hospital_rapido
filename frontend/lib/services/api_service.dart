import '../models/api_models.dart';
import '../config/api_config.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const baseUrl = ApiConfig.baseUrl;
  static const storage = FlutterSecureStorage();
  static String? _token;
  static Session? session;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token'
      };
  static Future<bool> restoreSession() async {
    final p = await SharedPreferences.getInstance();
    // Remove somente preferências legadas do recurso de lembrar CPF.
    for (final key in ['ubs_cpf', 'ubs_remember_user']) {
      await p.remove(key);
    }
    _token = null;
    session = null;
    return false;
  }

  static Future<void> logout() async {
    _token = null;
    session = null;
    if (!kIsWeb) await storage.delete(key: 'ubs_token');
  }

  Future<Session> login(String document, String password) async =>
      _save(await _post('/auth/login', {
        'document': document.replaceAll(RegExp(r'[.\-\s]'), ''),
        'password': password
      }));
  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async =>
      await _post('/auth/register', data);

  Future<void> correctRegistrationEmail(
      String verificationToken, String newEmail) async {
    await _post('/auth/email/corrigir', {
      'verification_token': verificationToken,
      'new_email': newEmail.trim().toLowerCase(),
    });
  }

  Future<int> requestEmailVerification(String email) async {
    final response = await _post(
        '/auth/email/solicitar-codigo', {'email': email.trim().toLowerCase()});
    return (response['resend_after_seconds'] as num?)?.toInt() ?? 60;
  }

  Future<int> resendEmailVerification(String email) async {
    final response = await _post(
        '/auth/email/reenviar-codigo', {'email': email.trim().toLowerCase()});
    return (response['resend_after_seconds'] as num?)?.toInt() ?? 60;
  }

  Future<String> validateEmailVerification(String email, String code) async =>
      (await _post('/auth/email/validar-codigo', {
        'email': email.trim().toLowerCase(),
        'code': code,
      }))['message'] as String? ??
      'E-mail validado com sucesso.';

  Future<Map<String, dynamic>> forgotPassword(String email) async =>
      _post('/auth/esqueci-senha', {'email': email.trim().toLowerCase()});

  Future<String> verifyRecovery(String email, String code) async =>
      (await _post('/auth/validar-codigo-recuperacao', {
        'email': email.trim().toLowerCase(),
        'code': code
      }))['recovery_token'] as String;
  Future<void> changePassword(String currentPassword, String password) async {
    await _post('/auth/change-password',
        {'current_password': currentPassword, 'password': password});
  }

  Future<void> resetPassword(
      String recoveryToken, String password, String confirmation) async {
    await _post('/auth/redefinir-senha', {
      'recovery_token': recoveryToken,
      'new_password': password,
      'confirm_new_password': confirmation
    });
  }

  Future<List<Appointment>> appointments() async =>
      _list(await _request('GET', '/appointments/me'))
          .map(Appointment.fromJson)
          .toList();
  Future<PatientProfile> patient() async => PatientProfile.fromJson(
      jsonDecode((await _request('GET', '/patients/me')).body));
  Future<PatientSummary> summary() async => PatientSummary.fromJson(
      jsonDecode((await _request('GET', '/patients/me/summary')).body));
  Future<Appointment> appointment(int id) async => Appointment.fromJson(
      jsonDecode((await _request('GET', '/appointments/$id')).body));
  Future<List<Map<String, dynamic>>> professionals(String specialty) async =>
      _list(await _request('GET',
          '/professionals?specialty=${Uri.encodeQueryComponent(specialty)}'));
  Future<List<Map<String, dynamic>>> bookingProfessionals() async =>
      _list(await _request('GET', '/professionals'));
  Future<List<Map<String, dynamic>>> specialtiesForProfessional(
          int professionalId) async =>
      _list(await _request(
          'GET', '/specialties?professional_id=$professionalId'));
  Future<List<DateTime>> availableDates(String specialty, int doctorId) async =>
      (jsonDecode((await _request('GET',
                  '/availability/calendar-dates?specialty=${Uri.encodeQueryComponent(specialty)}&doctor_id=$doctorId'))
              .body) as List)
          .map((x) => DateTime.parse(x as String))
          .toList();
  Future<List<Slot>> availableTimes(
          String specialty, int doctorId, DateTime day) async =>
      _list(await _request('GET',
              '/availability/calendar-times?specialty=${Uri.encodeQueryComponent(specialty)}&doctor_id=$doctorId&day=${day.toIso8601String().substring(0, 10)}'))
          .map(Slot.fromJson)
          .toList();
  Future<List<Map<String, dynamic>>> queue(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? risk,
      String? patient}) async {
    final query = <String, String>{
      'day': _day(day ?? DateTime.now()),
      if (specialty?.trim().isNotEmpty ?? false) 'specialty': specialty!.trim(),
      if (professionalId != null) 'professional_id': '$professionalId',
      if (status?.trim().isNotEmpty ?? false) 'status': status!.trim(),
      if (risk?.trim().isNotEmpty ?? false) 'risk': risk!.trim(),
      if (patient?.trim().isNotEmpty ?? false) 'patient': patient!.trim(),
    };
    return _list(
        await _request('GET', '/queue?${Uri(queryParameters: query).query}'));
  }

  Future<void> book(Slot s) async {
    await _post('/appointments', {
      'doctor_id': s.doctorId,
      'specialty': s.specialty,
      'scheduled_at': s.scheduledAt.toIso8601String()
    });
  }

  Future<String> cancel(int id) async =>
      (await _post('/appointments/$id/cancel', {}))['message'] as String? ??
      'Consulta cancelada.';

  Future<void> reschedule(int id, Slot s) async {
    await _post('/appointments/$id/reschedule', {
      'doctor_id': s.doctorId,
      'scheduled_at': s.scheduledAt.toIso8601String()
    });
  }

  Future<Session> _save(Map<String, dynamic> v) async {
    _token = v['access_token'];
    final u = v['user'];
    final permissions = ((v['permissions'] ?? u['permissions'] ?? []) as List)
        .map((x) => x.toString())
        .toList();
    session = Session(_token!, u['name'], u['role'], permissions);
    return session!;
  }

  Future<http.Response> _request(String method, String path,
      [Object? body]) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final r = await (switch (method) {
        'GET' => http.get(uri, headers: _headers),
        'PUT' => http.put(uri, headers: _headers, body: jsonEncode(body)),
        'PATCH' => http.patch(uri, headers: _headers, body: jsonEncode(body)),
        'DELETE' => http.delete(uri, headers: _headers),
        _ => http.post(uri, headers: _headers, body: jsonEncode(body)),
      })
          .timeout(const Duration(seconds: 45));
      if (r.statusCode == 401 && path != '/auth/login') {
        await logout();
        throw const ApiException('Sessão expirada. Entre novamente.',
            statusCode: 401);
      }
      if (r.statusCode < 200 || r.statusCode >= 300) throw _error(r);
      return r;
    } on TimeoutException {
      throw const ApiException(
          'A UBS demorou para responder. Tente novamente.');
    } on http.ClientException {
      throw const ApiException(
          'Não foi possível conectar à UBS. Verifique sua conexão.');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final r = await _request('POST', path, body);
    return r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> changeStatus(int id, String status,
      {String? risk, String? triage}) async {
    switch (status) {
      case 'em_espera':
        return receptionCheckIn(id);
      case 'em_triagem':
        return classifyRisk(id, risk!, triage!, triage, null);
      case 'em_atendimento':
        return startCare(id);
      case 'concluido':
        return completeCare(id);
      default:
        throw const ApiException('Transição de atendimento inválida.');
    }
  }

  Future<List<Map<String, dynamic>>> specialties() async =>
      _list(await _request('GET', '/specialties'));

  Future<AdminSummary> adminSummary([DateTime? day]) async =>
      AdminSummary.fromJson(jsonDecode((await _request(
              'GET', '/admin/summary?day=${_day(day ?? DateTime.now())}'))
          .body));

  Future<List<InternalUser>> internalUsers(
      {String? search, String? role, bool? active}) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
      if (role != null && role.isNotEmpty) 'role': role,
      if (active != null) 'active': active.toString(),
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return _list(await _request('GET', '/admin/users$suffix'))
        .map(InternalUser.fromJson)
        .toList();
  }

  Future<InternalUser> createInternalUser(Map<String, dynamic> data) async =>
      InternalUser.fromJson(await _post('/admin/users', data));

  Future<InternalUser> createAdmin(Map<String, dynamic> data) async =>
      InternalUser.fromJson(await _post('/admin/admins', data));

  Future<InternalUser> updateInternalUser(
          int id, Map<String, dynamic> data) async =>
      InternalUser.fromJson(
          jsonDecode((await _request('PUT', '/admin/users/$id', data)).body));

  Future<InternalUser> setInternalUserActive(int id, bool active) async =>
      InternalUser.fromJson(await _post(
          '/admin/users/$id/${active ? 'activate' : 'deactivate'}', {}));

  Future<void> resetInternalAccess(
      int id, String password, String confirmation) async {
    await _post('/admin/users/$id/reset-access', {
      'password': password,
      'password_confirmation': confirmation,
    });
  }

  Future<List<AdminAppointment>> adminAppointments(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? risk,
      String? patient}) async {
    final query = <String, String>{
      'day': _day(day ?? DateTime.now()),
      if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
      if (professionalId != null) 'professional_id': '$professionalId',
      if (status != null && status.isNotEmpty) 'status': status,
      if (risk != null && risk.isNotEmpty) 'risk': risk,
      if (patient != null && patient.trim().isNotEmpty)
        'patient': patient.trim(),
    };
    return _list(await _request(
            'GET', '/admin/appointments?${Uri(queryParameters: query).query}'))
        .map(AdminAppointment.fromJson)
        .toList();
  }

  Future<void> checkIn(int id) async {
    await _request('PATCH', '/recepcao/agendamentos/$id/check-in', {});
  }

  Future<void> registerAbsence(int id) async {
    await _post('/admin/appointments/$id/absence', {});
  }

  Future<Map<String, dynamic>> receptionSummary([DateTime? day]) async =>
      jsonDecode((await _request(
              'GET', '/recepcao/resumo?day=${_day(day ?? DateTime.now())}'))
          .body) as Map<String, dynamic>;

  Future<List<AdminAppointment>> receptionAppointments(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? patient}) async {
    final query = <String, String>{
      'day': _day(day ?? DateTime.now()),
      if (specialty?.isNotEmpty ?? false) 'specialty': specialty!,
      if (professionalId != null) 'professional_id': '$professionalId',
      if (status?.isNotEmpty ?? false) 'status': status!,
      if (patient?.trim().isNotEmpty ?? false) 'patient': patient!.trim(),
    };
    return _list(await _request('GET',
            '/recepcao/agendamentos?${Uri(queryParameters: query).query}'))
        .map(AdminAppointment.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> receptionDetails(int id) async =>
      jsonDecode((await _request('GET', '/recepcao/agendamentos/$id')).body)
          as Map<String, dynamic>;

  Future<void> receptionCheckIn(int id) async {
    await _request('PATCH', '/recepcao/agendamentos/$id/check-in', {});
  }

  Future<void> receptionAbsence(int id) async {
    await _request('PATCH', '/recepcao/agendamentos/$id/nao-compareceu', {});
  }

  Future<void> receptionValidatePriorityCondition(
      int appointmentId, String condition, String status) async {
    await _request(
        'PATCH',
        '/recepcao/agendamentos/$appointmentId/condicoes/$condition/validacao',
        {'status': status});
  }

  Future<Map<String, dynamic>> nursingSummary([DateTime? day]) async =>
      jsonDecode((await _request(
              'GET', '/enfermagem/resumo?day=${_day(day ?? DateTime.now())}'))
          .body) as Map<String, dynamic>;

  Future<List<AdminAppointment>> nursingQueue(
      {DateTime? day, String? specialty, String? status, String? risk}) async {
    final query = <String, String>{
      'day': _day(day ?? DateTime.now()),
      if (specialty?.isNotEmpty ?? false) 'specialty': specialty!,
      if (status?.isNotEmpty ?? false) 'status': status!,
      if (risk?.isNotEmpty ?? false) 'risk': risk!,
    };
    return _list(await _request(
            'GET', '/enfermagem/fila?${Uri(queryParameters: query).query}'))
        .map(AdminAppointment.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> nursingDetails(int id) async =>
      jsonDecode((await _request('GET', '/enfermagem/agendamentos/$id')).body)
          as Map<String, dynamic>;

  Future<void> classifyRisk(int id, String level, String complaint,
      String vitalSigns, String? observation) async {
    await _request(
        'PATCH', '/enfermagem/agendamentos/$id/classificacao-risco', {
      'level': level,
      'complaint': complaint.trim(),
      'vital_signs': vitalSigns.trim(),
      if (observation?.trim().isNotEmpty ?? false)
        'observation': observation!.trim(),
    });
  }

  Future<void> startCare(int id) async {
    await _request('PATCH', '/medico/atendimentos/$id/iniciar', {});
  }

  Future<void> completeCare(int id) async {
    await _request('PATCH', '/medico/atendimentos/$id/concluir',
        {'summary': 'Atendimento concluído pelo painel profissional.'});
  }

  Future<List<MedicalAppointment>> medicalQueue() async =>
      _list(await _request('GET', '/medico/fila'))
          .map(MedicalAppointment.fromJson)
          .toList();

  Future<MedicalAppointment> medicalDetails(int id) async =>
      MedicalAppointment.fromJson(
          jsonDecode((await _request('GET', '/medico/atendimentos/$id')).body));

  Future<MedicalAppointment> startMedicalCare(int id) async =>
      MedicalAppointment.fromJson(jsonDecode(
          (await _request('PATCH', '/medico/atendimentos/$id/iniciar', {}))
              .body));

  Future<MedicalAppointment> completeMedicalCare(
          int id, String summary) async =>
      MedicalAppointment.fromJson(jsonDecode((await _request('PATCH',
              '/medico/atendimentos/$id/concluir', {'summary': summary.trim()}))
          .body));

  Future<List<DoctorAccount>> doctors({String? search, bool? active}) async {
    final query = <String, String>{
      if (search?.trim().isNotEmpty ?? false) 'q': search!.trim(),
      if (active != null) 'active': active.toString(),
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return _list(await _request('GET', '/admin/medicos$suffix'))
        .map(DoctorAccount.fromJson)
        .toList();
  }

  Future<DoctorAccount> createDoctor(Map<String, dynamic> data) async =>
      DoctorAccount.fromJson(await _post('/admin/medicos', data));

  Future<DoctorAccount> updateDoctor(int id, Map<String, dynamic> data) async =>
      DoctorAccount.fromJson(
          jsonDecode((await _request('PUT', '/admin/medicos/$id', data)).body));

  Future<DoctorAccount> setDoctorActive(int id, bool active) async =>
      DoctorAccount.fromJson(await _post(
          '/admin/medicos/$id/${active ? 'activate' : 'deactivate'}', {}));

  Future<List<AdminAppointment>> professionalQueue([DateTime? day]) async =>
      _list(await _request('GET', '/medico/fila'))
          .map(AdminAppointment.fromJson)
          .toList();

  Future<Map<String, dynamic>> professionalDetails(int id) async =>
      jsonDecode((await _request('GET', '/medico/atendimentos/$id')).body)
          as Map<String, dynamic>;

  Future<void> callPatient(int id) async {
    await _request('PATCH', '/medico/atendimentos/$id/chamar', {});
  }

  Future<Map<String, dynamic>> adminAppointmentDetails(int id) async =>
      jsonDecode((await _request('GET', '/admin/appointments/$id')).body)
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> auditHistory() async =>
      _list(await _request('GET', '/admin/audit'));

  Future<List<Map<String, dynamic>>> priorityValidations() async =>
      _list(await _request('GET', '/admin/priority-validations'));

  Future<List<Map<String, dynamic>>> grids() async =>
      _list(await _request('GET', '/admin/grids'));

  Future<void> createGrid(Map<String, dynamic> data) async {
    await _post('/admin/grids', data);
  }

  Future<void> removeGrid(int id) async {
    await _request('DELETE', '/admin/grids/$id');
  }

  Future<Map<String, dynamic>> createSpecialty(String name) async =>
      _post('/admin/specialties', {'name': name});

  Future<List<Map<String, dynamic>>> adminSpecialties() async =>
      _list(await _request('GET', '/admin/specialties'));

  Future<Map<String, dynamic>> updateSpecialty(int id, String name) async =>
      jsonDecode(
          (await _request('PUT', '/admin/specialties/$id', {'name': name}))
              .body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> setSpecialtyActive(int id, bool active) async =>
      _post('/admin/specialties/$id/${active ? 'activate' : 'deactivate'}', {});

  Future<List<Map<String, dynamic>>> allProfessionals() async =>
      _list(await _request('GET', '/admin/schedule-professionals'));

  String _day(DateTime value) => value.toIso8601String().substring(0, 10);
  List<Map<String, dynamic>> _list(http.Response r) {
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    }
    throw _error(r);
  }

  ApiException _error(http.Response r) {
    try {
      final detail = jsonDecode(r.body)['detail'];
      if (detail is Map) {
        return ApiException(detail['message'].toString(),
            field: detail['field'] as String?, statusCode: r.statusCode);
      }
      if (detail is List && detail.isNotEmpty) {
        return ApiException(
            detail.first['msg']?.toString() ?? 'Confira o campo informado.',
            field: (detail.first['loc'] as List).last.toString(),
            statusCode: r.statusCode);
      }
      return ApiException(detail.toString(), statusCode: r.statusCode);
    } catch (_) {
      return const ApiException('Não foi possível comunicar com a UBS.');
    }
  }
}
