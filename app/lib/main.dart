import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'alerts.dart';
import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'personnel_page.dart';
import 'session.dart';
import 'theme.dart';

export 'theme.dart';

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:5080');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alerts.init();
  runApp(const EcoPulseApp());
}

class EcoPulseApp extends StatefulWidget {
  const EcoPulseApp({super.key});

  @override
  State<EcoPulseApp> createState() => _EcoPulseAppState();
}

class _EcoPulseAppState extends State<EcoPulseApp> {
  final Session session = Session();
  late final ApiClient api = ApiClient(baseUrl: apiBase, session: session);
  late final GoRouter router = GoRouter(
    initialLocation: '/login',
    refreshListenable: session,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      if (!session.signedIn) {
        return loggingIn ? null : '/login';
      }

      final home = session.role == 'manager' ? '/manager' : '/operator';
      if (loggingIn) {
        return home;
      }
      if (state.matchedLocation.startsWith('/manager') && session.role != 'manager') {
        return '/operator';
      }
      if (state.matchedLocation == '/operator' && session.role != 'operator') {
        return '/manager';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/operator', builder: (context, state) => const OperatorPage()),
      GoRoute(
        path: '/manager',
        builder: (context, state) => const ManagerPage(),
        routes: [
          GoRoute(path: 'personnel', builder: (context, state) => const PersonnelPage()),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: session,
      api: api,
      child: MaterialApp.router(
        title: 'EcoPulse OSB',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: router,
      ),
    );
  }
}
