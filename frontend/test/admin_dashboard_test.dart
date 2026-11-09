import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class FakeAdminApi extends ApiService {
  @override
  Future<AdminSummary> adminSummary([DateTime? day]) async =>
      AdminSummary.fromJson({
        'scheduled': 4,
        'checked_in': 2,
        'waiting': 2,
        'in_care': 1,
        'completed': 3,
        'cancelled': 1,
      });

  @override
  Future<List<InternalUser>> internalUsers(
          {String? search, String? role, bool? active}) async =>
      [];

  @override
  Future<List<AdminAppointment>> adminAppointments(
          {DateTime? day,
          String? specialty,
          int? professionalId,
          String? status,
          String? risk,
          String? patient}) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> queue(
          {DateTime? day,
          String? specialty,
          int? professionalId,
          String? status,
          String? risk,
          String? patient}) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> specialties() async => [];

  @override
  Future<List<Map<String, dynamic>>> adminSpecialties() async => [];

  @override
  Future<List<Map<String, dynamic>>> allProfessionals() async => [];

  @override
  Future<List<Map<String, dynamic>>> auditHistory() async => [];

  @override
  Future<List<Map<String, dynamic>>> priorityValidations() async => [];

  @override
  Future<List<Map<String, dynamic>>> grids() async => [];
}

class FakeAgendaApi extends FakeAdminApi {
  final agendaItem = AdminAppointment.fromJson({
    'id': 10,
    'scheduled_at': '2026-09-25T08:00:00',
    'patient': 'Paciente Fictício',
    'patient_document': '***.***.***-25',
    'specialty': 'Clínica geral',
    'professional': 'Dra. Ana',
    'professional_id': 2,
    'status': 'agendado',
    'legal_priority': 'geral',
  });

  @override
  Future<List<AdminAppointment>> adminAppointments(
          {DateTime? day,
          String? specialty,
          int? professionalId,
          String? status,
          String? risk,
          String? patient}) async =>
      [agendaItem];

  @override
  Future<Map<String, dynamic>> adminAppointmentDetails(int id) async => {
        'id': id,
        'scheduled_at': '2026-09-25T08:00:00',
        'patient': 'Paciente Fictício',
        'patient_document': '***.***.***-25',
        'specialty': 'Clínica geral',
        'professional': 'Dra. Ana',
        'status': 'agendado',
        'legal_priority': 'geral',
        'risk_classification': null,
      };
}

class FakeAdminContentApi extends FakeAdminApi {
  static const longName =
      'Profissional Administrativa com Nome Muito Longo da Silva';
  static const longSpecialty =
      'Clínica integrada da família e comunidade ampliada';

  @override
  Future<List<InternalUser>> internalUsers(
          {String? search, String? role, bool? active}) async =>
      [
        InternalUser.fromJson({
          'id': 1,
          'name': longName,
          'masked_cpf': '***.***.***-25',
          'email': 'profissional@example.test',
          'role': 'profissional',
          'active': true,
          'professional_registration': 'CRM 123',
          'specialty_id': 1,
          'specialty': longSpecialty,
          'can_triage': true,
        })
      ];

  @override
  Future<List<Map<String, dynamic>>> adminSpecialties() async => [
        {'id': 1, 'name': longSpecialty, 'active': true}
      ];

