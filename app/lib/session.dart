import 'package:flutter/widgets.dart';

import 'api.dart';

class Session extends ChangeNotifier {
  final String deviceToken = 'device-${DateTime.now().microsecondsSinceEpoch}';
  String? token;
  String? role;
  String? displayName;

  bool get signedIn => token != null && role != null;

  void signIn(LoginResult result) {
    token = result.accessToken;
    role = result.role;
    displayName = result.displayName;
    notifyListeners();
  }

  void signOut() {
    if (token == null && role == null) {
      return;
    }
    token = null;
    role = null;
    displayName = null;
    notifyListeners();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({
    required this.session,
    required this.api,
    required super.child,
    super.key,
  });

  final Session session;
  final ApiClient api;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => session != oldWidget.session || api != oldWidget.api;
}
