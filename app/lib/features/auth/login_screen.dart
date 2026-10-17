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
import '../../l10n/l10n.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/app_page_body.dart';
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

  String _messageFor(AuthError error) {
    final l10n = context.l10n;
    return error.when(
      network: (message) => l10n.authErrorNetwork,
      invalidCredentials: () => l10n.authErrorInvalidCredentials,
      unauthorized: () => l10n.authErrorUnauthorized,
      unexpectedStatus: (statusCode, body) => l10n.authErrorUnexpectedStatus(statusCode),
      malformedResponse: (details) => l10n.authErrorMalformedResponse,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      body: AutofillGroup(
        child: AppPageBody(
          centerVertically: true,
          children: [
            Text(
              l10n.appTitle,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const AppGap.lg(),
            TextField(
              key: const Key('login_username_field'),
              controller: _usernameController,
              decoration: InputDecoration(labelText: l10n.loginUsernameLabel),
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const AppGap.sm(),
            TextField(
              key: const Key('login_password_field'),
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.loginPasswordLabel),
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isSubmitting) _submit();
              },
            ),
            const AppGap.lg(),
            AppButton(
              key: const Key('login_submit_button'),
              label: l10n.loginSubmit,
              loadingLabel: l10n.loginSubmitting,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