  @override
  Future<List<Map<String, dynamic>>> auditHistory() async => [
        {
          'action': 'usuario_ativado',
          'actor': 'Ana Administradora',
          'record_type': 'usuario',
          'record_id': 1,
          'created_at': '2026-10-07T14:30:00'
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> priorityValidations() async => [
        {
          'patient': 'Paciente Fictícia',
          'condition': 'pcd',
          'status': 'confirmada',
          'validated_by': 'Recepção Fictícia',
          'validated_at': '2026-10-07T14:25:00',
          'history': [
            {'new_status': 'pendente'},
            {'new_status': 'confirmada'}
          ],
        }
      ];
}

class FakeAdminQueueApi extends FakeAdminApi {
  @override
  Future<List<Map<String, dynamic>>> queue(
          {DateTime? day,
          String? specialty,
          int? professionalId,
          String? status,
          String? risk,
          String? patient}) async =>
      [
        for (var index = 1; index <= 6; index++)
          {
            'position': index,
            'patient': 'Paciente $index',
            'specialty': index.isEven ? 'Clínica geral' : 'Pediatria',
            'professional': 'Profissional $index',
            'arrived_at':
                '2026-10-20T${(8 + index).toString().padLeft(2, '0')}:10:00',
            'legal_priority': index == 1 ? 'gestante' : 'geral',
            'risk_classification': index == 1 ? 'alto' : 'moderado',
            'status': index == 1 ? 'em_atendimento' : 'em_triagem',
          }
      ];
}

class FakeOperationalFiltersApi extends FakeAdminApi {
  String? agendaSpecialty,
      agendaStatus,
      agendaRisk,
      agendaPatient,
      queueSpecialty,
      queueStatus,
      queueRisk,
      queuePatient;
  int? agendaProfessionalId, queueProfessionalId;
  Completer<List<Map<String, dynamic>>>? nextQueueRequest;

  final agendaItem = AdminAppointment.fromJson({
    'id': 91,
    'scheduled_at': '2026-10-21T09:00:00',
    'patient': 'Maria Fictícia',
    'patient_document': '***.***.***-25',
    'specialty': 'Clínica geral',
    'professional': 'Dra. Ana',
    'professional_id': 7,
    'status': 'em_triagem',
    'legal_priority': 'geral',
    'risk_classification': 'alto',
  });

  @override
  Future<List<AdminAppointment>> adminAppointments(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? risk,
      String? patient}) async {
    agendaSpecialty = specialty;
    agendaProfessionalId = professionalId;
    agendaStatus = status;
    agendaRisk = risk;
    agendaPatient = patient;
    return patient?.trim() == 'Ninguém' ? [] : [agendaItem];
  }

  @override
  Future<List<Map<String, dynamic>>> queue(
      {DateTime? day,
      String? specialty,
      int? professionalId,
      String? status,
      String? risk,
      String? patient}) async {
    queueSpecialty = specialty;
    queueProfessionalId = professionalId;
    queueStatus = status;
    queueRisk = risk;
    queuePatient = patient;
    final pending = nextQueueRequest;
    if (pending != null) {
      nextQueueRequest = null;
      return pending.future;
    }
    if (patient?.trim() == 'Ninguém') return [];
    return [
      {
        'position': 1,
        'id': 91,
        'patient': 'Maria F.',
        'specialty': 'Clínica geral',
        'professional': 'Dra. Ana',
        'professional_id': 7,
        'arrived_at': '2026-10-21T08:50:00',
        'legal_priority': 'geral',
        'risk_classification': 'alto',
        'status': 'em_triagem',
      }
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> adminSpecialties() async => [
        {'id': 1, 'name': 'Clínica geral', 'active': true}
      ];

  @override
  Future<List<Map<String, dynamic>>> allProfessionals() async => [
        {'id': 7, 'name': 'Dra. Ana'}
      ];
}

class FakeSpecialtyManagementApi extends FakeAdminApi {
  final items = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Clínica Geral', 'active': true}
  ];

  @override
  Future<List<Map<String, dynamic>>> adminSpecialties() async =>
      items.map((item) => Map<String, dynamic>.from(item)).toList();

  @override
  Future<Map<String, dynamic>> createSpecialty(String name) async {
    final normalized = name.trim().toLowerCase();
    if (items.any(
        (item) => item['name'].toString().trim().toLowerCase() == normalized)) {
      throw const ApiException('Especialidade já cadastrada', statusCode: 409);
    }
    final item = <String, dynamic>{
      'id': items.length + 1,
      'name': name.trim(),
      'active': true
    };
    items.add(item);
    return Map<String, dynamic>.from(item);
  }

  @override
  Future<Map<String, dynamic>> updateSpecialty(int id, String name) async {
    final item = items.firstWhere((value) => value['id'] == id);
    item['name'] = name.trim();
    return Map<String, dynamic>.from(item);
  }

  @override
  Future<Map<String, dynamic>> setSpecialtyActive(int id, bool active) async {
    final item = items.firstWhere((value) => value['id'] == id);
    item['active'] = active;
    return Map<String, dynamic>.from(item);
  }
}

Future<void> selectAdminDestination(
    WidgetTester tester, String _, String destination) async {
  final compactPicker =
      find.byKey(const Key('responsive-compact-destination-picker'));
  if (compactPicker.evaluate().isNotEmpty) {
    await tester.tap(compactPicker);
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('wide-navigation-panel'));
    final scrollable =
        find.descendant(of: panel, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(destination), 180,
        scrollable: scrollable);
    await tester.ensureVisible(find.text(destination).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(destination).last);
    await tester.pumpAndSettle();
    return;
  }

  final navigation = find.byType(NavigationRail);
  final scrollable =
      find.descendant(of: navigation, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(destination), 180,
      scrollable: scrollable);
  await tester.ensureVisible(find.text(destination).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(destination).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
    ApiService.session = const Session('token-ficticio', 'Ana Administradora',
        'admin', ['users:manage', 'appointments:checkin']);
  });

