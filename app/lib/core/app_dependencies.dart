// Composición de dependencias de la app (Tarea 5 del plan de despliegue del
// demo). Un único objeto en vez de un grafo fino de providers de Riverpod:
// `AuthController`/`SyncEngine` no son observables (no son `ChangeNotifier`/
// `StateNotifier`, ver sus propios archivos), así que un grafo reactivo
// alrededor de ellos no aportaría nada — la navegación de esta app es
// imperativa (`Navigator.pushReplacement` tras el resultado de `login()`).
//
// Las Tareas 6 y 7 **añaden campos a esta misma clase** (`locationSource`/
// `photoCapture` en la 6; `syncEngine`/`attachmentUploadService` en la 7) en
// vez de crear objetos de dependencias paralelos.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auth/auth_controller.dart';
import 'auth/token_store.dart';
import 'capture/photo_capture.dart';
import 'constants.dart';
import 'device/device_id_store.dart';
import 'location/location_source.dart';
import '../data/capture/image_picker_photo_capture.dart';
import '../data/http/api_client.dart';
import '../data/http/auth_interceptor.dart';
import '../data/local/database.dart';
import '../data/local/encryption_key_store.dart';
import '../data/location/geolocator_location_source.dart';

class AppDependencies {
  AppDependencies({
    required this.database,
    required this.dio,
    required this.authController,
    required this.deviceId,
    LocationSource? locationSource,
    PhotoCapture? photoCapture,
  }) : locationSource = locationSource ?? const GeolocatorLocationSource(),
       photoCapture = photoCapture ?? ImagePickerPhotoCapture();

  final AppDatabase database;
  final Dio dio;
  final AuthController authController;
  final String deviceId;
  final LocationSource locationSource;
  final PhotoCapture photoCapture;

  static Future<AppDependencies> bootstrap() async {
    const secureStorage = FlutterSecureStorage();

    final deviceIdStore = DeviceIdStore(read: secureStorage.read, write: secureStorage.write);
    final deviceId = await deviceIdStore.getOrCreateId();

    final encryptionKeyStore = EncryptionKeyStore(secureStorage);
    final encryptionKey = await encryptionKeyStore.getOrCreateKey();
    final documentsDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(documentsDir.path, 'visitacampo.db'));
    final database = AppDatabase.open(
      createEncryptedExecutor(file: dbFile, encryptionKey: encryptionKey),
    );

    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final tokenStore = SecureTokenStore(secureStorage);
    final authController = AuthController(
      transport: AuthApiClient(dio),
      tokenStore: tokenStore,
      deviceId: deviceId,
    );
    dio.interceptors.add(AuthInterceptor(dio: dio, controller: authController));

    return AppDependencies(
      database: database,
      dio: dio,
      authController: authController,
      deviceId: deviceId,
    );
  }
}
