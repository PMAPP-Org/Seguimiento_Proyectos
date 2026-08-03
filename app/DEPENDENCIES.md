# Presupuesto de dependencias — VisitaCampo (app/)

Doc 08 ADR-001 ("Negativas"): la dependencia de la salud del proyecto Flutter
y de paquetes de terceros se mitiga con un **presupuesto de dependencias**.
Toda dependencia nueva añadida a `pubspec.yaml` requiere una entrada en este
archivo que la justifique, siguiendo la regla de ADR-001: **plugin oficial de
flutter.dev/Google, o >1k likes en pub.dev con mantenimiento activo**. Si no
cumple ninguna de las dos, la justificación tiene que decir explícitamente
por qué se acepta el riesgo de todas formas.

Regla operativa: un PR que añada una dependencia a `dependencies:` o
`dev_dependencies:` sin una entrada correspondiente aquí no está completo,
mismo principio que "ningún paso se considera cerrado sin su CI en verde"
(`CONTRIBUTING.md`).

## Runtime (`dependencies:`)

| Paquete | Por qué | Cumple la regla |
|---|---|---|
| `flutter_riverpod` | Gestión de estado — decisión de ADR-001 ("Riverpod" citado explícitamente en la arquitectura de capas). Providers escritos a mano (`Provider`/`NotifierProvider`), sin `riverpod_generator`: ver nota abajo. | Paquete oficial del ecosistema Riverpod, >1k likes, mantenimiento activo. |
| `freezed_annotation` | Anotaciones para tipos sellados (`@freezed`) — la mitad estática de RD-02/RD-03: ningún modelo de dominio o de red se representa con `Map<String, dynamic>` suelto. | >1k likes, mantenimiento activo (paquete hermano de `freezed`, ver dev_dependencies). |
| `json_annotation` | Anotaciones para (de)serialización JSON generada — necesario para que los modelos `freezed` tengan `fromJson`/`toJson` sin escribirlo a mano (superficie de bug si se hiciera manualmente, justo lo que RD-02/RD-03 quieren evitar). | >1k likes, mantenimiento activo. |
| `dio` | Cliente HTTP para `/v1/*` (Paso 13 en adelante). Elegido sobre `http` (paquete `dart.dev`) porque el `SyncEngine` (Paso 12) necesita interceptores para refresh automático de JWT (`sync/api.py` Paso 7) e integración futura con `TrustStore`/pinning SPKI (Paso 16, RD-01) vía `HttpClientAdapter` — el paquete `http` no expone ese punto de extensión sin envolverlo a mano, que sería reinventar lo que `dio` ya da. | >1k likes, mantenimiento muy activo. |
| `uuid` | Generación de `op_uuid` UUIDv7 en el dispositivo (Paso 12, idempotencia real del outbox — doc 08 §4.3). | >1k likes, mantenimiento activo. |
| `cupertino_icons` | Generado por `flutter create`, íconos iOS-style. | Paquete oficial de flutter.dev. |
| `drift` | Almacén local (Paso 11, ADR-002): SQL tipado, streams reactivos, transacciones multi-tabla explícitas — la decisión ya cerrada en ADR-002 frente a `sqflite`/Realm/Isar. | >1k likes, mantenimiento muy activo (paquete de referencia para SQLite en Dart). |
| `flutter_secure_storage` | Guarda la clave de cifrado de SQLCipher (`EncryptionKeyStore`, Paso 11) en Keychain/Keystore — el mismo mecanismo que Paso 13/16 reutilizará para tokens de sesión (ADR-002/ADR-008). | Paquete de referencia del ecosistema, >1k likes, mantenimiento activo. |
| `path_provider` | Ubica el directorio de datos de la app donde vive el archivo `.sqlite` (`AppDatabase`, Paso 11). | Paquete oficial de flutter.dev. |
| `path` | Construcción de rutas de archivo independiente de plataforma. | Paquete oficial de dart.dev. |
| `meta` | `@visibleForTesting` en `AppDatabase.forTesting` (Paso 11) — documenta en el propio tipo que ese factory nunca debe usarse fuera de tests. | Paquete oficial de dart.dev. |