  tearDown(() {
    ApiService.session = null;
    accessibility.setContrast(false);
    accessibility.setFontScale(1);
  });

  testWidgets('admin_wide_shows_navigation_and_content_without_overlap',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();
    expect(find.byType(ResponsiveAppShell), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('grouped-wide-navigation')), findsNothing);
    expect(find.text('Visão geral'), findsOneWidget);
    expect(find.text('Agenda do dia'), findsOneWidget);
    final navigation = find.byType(NavigationRail);
    final navigationColors = tester
        .widgetList<Icon>(
            find.descendant(of: navigation, matching: find.byType(Icon)))
        .map((icon) => icon.color)
        .whereType<Color>()
        .toSet();
    expect(navigationColors, contains(const Color(0xFF0F6B3A)));
    expect(navigationColors, contains(const Color(0xFF005A9C)));
    expect(navigationColors, contains(const Color(0xFF6A3DA6)));
    expect(navigationColors, contains(const Color(0xFF9A4A00)));
    expect(
        AdminSection.specialties.icon, isNot(AdminSection.professionals.icon));
    final scrollable = find
        .descendant(of: navigation, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Usuários internos'), 180,
        scrollable: scrollable);
    expect(find.text('Usuários internos'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Configurações'), 180,
        scrollable: scrollable);
    expect(find.text('Configurações'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin_compact_shows_one_module_at_a_time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('responsive-compact-destination-picker')),
        findsOneWidget);
    expect(find.text('Consultas agendadas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('região administrativa rolável recebe foco e rola pelo teclado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();

    final focusRegion = find.byKey(const Key('admin-scroll-region-focus'));
    expect(focusRegion, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Conteúdo rolável: Visão do dia')),
        findsOneWidget);
    final focusNode = tester.widget<Focus>(focusRegion).focusNode!;
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    final module = find.byKey(const Key('admin-module-content'));
    final scrollable =
        find.descendant(of: module, matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('módulos administrativos mantêm rolagens independentes',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(390, 600),
      Size(768, 600),
      Size(1366, 600),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(UbsApp(
          home: AdminDashboard(
              key: ValueKey('admin-scroll-$size'), api: FakeAdminApi())));
      await tester.pumpAndSettle();

      Finder moduleScrollable() => find
          .descendant(
              of: find.byKey(const Key('admin-module-content')),
              matching: find.byType(Scrollable))
          .first;

      await tester.drag(moduleScrollable(), const Offset(0, -420));
      await tester.pumpAndSettle();
      final overviewPosition =
          tester.state<ScrollableState>(moduleScrollable()).position.pixels;
      expect(overviewPosition, greaterThan(0), reason: 'largura $size');

      await selectAdminDestination(
          tester, 'Atendimento', 'Fila de atendimento');
      final queuePosition =
          tester.state<ScrollableState>(moduleScrollable()).position.pixels;
      expect(queuePosition, 0,
          reason: 'A fila não deve herdar a rolagem em $size.');

      await selectAdminDestination(tester, 'Atendimento', 'Visão geral');
      final restoredOverview =
          tester.state<ScrollableState>(moduleScrollable()).position.pixels;
      expect(restoredOverview, closeTo(overviewPosition, 1),
          reason: 'A seção anterior deve preservar sua própria posição.');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('admin_summary_survives_max_text_scale', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    accessibility.setFontScale(1.3);
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Consultas agendadas'), 180,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Consultas agendadas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fila associa status ao paciente e mantém último card acessível',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeAdminQueueApi();

    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(UbsApp(
        home: AdminDashboard(key: const ValueKey('compact-queue'), api: api)));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Atendimento', 'Fila de atendimento');
    final wideCard = find.byKey(const Key('admin-queue-card-1'));
    final wideStatus = find.byKey(const Key('admin-queue-status-1'));
    expect(wideCard, findsOneWidget);
    expect(wideStatus, findsOneWidget);
    expect(tester.getTopLeft(wideStatus).dx,
        greaterThan(tester.getTopLeft(find.text('Paciente 1')).dx));
    expect(tester.widget<Text>(find.text('Paciente 1')).style?.fontSize, 18);

    accessibility.setFontScale(1.3);
    await tester.binding.setSurfaceSize(const Size(360, 760));
    await tester.pumpWidget(UbsApp(
        home: AdminDashboard(
            key: const ValueKey('compact-queue-a-plus'), api: api)));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Atendimento', 'Fila de atendimento');
    final queueList = find
        .descendant(
            of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('admin-queue-card-1'), skipOffstage: false), 120,
        scrollable: queueList);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('admin-queue-status-1'))).dy,
        greaterThan(tester.getTopLeft(find.text('Paciente 1')).dy));
    await tester.scrollUntilVisible(
        find.byKey(const Key('admin-queue-card-6')), 240,
        scrollable: queueList);
    expect(find.byKey(const Key('admin-queue-card-6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agenda combina filtros no servidor e limpa todo o estado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeOperationalFiltersApi();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: api)));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Agenda e oferta', 'Agenda do dia');

    expect(find.byKey(const Key('admin-agenda-filter-region')), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);

    final searchRect =
        tester.getRect(find.byKey(const Key('admin-agenda-search')));
    final statusRect =
        tester.getRect(find.byKey(const ValueKey('admin-agenda-status-null')));
    final specialtyRect = tester
        .getRect(find.byKey(const ValueKey('admin-agenda-specialty-null')));
    final professionalRect = tester
        .getRect(find.byKey(const ValueKey('admin-agenda-professional-null')));
    final riskRect =
        tester.getRect(find.byKey(const ValueKey('admin-agenda-risk-null')));
    final dateRect = tester.getRect(find.byKey(const Key('admin-agenda-date')));
    expect(statusRect.width, closeTo(searchRect.width, .01));
    expect(specialtyRect.width, closeTo(searchRect.width, .01));
    expect(riskRect.width, closeTo(professionalRect.width, .01));
    expect(dateRect.width, closeTo(professionalRect.width, .01));
    expect(professionalRect.left, searchRect.left);
    expect(riskRect.left, statusRect.left);
    expect(dateRect.left, specialtyRect.left);

    await tester.ensureVisible(
        find.byKey(const ValueKey('admin-agenda-specialty-null')));
    await tester.tap(find.byKey(const ValueKey('admin-agenda-specialty-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica Geral').last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('admin-agenda-professional-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dra. Ana').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-agenda-status-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em triagem').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-agenda-risk-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risk-filter-option-alto')).last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('admin-agenda-search')), '  Maria  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(api.agendaSpecialty, 'Clínica geral');
    expect(api.agendaProfessionalId, 7);
    expect(api.agendaStatus, 'em_triagem');
    expect(api.agendaRisk, 'alto');
    expect(api.agendaPatient, '  Maria  ');

    await tester
        .ensureVisible(find.byKey(const Key('admin-agenda-clear-filters')));
    await tester.tap(find.byKey(const Key('admin-agenda-clear-filters')));
    await tester.pumpAndSettle();
    expect(api.agendaSpecialty, isNull);
    expect(api.agendaProfessionalId, isNull);
    expect(api.agendaStatus, isNull);
    expect(api.agendaRisk, isNull);
    expect(api.agendaPatient, isEmpty);
    final search =
        tester.widget<TextField>(find.byKey(const Key('admin-agenda-search')));
    expect(search.controller?.text, isEmpty);
  });

  testWidgets('fila mostra carregamento, vazio e restaura ao limpar filtros',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeOperationalFiltersApi();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: api)));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Atendimento', 'Fila de atendimento');

    expect(find.byKey(const Key('admin-queue-filter-region')), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);
    final pending = Completer<List<Map<String, dynamic>>>();
    api.nextQueueRequest = pending;
    await tester.enterText(
        find.byKey(const Key('admin-queue-search')), 'Ninguém');
    await tester.tap(find.byTooltip('Buscar paciente'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum paciente corresponde aos filtros selecionados.'),
        findsOneWidget);
    expect(api.queuePatient, 'Ninguém');

    await tester
        .ensureVisible(find.byKey(const Key('admin-queue-clear-filters')));
    await tester.tap(find.byKey(const Key('admin-queue-clear-filters')));
    await tester.pumpAndSettle();
    expect(api.queuePatient, isEmpty);
    expect(find.text('Maria F.'), findsOneWidget);
  });

  testWidgets('filtros operacionais suportam 320 e 360 pixels com A+',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    accessibility.setFontScale(1.3);
    accessibility.setContrast(true);
    final semantics = tester.ensureSemantics();

    for (final width in [320.0, 360.0]) {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      final api = FakeOperationalFiltersApi();
      await tester.pumpWidget(UbsApp(
          home: AdminDashboard(
              key: ValueKey('operational-filters-$width'), api: api)));
      await tester.pumpAndSettle();
      await selectAdminDestination(tester, 'Agenda e oferta', 'Agenda do dia');
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpAndSettle();
      final agendaList = find.descendant(
          of: find.byKey(const Key('admin-module-content')),
          matching: find.byType(ListView));
      expect(agendaList, findsOneWidget);
      await tester.drag(agendaList, const Offset(0, -600));
      await tester.pumpAndSettle();
      final filterRegion = find.byKey(const Key('admin-agenda-filter-region'));
      expect(filterRegion, findsOneWidget, reason: 'largura $width');
      expect(tester.getSemantics(filterRegion).label,
          contains('Filtros de agendamentos administrativos'));
      expect(find.bySemanticsLabel('Buscar paciente por nome ou CPF'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('admin-agenda-search')), 'Maria');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.agendaPatient, 'Maria');
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('long_internal_user_and_specialty_wrap_without_hiding_actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminContentApi())));
    await tester.pumpAndSettle();
    await selectAdminDestination(
        tester, 'Pessoas e acessos', 'Usuários internos');
    await tester.scrollUntilVisible(
        find.text(FakeAdminContentApi.longName), 180,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(FakeAdminContentApi.longName), findsOneWidget);
    expect(find.byTooltip('Ações do usuário'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin_dialogs_fit_360px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminContentApi())));
    await tester.pumpAndSettle();
    await selectAdminDestination(
        tester, 'Pessoas e acessos', 'Usuários internos');
    expect(tester.takeException(), isNull,
        reason: 'A lista de usuários deve caber antes de abrir o diálogo.');
    await tester.ensureVisible(find.text('Cadastrar usuário'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar usuário'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nova grade inicia com periodo matinal valido sem intervalo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();

    await selectAdminDestination(
        tester, 'Agenda e oferta', 'Grades e horários');
    await tester.tap(find.text('Nova grade'));
    await tester.pumpAndSettle();

    String valueFor(String label) => tester
        .widget<TextFormField>(find.ancestor(
            of: find.text(label), matching: find.byType(TextFormField)))
        .controller!
        .text;

    expect(valueFor('Início'), '09:00');
    expect(valueFor('Fim'), '11:00');
    expect(valueFor('Início intervalo'), isEmpty);
    expect(valueFor('Fim intervalo'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'administrador cria pesquisa e edita especialidade com validacao clara',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeSpecialtyManagementApi();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: api)));
    await tester.pumpAndSettle();

    await selectAdminDestination(tester, 'Agenda e oferta', 'Especialidades');
    expect(find.byKey(const Key('new-specialty-button')), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-specialty-button')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Nova especialidade')),
        findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-specialty-button')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome da especialidade.'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('specialty-name-field')), 'Pediatria');
    await tester.tap(find.byKey(const Key('save-specialty-button')));
    await tester.pumpAndSettle();
    expect(find.text('Especialidade criada com sucesso.'), findsOneWidget);
    expect(find.text('Pediatria'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('specialty-search-field')), 'pedia');
    await tester.pumpAndSettle();
    expect(find.text('Pediatria'), findsOneWidget);
    expect(find.text('Clínica Geral'), findsNothing);
    await tester.enterText(find.byKey(const Key('specialty-search-field')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-specialty-2')));
    await tester.pumpAndSettle();
    expect(find.text('Editar especialidade'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('specialty-name-field')))
            .controller!
            .text,
        'Pediatria');
    await tester.enterText(
        find.byKey(const Key('specialty-name-field')), 'Pediatria Infantil');
    await tester.tap(find.byKey(const Key('save-specialty-button')));
    await tester.pumpAndSettle();
    expect(find.text('Pediatria Infantil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formulario de especialidade exibe erro retornado pela API',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeSpecialtyManagementApi();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: api)));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Agenda e oferta', 'Especialidades');
    await tester.ensureVisible(find.byKey(const Key('new-specialty-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-specialty-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('specialty-name-field')), 'clínica geral');
    await tester.tap(find.byKey(const Key('save-specialty-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('specialty-form-error')), findsOneWidget);
    expect(find.text('Especialidade já cadastrada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audit_status_is_not_color_only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminContentApi())));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Governança', 'Histórico');
    expect(find.text('Registrado'), findsOneWidget);
    expect(find.text('usuario ativado'), findsOneWidget);
    expect(find.text('Paciente Fictícia • pcd'), findsOneWidget);
    expect(
        find.textContaining('Responsável: Recepção Fictícia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audit_metadata_is_16px_and_wraps_below_on_compact',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminContentApi())));
    await tester.pumpAndSettle();
    await selectAdminDestination(tester, 'Governança', 'Histórico');

    final registered = tester.widget<Text>(find.text('Registrado'));
    final date = tester.widget<Text>(find.text('2026-10-07 14:30'));
    expect(registered.style?.fontSize, 16);
    expect(date.style?.fontSize, 16);
    expect(find.byKey(const Key('audit-metadata')), findsOneWidget);

    accessibility.setFontScale(1.3);
    await tester.binding.setSurfaceSize(const Size(360, 780));
    await tester
        .pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminContentApi())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Histórico e auditoria'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Registrado'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('audit-metadata')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('audit-metadata'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('audit-content'))).dy),
    );
  });

  testWidgets('painel administrativo mostra resumo real e menu responsivo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsOneWidget);
    expect(find.text('Consultas agendadas'), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('painel administrativo suporta A+ e alto contraste no celular',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAdminApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferências de acessibilidade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A+'));
    await tester.tap(find.text('Alto contraste'));
    await tester.pumpAndSettle();
    expect(accessibility.fontSizeScale, greaterThan(1));
    expect(accessibility.highContrast, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('direcionamento reconhece os cinco perfis', () {
    ApiService.session =
        const Session('t', 'Paciente Fictício', 'paciente', []);
    expect(homeForRole(), isA<PatientDashboard>());
    ApiService.session = const Session('t', 'Admin Fictício', 'admin', []);
    expect(homeForRole(), isA<AdminDashboard>());
    ApiService.session =
        const Session('t', 'Recepção Fictícia', 'recepcao', []);
    expect(homeForRole(), isA<StaffDashboard>());
    ApiService.session =
        const Session('t', 'Enfermagem Fictícia', 'enfermagem', []);
    expect(homeForRole(), isA<StaffDashboard>());
    ApiService.session = const Session('t', 'Médico Fictício', 'medico', []);
    expect(homeForRole(), isA<MedicalDashboard>());
  });

  testWidgets('ver detalhes abre modal e mantém o painel aberto',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: FakeAgendaApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda do dia'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppStatusBadge), findsOneWidget);
    await tester.tap(find.text('Ver detalhes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Detalhes da consulta'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Administração'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
