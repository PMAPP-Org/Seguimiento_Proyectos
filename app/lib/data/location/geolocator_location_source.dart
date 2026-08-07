// Implementación real de `LocationSource` sobre el paquete `geolocator`.
// Sin test unitario propio (envoltorio delgado de un plugin de plataforma,
// no probable con `flutter test` sin un dispositivo/emulador real) — mismo
// criterio que `SecureTokenStore` (`core/auth/token_store.dart`), que
// tampoco tiene test propio y se prueba a través de un fake en el dominio
// que sí lo consume (aquí, `CaptureScreen`).
import 'package:geolocator/geolocator.dart';

import '../../core/location/location_source.dart';

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<LocationFix?> getCurrentFix() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LocationFix(
      lat: position.latitude,
      lon: position.longitude,
      accuracyM: position.accuracy,
      altitudeM: position.altitude,
    );
  }
}
