import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2000), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await loadThemeFromSupabase();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => session != null ? const ChatScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CustomPaint(painter: _SplashCubePainter(color: scheme.primary)),
                ),
                const SizedBox(height: 20),
                Text(
                  'StockAI',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The database that builds itself.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashCubePainter extends CustomPainter {
  final Color color;
  const _SplashCubePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.055
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final pts = [
      Offset(w * 0.5, h * 0.05),
      Offset(w * 0.95, h * 0.28),
      Offset(w * 0.95, h * 0.72),
      Offset(w * 0.5, h * 0.95),
      Offset(w * 0.05, h * 0.72),
      Offset(w * 0.05, h * 0.28),
    ];

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
    path.close();
    canvas.drawPath(path, paint);

    final center = Offset(w * 0.5, h * 0.5);
    canvas.drawLine(pts[0], center, paint);
    canvas.drawLine(pts[2], center, paint);
    canvas.drawLine(pts[4], center, paint);
  }

  @override
  bool shouldRepaint(_SplashCubePainter old) => old.color != color;
}
