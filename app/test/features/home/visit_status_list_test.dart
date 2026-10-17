// Estado de sincronización visible al agente (Paso 22, tarea 6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/data/local/visit_status_repository.dart';
import 'package:visitacampo/features/home/visit_status_list.dart';

import '../../support/test_app.dart';

VisitSummary summary(String id, VisitSyncStatus status, {int attachments = 0, int pending = 0}) => VisitSummary(
  id: id,
  templateName: 'Inspección $id',
  capturedAt: DateTime.utc(2026, 10, 17, 15, 30),
  status: status,
  attachments: attachments,
  pendingUploads: pending,
);

void main() {
  testWidgets('cada visita muestra su estado y los adjuntos por subir', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: VisitStatusList(
            visits: [
              summary('a', VisitSyncStatus.pending, attachments: 10, pending: 10),
              summary('b', VisitSyncStatus.synced, attachments: 2, pending: 1),
              summary('c', VisitSyncStatus.rejected),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Sincronizada'), findsOneWidget);
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.textContaining('10 adjuntos · 10 por subir'), findsOneWidget);
    expect(find.textContaining('2 adjuntos · 1 por subir'), findsOneWidget, reason: 'sincronizada con fotos pendientes');
  });

  testWidgets('sin visitas lo dice', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: VisitStatusList(visits: []))));
    expect(find.byKey(const Key('home_no_visits')), findsOneWidget);
  });
}
