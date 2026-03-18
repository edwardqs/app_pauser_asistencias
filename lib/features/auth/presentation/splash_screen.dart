import 'package:app_asistencias_pauser/core/services/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Anillos de pulso que se expanden desde el icono
  late AnimationController _ringController;
  late Animation<double> _ringAnim;

  // Puntos de carga que pulsan en loop
  late AnimationController _dotsController;
  late Animation<double> _dotsAnim;

  @override
  void initState() {
    super.initState();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _ringAnim = CurvedAnimation(parent: _ringController, curve: Curves.easeOut);

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _dotsAnim = CurvedAnimation(parent: _dotsController, curve: Curves.easeInOut);

    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      final isAuth = ref.read(authNotifierProvider).isAuthenticated;
      context.go(isAuth ? '/home' : '/login');
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  Widget _buildRing(double baseSize, double offset, double maxOpacity) {
    return AnimatedBuilder(
      animation: _ringAnim,
      builder: (_, __) {
        // Cada anillo arranca desfasado usando offset (0.0 – 1.0)
        final progress = (_ringAnim.value + offset) % 1.0;
        final size = baseSize + progress * 90;
        final opacity = maxOpacity * (1.0 - progress);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF60A5FA).withValues(alpha: opacity),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _dotsAnim,
      builder: (_, __) {
        // Cada punto tiene un desfase de fase para el efecto wave
        final phase = (index / 3.0);
        final t = ((_dotsAnim.value + phase) % 1.0);
        final scale = 0.5 + t * 0.5;
        final opacity = 0.4 + t * 0.6;
        return Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: opacity),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628), // Azul muy oscuro
              Color(0xFF0D2151), // Navy profundo
              Color(0xFF1A3A8C), // Azul corporativo oscuro
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Círculos decorativos de fondo ──────────────────────────
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              top: 180,
              left: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.07),
                ),
              ),
            ),

            // ── Contenido central ──────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Anillos + Icono
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Tres anillos desfasados
                        _buildRing(130, 0.0, 0.35),
                        _buildRing(130, 0.33, 0.25),
                        _buildRing(130, 0.66, 0.15),

                        // Icono con fondo blanco circular
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Image.asset(
                            'assets/images/icono_pauser.png',
                            fit: BoxFit.contain,
                          ),
                        )
                            .animate()
                            .scale(
                              begin: const Offset(0.0, 0.0),
                              end: const Offset(1.0, 1.0),
                              duration: 700.ms,
                              delay: 150.ms,
                              curve: Curves.elasticOut,
                            )
                            .fadeIn(duration: 400.ms, delay: 150.ms),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Nombre de la app
                  const Text(
                    'CoreTime',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3.0,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.4,
                        end: 0,
                        delay: 700.ms,
                        duration: 500.ms,
                        curve: Curves.easeOut,
                      ),

                  const SizedBox(height: 10),

                  // Subtítulo
                  Text(
                    'Gestión de Asistencias',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 15,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 950.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.4,
                        end: 0,
                        delay: 950.ms,
                        duration: 500.ms,
                        curve: Curves.easeOut,
                      ),

                  const SizedBox(height: 10),

                  // Línea decorativa
                  Container(
                    width: 50,
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 1100.ms, duration: 400.ms)
                      .scaleX(begin: 0, end: 1, delay: 1100.ms, duration: 400.ms),
                ],
              ),
            ),

            // ── Indicador de carga inferior ────────────────────────────
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Tres puntos wave
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, _buildDot),
                  )
                      .animate()
                      .fadeIn(delay: 1400.ms, duration: 400.ms),

                  const SizedBox(height: 18),

                  Text(
                    'PAUSER DISTRIBUCIONES',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 11,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ).animate().fadeIn(delay: 1600.ms, duration: 500.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