**Nota sobre `sqlcipher_flutter_libs`/`sqlite3_flutter_libs`** (Paso 11): ADR-002
nombra literalmente `sqlcipher_flutter_libs`, pero ese paquete está
descontinuado desde la versión `0.7.0+eol` ("Not used anymore, update to
version 3.x of package:sqlite3 instead") — lo mismo aplica a
`sqlite3_flutter_libs`. Desde `sqlite3` v3.x el soporte de SQLCipher se
activa con el sistema de *hooks*/native-assets de Dart
(`pubspec.yaml: hooks.user_defines.sqlite3.source: sqlcipher`), verificado
funcionando en este paso (`test/data/local/encryption_smoke_test.dart`:
un archivo escrito con la clave real es ilegible sin ella). La decisión de
ADR-002 (SQLCipher) no cambia — solo el mecanismo de empaquetado.

**Nota sobre `riverpod_generator`**: se evaluó y se descartó en este paso. Su
versión más reciente (que requiere `riverpod_annotation ^4.0.6`, arrastrado
por `flutter_riverpod ^3.4.2`) depende transitivamente del sistema de
*macros* experimental de Dart (`freezed >=3.0.0` con macros), que **no**
resuelve junto con la cadena de dependencias de `freezed`/`json_serializable`
en este SDK (Dart 3.12 estable): `flutter pub add` reporta un conflicto de
versiones irresoluble entre `riverpod_generator`, `freezed` y `custom_lint`.
Los providers de Riverpod se escriben a mano (`Provider`, `NotifierProvider`)
en vez de con `@riverpod` — sigue siendo un patrón de primera clase del
propio paquete, no una alternativa de segunda categoría. Revisar en un paso
posterior si el ecosistema converge (Riverpod/freezed/analyzer con versiones
estables mutuamente compatibles) antes de reconsiderar `riverpod_generator`.

## Desarrollo (`dev_dependencies:`)

| Paquete | Por qué | Cumple la regla |
|---|---|---|
| `flutter_lints` | Generado por `flutter create`; base de `analysis_options.yaml`, extendida con reglas más estrictas en este mismo paso. | Paquete oficial de flutter.dev. |
| `build_runner` | Motor de codegen que ejecuta `freezed`/`json_serializable`. | Paquete oficial de dart.dev. |
| `freezed` | Generador de código de `@freezed` (tipos sellados, `copyWith`, unions — RD-02/RD-03). Anclado a una versión `3.2.6-dev.1` porque la serie estable 3.x más reciente en el momento de este paso también resolvía con macros; el `dev` elegido genera código con el backend `build_runner` clásico (verificado: `dart run build_runner build` produjo `visit.freezed.dart`/`visit.g.dart` sin usar macros). Revisar cuando `freezed` publique una serie 3.x estable sin ese requisito. | >1k likes, mantenimiento muy activo (paquete de referencia para tipos sellados en Dart). |
| `json_serializable` | Generador de `fromJson`/`toJson` para los modelos `freezed`/`json_annotation`. | >1k likes, mantenimiento activo. |
| `drift_dev` | Generador de código del esquema Drift (Paso 11): produce `database.g.dart` a partir de `tables.dart`/`database.dart`. | Paquete hermano oficial de `drift`, mantenimiento muy activo. |
| `sqlite3` | Uso directo (no vía Drift) solo en `test/data/local/encryption_smoke_test.dart`, para abrir el archivo `.sqlite` en crudo y confirmar que es ilegible sin la clave — es la misma dependencia transitiva de `drift`, promovida a directa porque el test la importa explícitamente. | Paquete oficial del mismo mantenedor de `drift`, mantenimiento muy activo. |
| `test` | API de aserciones (`test`/`expect`) usada en `encryption_smoke_test.dart`, que no depende de widgets y por eso no usa `flutter_test`. | Paquete oficial de dart.dev. |

## Cómo añadir una dependencia nueva

1. `flutter pub add <paquete>` (o `--dev`).
2. Añadir una fila a la tabla correspondiente de este archivo: qué resuelve,
   por qué esta y no otra, y si cumple la regla de ADR-001.
3. Si `flutter pub add` reporta un conflicto de versiones irresoluble (como
   pasó con `riverpod_generator` en este paso), documentarlo igual —la
   ausencia de una dependencia también es una decisión que vale la pena
   dejar por escrito para que el próximo paso no la reintente a ciegas.
