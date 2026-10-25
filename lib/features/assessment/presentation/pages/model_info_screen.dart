import 'package:flutter/material.dart';

import '../../../../core/services/ml_service.dart' show MlServiceException;
import '../../domain/model/assessment_ui_config.dart';
import '../../domain/repo/assessment_ports.dart';

/// Read-only view of the active forecast model for admins. There are deliberately no
/// approve / activate / rollback buttons: those actions exist only on the server
/// (POST /models/...), which checks the admin claim itself.
class ModelInfoScreen extends StatelessWidget {
  final AssessmentApi api;
  final RoleChecker roles;
  final AssessmentUiConfig ui;

  const ModelInfoScreen({super.key, required this.api, required this.roles, required this.ui});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(ui.t('sections', 'model_info'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<bool>(
          future: roles.isAdmin(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data != true) {
              return Center(child: Text(ui.t('states', 'admin_required'), key: const Key('admin-required')));
            }
            return FutureBuilder<Map<String, dynamic>>(
              future: api.activeModel(),
              builder: (context, m) {
                if (m.hasError) {
                  final e = m.error;
                  final denied = e is MlServiceException && (e.statusCode == 401 || e.statusCode == 403);
                  return Center(
                      child: Text(ui.t('states', denied ? 'admin_required' : 'api_unavailable'),
                          key: const Key('model-info-error')));
                }
                if (!m.hasData) return const Center(child: CircularProgressIndicator());
                final d = m.data!;
                final model = d['model'] as Map<String, dynamic>?;
                return ListView(key: const Key('model-info'), children: [
                  _row(ui.t('fields', 'model_version'), d['model_version']?.toString() ?? ui.t('fields', 'no_model')),
                  _row(ui.t('fields', 'status'), model?['status']?.toString() ?? '–'),
                  _row(ui.t('fields', 'dataset'), model?['dataset_version']?.toString() ?? '–'),
                  _row(ui.t('fields', 'metrics'), (model?['metrics'] as Map?)?['mae']?.toString() ?? '–'),
                  if (d['load_error'] != null) _row(ui.t('fields', 'load_error'), d['load_error'].toString()),
                ]);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _row(String k, String v) => ListTile(dense: true, title: Text(k), subtitle: Text(v));
}
