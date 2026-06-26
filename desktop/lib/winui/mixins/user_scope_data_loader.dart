import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

mixin UserScopeDataLoader<T extends StatefulWidget> on State<T> {
  String? _lastInitializedUserId;

  bool get isUserScopeReady;

  void loadUserScopeData();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthProvider>(context);
    if (!isUserScopeReady) {
      _lastInitializedUserId = null;
      return;
    }
    final uid = auth.credentials?.userId ?? '';
    if (uid.isNotEmpty && uid != _lastInitializedUserId) {
      _lastInitializedUserId = uid;
      final capturedUid = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (capturedUid != _lastInitializedUserId) return;
        loadUserScopeData();
      });
    }
  }
}
