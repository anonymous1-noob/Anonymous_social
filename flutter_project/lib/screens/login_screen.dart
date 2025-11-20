import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_screen.dart';
import 'feed_screen.dart';
import 'package:lottie/lottie.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final client = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> signInWithEmail() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = res.user;
      if (user != null) {
        // Call the RPC function to update timestamps
        await client.rpc('update_user_login_timestamps');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => FeedScreen()),
          );
        }
      } else {
        setState(() {
          error = 'Invalid credentials. Please try again.';
          loading = false;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'An unexpected error occurred.';
        loading = false;
      });
    }
  }

  Future<void> signInWithGoogle() async {
    await client.auth.signInWithOAuth(OAuthProvider.google);
  }

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder for robust responsive behavior
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          // breakpoint for wide view
          const wideBreakpoint = 900.0;

          if (width <= wideBreakpoint) {
            // Mobile / narrow layout (stacked)
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: Lottie.network(
                      'https://assets2.lottiefiles.com/packages/lf20_touohxv0.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'CHEERS Social',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  _buildLoginCard(maxWidth: width * 0.95),
                ],
              ),
            );
          }

          // Desktop / wide layout
          // leftWidth = 60% of width, rightWidth = 40% of width
          final leftWidth = width * 0.60;
          final rightWidth = width - leftWidth; // so it always sums to width

          return Row(
            children: [
              // LEFT PANEL (60%)
              SizedBox(
                width: leftWidth,
                height: height,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  color: Colors.indigo.shade600,
                  child: Stack(
                    children: [
                      // faint Lottie decorative background
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.12,
                          child: Lottie.network(
                            'https://assets2.lottiefiles.com/packages/lf20_touohxv0.json',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      // content
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.bolt, color: Colors.white, size: 72),
                              SizedBox(height: 16),
                              Text(
                                'CHEERS Social',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Connect • Share • Inspire',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 20),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  'A space to share anonymous thoughts and real experiences. '
                                  'Join your college or company community and speak freely.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // small gap / gutter between panels
              const SizedBox(width: 18),

              // RIGHT PANEL (40%) — white background and centered login card
              SizedBox(
                width: rightWidth - 18, // subtract gutter
                height: height,
                child: Container(
                  color: Colors.white,
                  child: Center(
                    child: _buildLoginCard(maxWidth: rightWidth * 0.7),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Builds the login card; maxWidth controls how wide the card can grow
  Widget _buildLoginCard({required double maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth.clamp(320.0, 520.0),
      ),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 10)),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome Back',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Sign in to continue', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 18),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: loading ? null : signInWithEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Sign In'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: loading ? null : signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, color: Colors.red),
                label: const Text('Sign in with Google'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: loading ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterScreen())),
              child: const Text('Create an account'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
