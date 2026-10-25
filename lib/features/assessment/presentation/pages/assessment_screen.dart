import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../dashboard/presentation/pages/Dashboard_Screen.dart' show LiveSensorService;
import '../../data/assessment_adapters.dart';
import '../../data/firestore_assessment_store.dart';
import '../../domain/model/assessment_ui_config.dart';
import '../../domain/repo/assessment_ports.dart';
import '../components/environment_panel.dart';
import 'model_info_screen.dart';

/// Farmer-facing assessments screen. Everything here is read-only advice; sprinkler
/// controls stay on the dashboard and are not touched.
class AssessmentScreen extends StatefulWidget {
  final AssessmentApi api;
  final AssessmentStore? store;
  final RuleConfigCache? cache;
  final RoleChecker? roles;
  final AssessmentUiConfig? ui;
  final ValueListenable<Map<String, dynamic>?>? liveData;
  final String? Function()? userId;
  final DateTime Function() clock;

  AssessmentScreen({
    super.key,
    AssessmentApi? api,
    this.store,
    this.cache,
    this.roles,
    this.ui,
    this.liveData,
    this.userId,
    DateTime Function()? clock,
  })  : api = api ?? const MlAssessmentApi(),
        clock = clock ?? DateTime.now;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  AssessmentUiConfig? _ui;
  RoleChecker? _roles;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    if (widget.liveData == null) LiveSensorService.start(); // guarded; same feed as the dashboard
    _ui = widget.ui;
    if (_ui == null) {
      AssessmentUiConfig.load().then((c) {
        if (mounted) setState(() => _ui = c);
        _checkRole();
      });
    } else {
      _checkRole();
    }
  }

  void _checkRole() {
    _roles = widget.roles ?? FirebaseRoleChecker(_ui!.adminClaim, _ui!.adminValue);
    _roles!.isAdmin().then((v) {
      if (mounted) setState(() => _isAdmin = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ui = _ui;
    if (ui == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(ui.t('sections', 'screen_title')),
        actions: [
          if (_isAdmin)
            IconButton(
              key: const Key('open-model-info'),
              tooltip: ui.t('sections', 'model_info'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ModelInfoScreen(api: widget.api, roles: _roles!, ui: ui)),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: EnvironmentPanel(
          liveData: widget.liveData ?? LiveSensorService.latestData,
          api: widget.api,
          store: widget.store ?? (widget.liveData == null ? FirestoreAssessmentStore() : null),
          cache: widget.cache ?? PrefsRuleConfigCache(),
          ui: ui,
          userId: widget.userId ?? () => FirebaseAuth.instance.currentUser?.uid,
          clock: widget.clock,
        ),
      ),
    );
  }
}
