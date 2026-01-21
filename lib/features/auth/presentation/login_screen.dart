import 'package:app_asistencias_pauser/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dniController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isDniFocused = false;
  bool _isPasswordFocused = false;

  @override
  void dispose() {
    _dniController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref
          .read(authControllerProvider.notifier)
          .signIn(dni: _dniController.text, password: _passwordController.text);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login Exitoso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Navigate to home
        context.go('/home');
      } else {
        // Error handling is managed by state updates in the controller, but we can check state too
        final state = ref.read(authControllerProvider);
        if (state.hasError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error.toString()),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image with Parallax-like scaling/overlay
          Positioned.fill(
            child:
                Image.asset(
                      'assets/images/imagen_pauser.jpg',
                      fit: BoxFit.cover,
                    )
                    .animate()
                    .fadeIn(duration: 800.ms)
                    .scale(
                      begin: const Offset(1.05, 1.05),
                      end: const Offset(1.0, 1.0),
                      duration: 2.seconds,
                      curve: Curves.easeOut,
                    ),
          ),
          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
          ),
          // Login Form
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                color: Colors.white.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo or Title
                        Text(
                              'Bienvenido',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E293B),
                                  ),
                              textAlign: TextAlign.center,
                            )
                            .animate()
                            .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              curve: Curves.easeOut,
                            )
                            .fadeIn(),
                        const SizedBox(height: 8),
                        Text(
                              'Ingresa tus credenciales',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            )
                            .animate()
                            .slideY(
                              begin: -0.2,
                              end: 0,
                              duration: 600.ms,
                              delay: 100.ms,
                              curve: Curves.easeOut,
                            )
                            .fadeIn(),
                        const SizedBox(height: 32),

                        // DNI Field
                        Focus(
                              onFocusChange: (hasFocus) =>
                                  setState(() => _isDniFocused = hasFocus),
                              child: TextFormField(
                                controller: _dniController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(8),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'DNI',
                                  hintText: 'Ingrese su DNI (8 dígitos)',
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                    color: _isDniFocused
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor ingrese su DNI';
                                  }
                                  if (value.length != 8) {
                                    return 'El DNI debe tener 8 dígitos';
                                  }
                                  return null;
                                },
                              ),
                            )
                            .animate()
                            .slideX(
                              begin: -0.1,
                              end: 0,
                              duration: 600.ms,
                              delay: 200.ms,
                            )
                            .fadeIn(),
                        const SizedBox(height: 20),

                        // Password Field
                        Focus(
                              onFocusChange: (hasFocus) =>
                                  setState(() => _isPasswordFocused = hasFocus),
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: !_isPasswordVisible,
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: _isPasswordFocused
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isPasswordVisible =
                                            !_isPasswordVisible;
                                      });
                                    },
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor ingrese su contraseña';
                                  }
                                  return null;
                                },
                              ),
                            )
                            .animate()
                            .slideX(
                              begin: -0.1,
                              end: 0,
                              duration: 600.ms,
                              delay: 300.ms,
                            )
                            .fadeIn(),
                        const SizedBox(height: 32),

                        // Login Button
                        SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 4,
                                  shadowColor: Theme.of(
                                    context,
                                  ).primaryColor.withValues(alpha: 0.4),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Iniciar Sesión',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            )
                            .animate()
                            .scale(
                              delay: 400.ms,
                              duration: 400.ms,
                              curve: Curves.easeOut,
                            )
                            .fadeIn(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
