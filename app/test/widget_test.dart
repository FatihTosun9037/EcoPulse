import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecopulse/api.dart';
import 'package:ecopulse/home_page.dart';
import 'package:ecopulse/main.dart';
import 'package:ecopulse/personnel_page.dart';
import 'package:ecopulse/session.dart';

void main() {
  testWidgets('giriş ekranı açılır', (tester) async {
    await tester.pumpWidget(const EcoPulseApp());
    expect(find.text('EcoPulse OSB'), findsOneWidget);
    expect(find.text('Saha olarak gir'), findsOneWidget);
    expect(find.text('Yönetici olarak gir'), findsOneWidget);
  });

  testWidgets('telefonda yönetici personel atamalarını açıp kullanabilir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = Session()
      ..signIn(
        const LoginResult(
          accessToken: 'test-token',
          role: 'manager',
          displayName: 'Yönetici',
        ),
      );
    final api = _PersonnelTestApi(session);
    final router = GoRouter(
      initialLocation: '/manager',
      routes: [
        GoRoute(
          path: '/manager',
          builder: (context, state) => const ManagerPage(),
          routes: [
            GoRoute(
              path: 'personnel',
              builder: (context, state) => const PersonnelPage(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      AppScope(
        session: session,
        api: api,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.badge_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Kerem Aydın'), findsWidgets);
    expect(find.text('ATANAN MAKİNELER'), findsOneWidget);
    expect(find.text('UYUMLU MAKİNELER'), findsOneWidget);
    expect(find.text('UYUMSUZ MAKİNELER'), findsOneWidget);

    final assignButton = find.text('Seçilen makineyi ata');
    await tester.ensureVisible(assignButton);
    await tester.tap(assignButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.assignedMachineIds, [2]);

    final mismatchButton = find.text('Yine de ata');
    await tester.ensureVisible(mismatchButton);
    await tester.tap(mismatchButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.assignedMachineIds, [2, 3]);

    final unassignButton = find.text('Atamayı kaldır');
    await tester.ensureVisible(unassignButton);
    await tester.tap(unassignButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.unassignedMachineIds, [1]);
  });
}

class _PersonnelTestApi extends ApiClient {
  _PersonnelTestApi(Session session)
    : super(baseUrl: 'http://localhost', session: session);

  final List<int> assignedMachineIds = [];
  final List<int> unassignedMachineIds = [];

  @override
  Future<Dashboard> dashboard() async => const Dashboard(
    machineCount: 0,
    activeAlarms: 0,
    openWorkOrders: 0,
    verifyingWorkOrders: 0,
    totalPowerText: '0 kW',
    activeLossText: '0 TL',
    verifiedSavingsText: '0 TL',
    verifiedCo2Text: '0 kg',
    machines: [],
    alarms: [],
  );

  @override
  Future<List<Notice>> notifications() async => const [];

  @override
  Future<List<Personnel>> personnel() async => const [
    Personnel(
      id: 1,
      fullName: 'Kerem Aydın',
      expertise: 'ELEKTRIK',
      expertiseLabel: 'Elektrik',
    ),
  ];

  @override
  Future<List<Machine>> machines() async => const [
    Machine(
      id: 1,
      name: 'Atanmış makine',
      location: 'Atölye',
      meta: '',
      faultActive: false,
      voltageText: '',
      currentText: '',
      temperatureText: '',
      powerText: '',
      voltageSeries: [],
      currentSeries: [],
      temperatureSeries: [],
      domain: 'ELEKTRIK',
      domainLabel: 'Elektrik',
      personnelId: 1,
      assigneeName: 'Kerem Aydın',
    ),
    Machine(
      id: 2,
      name: 'Uyumlu makine',
      location: 'Atölye',
      meta: '',
      faultActive: false,
      voltageText: '',
      currentText: '',
      temperatureText: '',
      powerText: '',
      voltageSeries: [],
      currentSeries: [],
      temperatureSeries: [],
      domain: 'ELEKTRIK',
      domainLabel: 'Elektrik',
    ),
    Machine(
      id: 3,
      name: 'Uyumsuz makine',
      location: 'Atölye',
      meta: '',
      faultActive: false,
      voltageText: '',
      currentText: '',
      temperatureText: '',
      powerText: '',
      voltageSeries: [],
      currentSeries: [],
      temperatureSeries: [],
      domain: 'ISI',
      domainLabel: 'Isı',
    ),
  ];

  @override
  Future<AssignmentResult> assignMachine(int personnelId, int machineId) async {
    assignedMachineIds.add(machineId);
    return const AssignmentResult(
      saved: true,
      expertiseMismatch: false,
      message: 'Atama kaydedildi.',
    );
  }

  @override
  Future<AssignmentResult> unassignMachine(int machineId) async {
    unassignedMachineIds.add(machineId);
    return const AssignmentResult(
      saved: true,
      expertiseMismatch: false,
      message: 'Atama kaldırıldı.',
    );
  }

  @override
  Future<void> ack(int id) async {}
}
