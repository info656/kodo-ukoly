import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zest/kodo/store.dart';

class KodoSessionStorage extends LocalStorage {
  final storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const key = 'kodo-tasks.supabase-session';
  @override
  Future<void> initialize() async {
    const probe = 'kodo-tasks.storage-check';
    await storage.write(key: probe, value: 'ok');
    if (await storage.read(key: probe) != 'ok') {
      throw StateError('Klíčenka není dostupná.');
    }
    await storage.delete(key: probe);
  }

  @override
  Future<bool> hasAccessToken() async => await storage.containsKey(key: key);
  @override
  Future<String?> accessToken() => storage.read(key: key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => storage.delete(key: key);
}

Future<void> initializeKodoSession() async {
  await Supabase.initialize(
    url: const String.fromEnvironment('KODO_SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('KODO_SUPABASE_KEY'),
    authOptions: FlutterAuthClientOptions(
      localStorage: KodoSessionStorage(),
      detectSessionInUri: false,
    ),
  );
}

/// Authentication is a gate only; the signed-in app is the unchanged Zest UI.
class KodoSessionGate extends StatefulWidget {
  final Widget child;
  const KodoSessionGate({super.key, required this.child});
  @override
  State<KodoSessionGate> createState() => _KodoSessionGateState();
}

class _KodoSessionGateState extends State<KodoSessionGate>
    with WidgetsBindingObserver {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  Timer? timer;
  StreamSubscription<AuthState>? auth;
  bool busy = false, loaded = false;
  String? error, factor;
  SupabaseClient get api => Supabase.instance.client;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth = api.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        KodoStore.instance.clear();
        if (mounted) setState(() => loaded = false);
      }
    });
    connect();
  }

  @override
  void dispose() {
    timer?.cancel();
    auth?.cancel();
    email.dispose();
    password.dispose();
    code.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && loaded) {
      KodoStore.instance.refresh().catchError((Object _) {});
    }
  }

  Future<void> connect() async {
    if (api.auth.currentSession == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final aal = api.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal.currentLevel != AuthenticatorAssuranceLevels.aal2 &&
          aal.nextLevel == AuthenticatorAssuranceLevels.aal2) {
        final factors = await api.auth.mfa.listFactors();
        factor = factors.totp.first.id;
        return;
      }
      await KodoStore.instance.refresh();
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 15), (_) {
        KodoStore.instance.refresh().catchError((Object _) {});
      });
      if (mounted) setState(() => loaded = true);
    } catch (e) {
      if (mounted) setState(() => error = readableKodoError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (factor != null) {
        await api.auth.mfa.challengeAndVerify(
          factorId: factor!,
          code: code.text.trim(),
        );
        factor = null;
        code.clear();
      } else {
        await api.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        password.clear();
      }
      await connect();
    } catch (e) {
      if (mounted) setState(() => error = readableKodoError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loaded) return widget.child;
    final signed = api.auth.currentSession != null;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kodo Úkoly',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                if (factor != null)
                  TextField(
                    controller: code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kód z ověřovací aplikace',
                    ),
                    onSubmitted: (_) => login(),
                  )
                else if (!signed) ...[
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail portálu Kodo',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Heslo'),
                    onSubmitted: (_) => login(),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy
                      ? null
                      : signed && factor == null
                      ? connect
                      : login,
                  child: Text(
                    busy
                        ? 'Načítám…'
                        : factor != null
                        ? 'Ověřit'
                        : signed
                        ? 'Načíst úkoly'
                        : 'Přihlásit se',
                  ),
                ),
                if (signed)
                  TextButton(
                    onPressed: busy ? null : () => api.auth.signOut(),
                    child: const Text('Odhlásit se'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String readableKodoError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  return 'Spojení se nepodařilo. Zkontrolujte internet a zkuste to znovu.';
}
