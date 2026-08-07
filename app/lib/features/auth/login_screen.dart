// Pantalla de login (Tarea 5 del plan de despliegue del demo). Conecta la
// UI directamente con `AuthController.login()` (Paso 13, ya construido) —
// esta pantalla no valida ni decide nada, solo traduce el formulario a los
// parámetros del contrato y el `AuthResult` a un mensaje o una navegación.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_result.dart';
import '../../core/constants.dart';
import '../../core/providers.dart';
import '../home/home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final dependencies = ref.read(appDependenciesProvider);
    setState(() => _isSubmitting = true);

    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final result = await dependencies.authController.login(
      username: _usernameController.text,
      password: _passwordController.text,
      deviceInfo: DeviceInfo(
        deviceId: dependencies.deviceId,
        platform: platform,
        appVersion: kAppVersion,
      ),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    result.when(
      ok: (_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
      },
      err: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      },
    );
  }

  String _messageFor(AuthError error) => error.when(
    network: (message) => 'No se pudo conectar con el servidor.',
    invalidCredentials: () => 'Usuario o contraseña incorrectos.',
    unauthorized: () => 'Sesión no autorizada.',
    unexpectedStatus: (statusCode, body) => 'Error inesperado del servidor ($statusCode).',
    malformedResponse: (details) => 'Respuesta del servidor no reconocida.',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VisitaCampo — Iniciar sesión')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('login_username_field'),
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Usuario'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login_password_field'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('login_submit_button'),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}
