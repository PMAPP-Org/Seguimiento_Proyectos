// Constantes de composición de la app (Tarea 5 del plan de despliegue del
// demo). `kAppVersion` va en el `DeviceInfo` del login/registro de
// dispositivo (contrato `DeviceInfo.app_version`) — se hardcodea en vez de
// leerla con `package_info_plus` porque el valor exacto no afecta al
// criterio de éxito del demo y añadir el paquete solo para esto sería
// sobre-construcción (YAGNI). El valor lo actualiza release-please en cada
// release, junto con `pubspec.yaml` (ver `release-please-config.json`).
const String kAppVersion = '0.2.0'; // x-release-please-version

/// URL base de la API, configurable en tiempo de build/ejecución con
/// `flutter run --dart-define=VISITACAMPO_API_BASE_URL=https://tu-dominio`.
/// Por defecto apunta al Caddy local de `infra/docker-compose.override.dev.yml`
/// (HTTPS con certificado autofirmado — ver `infra/Caddyfile`).
const String kApiBaseUrl = String.fromEnvironment(
  'VISITACAMPO_API_BASE_URL',
  defaultValue: 'https://localhost',
);
