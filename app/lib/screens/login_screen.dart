import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  Future<void> _handleAuth() async {
    setState(() { _loading = true; _error = null; });

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'display_name': _nameController.text.trim()},
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      }
    } on AuthException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CustomPaint(painter: _CubeLogoPainter(color: theme.colorScheme.primary)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'StockAI',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin ? 'Sign in to continue' : 'Create your account',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    if (!_isLogin) ...[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                      ),

                    if (_error != null) const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _handleAuth,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isLogin ? 'Sign In' : 'Create Account'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: () => setState(() { _isLogin = !_isLogin; _error = null; }),
                      child: Text(_isLogin ? "Don't have an account? Sign up" : 'Already have an account? Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CubeLogoPainter extends CustomPainter {
  final Color color;
  const _CubeLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.06
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Hexagon outline (top/bottom/left/right vertices of a cube projection)
    final pts = [
      Offset(w * 0.5, h * 0.05),  // top
      Offset(w * 0.95, h * 0.28), // top-right
      Offset(w * 0.95, h * 0.72), // bottom-right
      Offset(w * 0.5, h * 0.95),  // bottom
      Offset(w * 0.05, h * 0.72), // bottom-left
      Offset(w * 0.05, h * 0.28), // top-left
    ];

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) { path.lineTo(p.dx, p.dy); }
    path.close();
    canvas.drawPath(path, paint);

    // Center point
    final center = Offset(w * 0.5, h * 0.5);

    // Three inner lines from center to alternating vertices (top, bottom-right, bottom-left)
    canvas.drawLine(pts[0], center, paint);
    canvas.drawLine(pts[2], center, paint);
    canvas.drawLine(pts[4], center, paint);
  }

  @override
  bool shouldRepaint(_CubeLogoPainter old) => old.color != color;
}
