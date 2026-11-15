import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubs_saude/main.dart';
import 'package:ubs_saude/models/api_models.dart';
import 'package:ubs_saude/services/api_service.dart';

class FakeDoctorAdminApi extends ApiService {
  int doctorCreates = 0;
  String? lastSearch;

  DoctorAccount get doctor => DoctorAccount.fromJson({
        'id': 9,
        'name': 'Dr. Victor Almeida',
        'masked_cpf': '***.***.***-05',
        'role': 'medico',
        'active': true,
        'specialty': 'Clínica Geral',
      });

  @override
  Future<AdminSummary> adminSummary([DateTime? day]) async =>
      AdminSummary.fromJson({
        'scheduled': 0,
        'checked_in': 0,
        'waiting': 0,
        'in_care': 0,
        'completed': 0,
        'cancelled': 0,
        'available': 0,
        'absent': 0,
      });

  @override
  Future<List<DoctorAccount>> doctors({String? search, bool? active}) async {
    if (search != null) {
      lastSearch = search;
    }
    return [doctor];
  }

  @override
  Future<DoctorAccount> createDoctor(Map<String, dynamic> data) async {
    doctorCreates++;
    return doctor;
  }
}

void main() {
  setUp(() {
    ApiService.session =
        const Session('token', 'Administrador', 'admin', ['users:manage']);
  });
  tearDown(() => ApiService.session = null);

  testWidgets('admin_has_dedicated_doctors_section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeDoctorAdminApi();
    await tester.pumpWidget(UbsApp(home: AdminDashboard(api: api)));
    await tester.pumpAndSettle();

    final navigation = find.byType(NavigationRail);
    final navigationScroll = find
        .descendant(of: navigation, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Médicos'), 180,
        scrollable: navigationScroll);
    await tester.ensureVisible(find.text('Médicos').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Médicos').first);
    await tester.pumpAndSettle();
    expect(find.text('Há Médico ativo para atendimento'), findsOneWidget);
    expect(find.text('Dr. Victor Almeida'), findsOneWidget);
    expect(find.text('Médico • ***.***.***-05 • Clínica Geral'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('doctor-search')), '39053344705');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.lastSearch, '39053344705');

    await tester.tap(find.text('Cadastrar Médico'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Nome completo'), findsOneWidget);
    expect(find.text('CPF'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Perfil: Médico'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
