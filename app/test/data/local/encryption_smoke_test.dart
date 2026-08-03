// Paso 11, comando de verificación del brief: "abrir el archivo .sqlite con
// una herramienta estándar sin la clave debe fallar/mostrar contenido
// ilegible". Verificado: el hook `sqlite3: source: sqlcipher` (pubspec.yaml)
// sí compila/enlaza un sqlite3 con soporte SQLCipher real en este host
// (Windows) — un archivo escrito con `createEncryptedExecutor` es ilegible
// para un `sqlite3.open()` plano sin la clave, confirmado por este test.
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';
import 'package:visitacampo/data/local/database.dart';

void main() {
  test('un archivo escrito con createEncryptedExecutor no se puede leer sin la clave', () async {
    final dir = await Directory.systemTemp.createTemp('visitacampo_enc_test');
    final file = File('${dir.path}/test.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    final db = AppDatabase.forTesting(
      createEncryptedExecutor(file: file, encryptionKey: 'clave-de-prueba-no-real'),
    );
    await db.into(db.visits).insert(
      VisitsCompanion.insert(
        id: 'visit-1',
        orgId: 'org-1',
        version: 1,
        templateVersionId: 'template-1',
        answersJson: '{}',
        capturedAt: DateTime.utc(2026, 1, 1),
        deviceId: 'device-1',
        createdBy: 'user-1',
      ),
    );
    await db.close();

    expect(file.existsSync(), isTrue);

    // Sin PRAGMA key: si el archivo es SQLCipher real, esto debe fallar al
    // intentar leer el esquema (el header no es el de un SQLite plano).
    final raw = sqlite3.sqlite3.open(file.path);
    addTearDown(raw.close);

    expect(
      () => raw.select('SELECT name FROM sqlite_master WHERE type = ?', ['table']),
      throwsA(anything),
      reason: 'un archivo realmente cifrado no debe ser legible sin la clave',
    );
  });
}
