import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/campus_issue.dart';
import 'models/work_update.dart';
import 'services/firebase_issue_repository.dart';
import 'services/push_notification_service.dart';

const brand = Color(0xFF4F46E5);
const ink = Color(0xFF171A2C);
const muted = Color(0xFF73788C);
const pale = Color(0xFFF5F6FC);

String _roleLabel(String role) => switch (role) {
      'admin' => 'Authority / Admin',
      'staff' => 'Maintenance Staff',
      _ => 'Student',
    };

const _departments = [
  'Facilities',
  'Electrical',
  'Plumbing',
  'Network / IT',
  'Security',
  'Cleanliness',
];

String _defaultDepartment(String category) => switch (category) {
      'Electrical' => 'Electrical',
      'Plumbing' => 'Plumbing',
      'Internet' => 'Network / IT',
      'Safety' => 'Security',
      'Cleanliness' => 'Cleanliness',
      _ => 'Facilities',
    };

IconData _issueCategoryIcon(String category) => switch (category) {
      'Electrical' => Icons.electrical_services_outlined,
      'Plumbing' => Icons.water_drop_outlined,
      'Furniture' => Icons.chair_outlined,
      'Internet' => Icons.wifi_outlined,
      'Safety' => Icons.health_and_safety_outlined,
      'Cleanliness' => Icons.cleaning_services_outlined,
      _ => Icons.report_problem_outlined,
    };

class CampusPlusApp extends StatelessWidget {
  const CampusPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusPlus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: brand, brightness: Brightness.light),
        scaffoldBackgroundColor: pale,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
            backgroundColor: pale,
            foregroundColor: ink,
            elevation: 0,
            centerTitle: false),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE7E8F0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: brand, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE9EAF2)))),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _showApp = false;
  bool _showOnboarding = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2200), _continueFromSplash);
  }

  Future<void> _continueFromSplash() async {
    if (!mounted) return;
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        setState(() => _showApp = true);
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _showOnboarding =
            preferences.getBool('campusplus_onboarding_completed') != true;
        _showApp = !_showOnboarding;
      });
    } catch (error) {
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  Future<void> _finishOnboarding() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('campusplus_onboarding_completed', true);
      if (mounted) {
        setState(() {
          _showOnboarding = false;
          _showApp = true;
          _startupError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: _startupError != null
            ? _StartupError(
                key: const ValueKey('startup-error'),
                message: 'Could not open CampusPlus: $_startupError',
                onRetry: () {
                  setState(() => _startupError = null);
                  _continueFromSplash();
                },
              )
            : _showApp
                ? const AuthGate(key: ValueKey('auth-gate'))
                : _showOnboarding
                    ? OnboardingPage(
                        key: const ValueKey('onboarding'),
                        onFinished: _finishOnboarding,
                      )
                    : _CampusSplash(
                        key: const ValueKey('splash'),
                        onContinue: () {
                          _timer?.cancel();
                          _continueFromSplash();
                        },
                      ),
      );
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _slides = [
    (
      'Report Campus Problems',
      'Quickly report classroom, facility, network, sanitation and other campus issues in seconds.',
      Color(0xFF4F46E5),
      Icons.assignment_late_outlined,
    ),
    (
      'Track Every Update',
      'Stay informed about the progress of reported issues with clear status and repair updates.',
      Color(0xFF079BD4),
      Icons.track_changes_rounded,
    ),
    (
      'Make Campus Better',
      'Work together with students and staff to resolve campus problems faster for everyone.',
      Color(0xFF8B3CF0),
      Icons.groups_rounded,
    ),
  ];

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onFinished();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF4F4FF),
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          _OnboardingIllustration(
                            color: slide.$3,
                            icon: slide.$4,
                            page: index,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            slide.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            slide.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: muted,
                              height: 1.55,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(flex: 3),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: _page == index ? 21 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _page == index
                                ? _slides[index].$3
                                : const Color(0xFFD9DCEB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (_page < _slides.length - 1)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _finishing ? null : _finish,
                              child: const Text('Skip'),
                            ),
                          ),
                        if (_page < _slides.length - 1)
                          const SizedBox(width: 10),
                        Expanded(
                          flex: _page == _slides.length - 1 ? 1 : 2,
                          child: FilledButton(
                            onPressed: _finishing ? null : _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: _slides[_page].$3,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _finishing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _page == _slides.length - 1
                                        ? 'Get Started →'
                                        : 'Next →',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({
    required this.color,
    required this.icon,
    required this.page,
  });

  final Color color;
  final IconData icon;
  final int page;

  @override
  Widget build(BuildContext context) => Container(
        height: 230,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, const Color(0xFF4F46E5), .3)!],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: -40,
              top: -75,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .14)),
                ),
              ),
            ),
            if (page == 0)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 86,
                    height: 95,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(icon, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Network      Facility      Safety',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              )
            else if (page == 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_active,
                      color: Color(0xFFFFCB44), size: 34),
                  const SizedBox(width: 19),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in [
                        ('Reported', Colors.white54),
                        ('Verified', const Color(0xFF43D7A0)),
                        ('In Progress', const Color(0xFFB78BFF)),
                        ('Resolved', const Color(0xFF70C9FF)),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 12, color: item.$2),
                              const SizedBox(width: 9),
                              Container(
                                width: 86,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.$1,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final metric in [
                    ('63', 'Resolved'),
                    ('94%', 'Success'),
                    ('1.2k', 'Affected'),
                  ])
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person,
                          size: 44,
                          color: Colors.white70,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Column(
                            children: [
                              Text(
                                metric.$1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                metric.$2,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      );
}

class _CampusSplash extends StatelessWidget {
  const _CampusSplash({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF211B65), Color(0xFF4F46E5), Color(0xFF6D4AFF)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -130,
                bottom: 80,
                child: Container(
                  width: 390,
                  height: 390,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .10)),
                  ),
                ),
              ),
              Positioned(
                right: -90,
                bottom: 120,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .12)),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(27),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: .16),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'C+',
                                  style: TextStyle(
                                    color: brand,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Positioned(
                                right: -5,
                                bottom: -5,
                                child: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: Color(0xFFFFB800),
                                  child: Icon(
                                    Icons.auto_awesome,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'CampusPlus',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 31,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'REPORT  ·  TRACK  ·  RESOLVE',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const _CampusSkyline(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 25, top: 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              3,
                              (index) => Container(
                                width: 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(
                                    alpha: index == 0 ? .9 : .35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 9),
                          TextButton(
                            onPressed: onContinue,
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Colors.white.withValues(alpha: .78),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: const Text('Tap to continue'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _CampusSkyline extends StatelessWidget {
  const _CampusSkyline();

  @override
  Widget build(BuildContext context) {
    const heights = [
      34.0,
      52.0,
      29.0,
      67.0,
      42.0,
      31.0,
      56.0,
      38.0,
      62.0,
      30.0
    ];
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: heights
            .map(
              (height) => Expanded(
                child: Container(
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _profileProvisioningUid;
  String? _profileProvisioningError;

  void _provisionMissingProfile(User user) {
    if (_profileProvisioningUid == user.uid) return;
    _profileProvisioningUid = user.uid;
    _profileProvisioningError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final fallbackName =
            user.email?.split('@').first.trim().isNotEmpty == true
                ? user.email!.split('@').first
                : 'Student';
        await FirebaseIssueRepository().createUserProfile(
          user: user,
          displayName: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : fallbackName,
        );
      } catch (error) {
        if (mounted) {
          setState(() => _profileProvisioningError = error.toString());
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScreen();
          }
          final user = authSnapshot.data;
          if (user == null) {
            return const SignInPage();
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseIssueRepository().watchUserProfile(user.uid),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.hasError) {
                return _StartupError(
                  message:
                      'Could not load your account profile: ${profileSnapshot.error}',
                  onRetry: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const AuthGate()),
                  ),
                );
              }
              if (!profileSnapshot.hasData) {
                return const _LoadingScreen();
              }
              if (!profileSnapshot.data!.exists) {
                if (_profileProvisioningError != null &&
                    _profileProvisioningUid == user.uid) {
                  return _StartupError(
                    message:
                        'Could not initialize your account: $_profileProvisioningError',
                    onRetry: () => setState(() {
                      _profileProvisioningUid = null;
                      _profileProvisioningError = null;
                    }),
                  );
                }
                _provisionMissingProfile(user);
                return const _LoadingScreen();
              }

              final roleValue =
                  profileSnapshot.data!.data()?['role'] as String? ?? 'student';
              return HomeShell(
                role: _roleLabel(roleValue),
                email: user.email ?? '',
              );
            },
          );
        },
      );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = FirebaseAuth.instance;
      final email = _emailController.text.trim();
      if (_registering) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );
        await credential.user!.updateDisplayName(_nameController.text.trim());
        await FirebaseIssueRepository().createUserProfile(
          user: credential.user!,
          displayName: _nameController.text.trim(),
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() =>
            _error = 'Firebase setup error: ${error.message ?? error.code}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not complete sign-in: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not send reset email: $error');
      }
    }
  }

  String _authErrorMessage(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for this email.',
        'weak-password' =>
          'Choose a stronger password with at least 6 characters.',
        'network-request-failed' =>
          'Network error. Check your connection and try again.',
        'too-many-requests' =>
          'Too many attempts. Wait a moment and try again.',
        _ => error.message ?? 'Authentication failed (${error.code}).',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF312E81), Color(0xFF6D4AFF)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Text(
                            'C+',
                            style: TextStyle(
                              color: brand,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CampusPlus',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'REPORT  ·  TRACK  ·  RESOLVE',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'Your campus, made better.',
                    style: TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w800, color: ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to report and resolve campus issues.',
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _registering
                        ? 'Create your student account'
                        : 'Welcome back',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_registering) ...[
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null || value.trim().length < 2
                                    ? 'Enter your name.'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) =>
                              value == null || !value.contains('@')
                                  ? 'Enter a valid email address.'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          autofillHints: _registering
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.length < 6
                                  ? 'Password must be at least 6 characters.'
                                  : null,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (!_registering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _sendPasswordReset,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                    child: Text(
                      _registering
                          ? 'Already have an account? Sign in'
                          : 'New to CampusPlus? Create a student account',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'New accounts are Students. Staff and Admin accounts sign in here with their email and password after an Admin creates or assigns their role.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 42, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.role, required this.email});
  final String role;
  final String email;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String query = '';
  String filter = 'All';
  final repository = FirebaseIssueRepository();
  StreamSubscription<List<CampusIssue>>? _issuesSubscription;
  List<CampusIssue> issues = [];
  bool _loadingIssues = true;
  String? _issuesError;
  List<CampusIssue> get all => issues;
  bool get student => widget.role == 'Student';
  bool get staff => widget.role == 'Maintenance Staff';
  String get title => student
      ? 'Hello, Student 👋'
      : staff
          ? 'Staff workspace'
          : 'Authority dashboard';

  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.onOpen = _handlePushOpen;
    if (widget.role == 'Authority / Admin') {
      unawaited(_migrateLegacyReporterUids());
    }
    _issuesSubscription = repository.watchIssues().listen(
      (value) {
        if (!mounted) return;
        setState(() {
          issues = value;
          _loadingIssues = false;
          _issuesError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loadingIssues = false;
          _issuesError = error.toString();
        });
      },
    );
  }

  Future<void> _migrateLegacyReporterUids() async {
    try {
      await repository.migrateLegacyReporterUids();
      await repository.migrateLegacyAssigneeNames();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update legacy issue records: $error',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  void dispose() {
    _issuesSubscription?.cancel();
    PushNotificationService.instance.onOpen = null;
    super.dispose();
  }

  Future<void> _handlePushOpen(String? issueId) async {
    if (!mounted) return;
    final issue = all.where((item) => item.id == issueId).firstOrNull;
    if (issue != null) {
      _openIssue(issue);
    } else {
      setState(() => index = 3);
    }
  }

  void _selectDrawerDestination(int destination) {
    Navigator.pop(context);
    setState(() => index = destination);
  }

  Widget _buildDrawer(List<String> labels, List<IconData> icons) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF312E81), Color(0xFF6D4AFF)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white,
                    child: Text(
                      'C+',
                      style: TextStyle(
                        color: brand,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.role,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    currentUser?.email ?? widget.email,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (var destination = 0;
                      destination < labels.length;
                      destination++)
                    ListTile(
                      leading: Icon(
                        icons[destination],
                        color: index == destination ? brand : muted,
                      ),
                      title: Text(labels[destination]),
                      selected: index == destination,
                      selectedTileColor: const Color(0xFFEDEBFF),
                      onTap: () => _selectDrawerDestination(destination),
                    ),
                  if (student)
                    ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: const Text('My issues'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyIssuesPage(
                              uid: currentUser!.uid,
                              watchIssues: repository.watchIssues,
                              watchMyIssueIds: repository.watchMyIssueIds,
                              updateIssue: repository.updateIssue,
                              deleteIssue: repository.deleteIssue,
                              dismissDeletionRequest:
                                  repository.dismissIssueDeletionRequest,
                              uploadPhoto: repository.uploadIssuePhoto,
                              onOpenIssue: _openIssue,
                              onMessage: _showMessage,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!student && !staff)
                    ListTile(
                      leading: const Icon(Icons.manage_search_outlined),
                      title: const Text('Manage all issues'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageAllIssuesPage(
                              watchIssues: repository.watchIssues,
                              requestDeletion: repository.requestIssueDeletion,
                              onOpenIssue: _openIssue,
                              onMessage: _showMessage,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!student && !staff)
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('Manage accounts'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageAccountsPage(
                              repository: repository,
                            ),
                          ),
                        );
                      },
                    ),
                  const Divider(height: 20),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('Help & support'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportPage(
                            repository: repository,
                            isAdmin: !student && !staff,
                            isStudent: student,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Could not sign out: $error')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _issuesPage(),
      student ? _reportPage() : _tasksPage(),
      _notificationsPage(),
      _profilePage(),
    ];
    final labels = student
        ? ['Home', 'Issues', 'Report', 'Updates', 'Profile']
        : ['Overview', 'Issues', 'Tasks', 'Updates', 'Profile'];
    final icons = student
        ? [
            Icons.home_rounded,
            Icons.list_alt_rounded,
            Icons.add_circle_outline,
            Icons.notifications_none_rounded,
            Icons.person_outline_rounded
          ]
        : [
            Icons.dashboard_outlined,
            Icons.list_alt_rounded,
            Icons.assignment_outlined,
            Icons.notifications_none_rounded,
            Icons.person_outline_rounded
          ];
    final safeIndex = index.clamp(0, pages.length - 1);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      return Scaffold(
        drawer: _buildDrawer(labels, icons),
        appBar: AppBar(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(index == 0 ? title : labels[safeIndex],
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            if (index == 0)
              const Text('University issue reporting & resolution',
                  style: TextStyle(fontSize: 11, color: muted)),
          ]),
          actions: [
            IconButton(
                onPressed: () => setState(() => index = 3),
                icon: const Icon(Icons.notifications_none_rounded)),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(children: [
          if (wide)
            NavigationRail(
              selectedIndex: safeIndex,
              onDestinationSelected: (v) => setState(() => index = v),
              labelType: NavigationRailLabelType.all,
              destinations: List.generate(
                  labels.length,
                  (i) => NavigationRailDestination(
                      icon: Icon(icons[i]), label: Text(labels[i]))),
            ),
          Expanded(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: IndexedStack(
                        index: safeIndex,
                        children: pages,
                      )))),
        ]),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: safeIndex,
                onDestinationSelected: (v) => setState(() => index = v),
                destinations: List.generate(
                    labels.length,
                    (i) => NavigationDestination(
                        icon: Icon(icons[i]), label: labels[i])),
              ),
        floatingActionButton: !student && index == 2 && staff
            ? FloatingActionButton.extended(
                onPressed: () => _showMessage('Task list refreshed'),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'))
            : null,
      );
    });
  }

  Widget _dashboard() {
    final open = all.where((i) => i.isOpen).length;
    final resolved = all.where((i) => i.status == IssueStatus.resolved).length;
    final myStaffTasks = all
        .where((issue) =>
            issue.assignedTo == FirebaseAuth.instance.currentUser?.uid ||
            (issue.status == IssueStatus.verificationRequested &&
                issue.verificationAssignedTo ==
                    FirebaseAuth.instance.currentUser?.uid))
        .toList(growable: false);
    final review = all
        .where((i) =>
            i.status == IssueStatus.reported ||
            i.status == IssueStatus.verified)
        .length;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
            borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Make your campus better',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              student
                  ? 'Report a problem, follow progress, and help verify the fix.'
                  : staff
                      ? 'Review assigned work and keep campus services moving.'
                      : 'Review, prioritize and route campus issues to the right team.',
              style: const TextStyle(color: Colors.white70, height: 1.4)),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (student)
              FilledButton.icon(
                onPressed: () => setState(() => index = 2),
                icon: const Icon(Icons.add),
                label: const Text('Report issue'),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: brand),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => index = 1),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Browse issues'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: _stat(
            'Open issues',
            '$open',
            Icons.pending_actions_rounded,
            const Color(0xFF6D5CE8),
            onTap: () => _showIssuesWithFilter('Open'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _stat(
            'Resolved',
            '$resolved',
            Icons.task_alt_rounded,
            const Color(0xFF159A78),
            onTap: () => _showIssuesWithFilter('Resolved'),
          ),
        ),
      ]),
      if (!student && !staff) ...[
        const SizedBox(height: 10),
        _stat(
          'Needs admin review',
          '$review',
          Icons.fact_check_outlined,
          const Color(0xFF0E9AA7),
          onTap: () => _showIssuesWithFilter('Needs review'),
        ),
      ],
      const SizedBox(height: 22),
      _sectionTitle(
          student
              ? 'Recent campus issues'
              : staff
                  ? 'My assigned work · ${myStaffTasks.length}'
                  : 'Needs attention',
          onTap: staff
              ? () => setState(() => index = 2)
              : () => _showIssuesWithFilter('All')),
      const SizedBox(height: 10),
      if (staff && myStaffTasks.isEmpty)
        const _EmptyState(
          title: 'No assigned tasks yet',
          subtitle:
              'Inspection requests and repair assignments from Admin will appear in Tasks.',
        ),
      ...(staff ? myStaffTasks : all)
          .take(3)
          .map((i) => IssueTile(issue: i, onTap: () => _openIssue(i))),
      const SizedBox(height: 18),
      if (!student) _sectionTitle(staff ? 'Staff actions' : 'Quick actions'),
      if (staff)
        Wrap(spacing: 10, runSpacing: 10, children: [
          ActionChip(
            avatar: const Icon(Icons.assignment_ind_outlined),
            label: const Text('Open my tasks'),
            onPressed: () => setState(() => index = 2),
          ),
          ActionChip(
            avatar: const Icon(Icons.list_alt_outlined),
            label: const Text('Browse all issues'),
            onPressed: () => _showIssuesWithFilter('All'),
          ),
        ]),
      if (!student && !staff)
        Wrap(spacing: 10, runSpacing: 10, children: [
          ActionChip(
              avatar: const Icon(Icons.fact_check_outlined),
              label: const Text('Review reports'),
              onPressed: () => _showIssuesWithFilter('Needs review')),
          ActionChip(
              avatar: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assignments'),
              onPressed: () => setState(() => index = 2)),
          ActionChip(
              avatar: const Icon(Icons.bar_chart_rounded),
              label: const Text('View analytics'),
              onPressed: _showAnalytics),
        ]),
    ]);
  }

  Widget _issuesPage() {
    final list = all.where((i) {
      final match = '${i.title} ${i.description} ${i.category} ${i.location}'
          .toLowerCase()
          .contains(query.toLowerCase());
      final status = switch (filter) {
        'Open' => i.isOpen,
        'Resolved' => i.status == IssueStatus.resolved,
        'Needs review' =>
          i.status == IssueStatus.reported || i.status == IssueStatus.verified,
        _ => filter == 'All' || i.status.label == filter,
      };
      return match && status;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_issuesError != null)
          _ErrorBanner(message: 'Could not load issues: $_issuesError'),
        if (_loadingIssues) const LinearProgressIndicator(),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search issue, category or location',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              'All',
              'Open',
              'Needs review',
              'Reported',
              'Verification requested',
              'Verified',
              'Assigned',
              'In Progress',
              'Resolved'
            ]
                .map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: filter == s,
                      onSelected: (_) => setState(() => filter = s),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty && !_loadingIssues && _issuesError == null)
          const _EmptyState(
              title: 'No issues found',
              subtitle: 'Try another search or filter.'),
        ...list.map((i) => IssueTile(issue: i, onTap: () => _openIssue(i))),
      ],
    );
  }

  void _showIssuesWithFilter(String value) {
    setState(() {
      filter = value;
      index = 1;
    });
  }

  Widget _tasksPage() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final tasks = staff
        ? all
            .where((issue) =>
                issue.assignedTo == uid || issue.verificationAssignedTo == uid)
            .toList()
        : all
            .where((issue) =>
                issue.status == IssueStatus.reported ||
                issue.status == IssueStatus.verified)
            .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          staff ? 'My assignments & inspections' : 'Reports awaiting review',
          style: const TextStyle(
            color: ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (_issuesError != null)
          _ErrorBanner(message: 'Could not load tasks: $_issuesError'),
        if (_loadingIssues) const LinearProgressIndicator(),
        if (tasks.isEmpty && !_loadingIssues && _issuesError == null)
          _EmptyState(
            title: staff ? 'No assigned tasks' : 'Nothing needs review',
            subtitle: staff
                ? 'Inspection requests and repair assignments will appear here.'
                : 'New reports and staff-verified issues will appear here.',
          ),
        ...tasks.map((issue) => IssueTile(
              issue: issue,
              onTap: () => _openIssue(issue),
            )),
      ],
    );
  }

  Widget _reportPage() => ReportIssuePage(
      onMarkAffected: repository.markAffected,
      onSubmit: (issue, photoBytes, photoName, contentType) async {
        if (photoBytes != null && photoName != null && contentType != null) {
          issue.imageUrl = await repository.uploadIssuePhoto(
            bytes: photoBytes,
            fileName: photoName,
            contentType: contentType,
          );
        }
        await repository.createIssue(issue);
        if (!mounted) return;
        setState(() => index = 1);
        _showMessage('Report submitted.');
      },
      onSimilar: (category, location) {
        final matches = all
            .where((i) =>
                i.isOpen && i.category == category && i.location == location)
            .toList();
        return matches;
      });

  Widget _notificationsPage() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return IssueUpdatesPage(
      issues: all,
      notifications: repository.watchNotifications(uid),
      watchWorkUpdates: repository.watchWorkUpdates,
      markNotificationRead: repository.markNotificationRead,
      onOpenIssue: _openIssue,
      onMessage: _showMessage,
    );
  }

  Widget _profilePage() =>
      ListView(padding: const EdgeInsets.all(18), children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: repository.watchUserProfile(
            FirebaseAuth.instance.currentUser!.uid,
          ),
          builder: (context, snapshot) {
            final profile = snapshot.data?.data() ?? const {};
            final photoUrl = profile['photoUrl'] as String?;
            final displayName = profile['displayName'] as String?;
            return Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0xFFE7E5FF),
                    foregroundImage:
                        photoUrl == null ? null : NetworkImage(photoUrl),
                    child: photoUrl != null
                        ? null
                        : Icon(
                            student
                                ? Icons.school_rounded
                                : staff
                                    ? Icons.handyman_rounded
                                    : Icons.admin_panel_settings_rounded,
                            size: 38,
                            color: brand,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName?.isNotEmpty == true
                        ? displayName!
                        : widget.role,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    widget.email,
                    style: const TextStyle(color: muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.role,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _menuTile(
            Icons.person_outline,
            'Edit profile',
            'Update your display name and photo',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EditProfilePage(repository: repository)))),
        _menuTile(
            Icons.settings_outlined,
            'Settings',
            'Push alerts and privacy preferences',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsPage(repository: repository)))),
        _menuTile(
            Icons.help_outline,
            'Help & support',
            'FAQs and contact the campus support team',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SupportPage(
                          repository: repository,
                          isAdmin: !student && !staff,
                          isStudent: student,
                        )))),
        if (!student && !staff)
          _menuTile(
              Icons.manage_accounts_outlined,
              'Manage accounts',
              'Create Staff accounts and manage account roles',
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ManageAccountsPage(repository: repository)))),
        _menuTile(Icons.logout, 'Sign out', 'Sign out of your account',
            () async {
          try {
            await FirebaseAuth.instance.signOut();
          } catch (error) {
            if (mounted) _showMessage('Could not sign out: $error');
          }
        }),
      ]);

  Widget _stat(
    String label,
    String value,
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE9EAF2)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  color: ink,
                ),
              ),
              Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _sectionTitle(String title, {VoidCallback? onTap}) => Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17, color: ink))),
        if (onTap != null)
          TextButton(onPressed: onTap, child: const Text('See all')),
      ]);

  Widget _menuTile(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      Card(
        child: ListTile(
            leading: Icon(icon, color: brand),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap),
      );

  void _openIssue(CampusIssue issue) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => IssueDetailPage(
                issue: issue,
                role: widget.role,
                onChanged: _persistIssue,
                onMarkAffected: repository.markAffected,
                onVerify: repository.recordVerification,
                onToggleFollow: repository.toggleFollow,
                checkFollowing: repository.isFollowing,
                checkAffected: repository.isAffected,
                checkVerification: repository.hasVerification,
                loadStaffUsers: repository.getStaffUsers,
                watchWorkUpdates: repository.watchWorkUpdates,
                addWorkUpdate: repository.addWorkUpdate,
                uploadPhoto: repository.uploadIssuePhoto,
                onMessage: _showMessage,
              )));
  Future<void> _persistIssue(CampusIssue issue) async {
    await repository.updateIssue(issue);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  void _showAnalytics() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => AnalyticsPage(issues: all)));
}

class IssueUpdatesPage extends StatelessWidget {
  const IssueUpdatesPage({
    super.key,
    required this.issues,
    required this.notifications,
    required this.watchWorkUpdates,
    required this.markNotificationRead,
    required this.onOpenIssue,
    required this.onMessage,
  });

  final List<CampusIssue> issues;
  final Stream<List<Map<String, dynamic>>> notifications;
  final Stream<List<WorkUpdate>> Function(String) watchWorkUpdates;
  final Future<void> Function(String, String) markNotificationRead;
  final ValueChanged<CampusIssue> onOpenIssue;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    final recent = [...issues]..sort((a, b) =>
        (b.updatedAt ?? b.createdAt ?? DateTime(2000))
            .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(2000)));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Issue activity',
          style:
              TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Follow staff notes, completed work, remaining steps, and status changes.',
          style: TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: notifications,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorBanner(
                message: 'Could not load your notifications: ${snapshot.error}',
              );
            }
            final notices = snapshot.data ?? const [];
            if (notices.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 8),
                ...notices.map((notification) {
                  final issueId = notification['issueId'] as String?;
                  final issue =
                      issues.where((item) => item.id == issueId).firstOrNull;
                  final createdAt = notification['createdAt'];
                  return _Notice(
                    icon: notification['read'] == true
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_outlined,
                    title:
                        notification['title'] as String? ?? 'CampusPlus update',
                    body: notification['body'] as String? ?? '',
                    time: createdAt is Timestamp
                        ? _formatTimeAgo(createdAt.toDate())
                        : 'Just now',
                    onTap: () async {
                      try {
                        await markNotificationRead(
                          FirebaseAuth.instance.currentUser!.uid,
                          notification['id'] as String,
                        );
                        if (issue != null) onOpenIssue(issue);
                      } catch (error) {
                        onMessage('Could not open notification: $error');
                      }
                    },
                  );
                }),
                const SizedBox(height: 18),
              ],
            );
          },
        ),
        const Text(
          'Step-by-step progress',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const _EmptyState(
            title: 'No issue activity yet',
            subtitle: 'Reported issues and staff progress will appear here.',
          )
        else
          ...recent.take(40).map(
                (issue) => _IssueActivityCard(
                  issue: issue,
                  watchWorkUpdates: watchWorkUpdates,
                  onTap: () => onOpenIssue(issue),
                ),
              ),
      ],
    );
  }
}

class _IssueActivityCard extends StatelessWidget {
  const _IssueActivityCard({
    required this.issue,
    required this.watchWorkUpdates,
    required this.onTap,
  });

  final CampusIssue issue;
  final Stream<List<WorkUpdate>> Function(String) watchWorkUpdates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        issue.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _StatusPill(issue.status),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${issue.id} · ${issue.location}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                if (issue.history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.history, size: 18, color: brand),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          issue.history.last,
                          style: const TextStyle(height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                StreamBuilder<List<WorkUpdate>>(
                  stream: watchWorkUpdates(issue.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        'Could not load staff progress: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent),
                      );
                    }
                    final updates = snapshot.data ?? const [];
                    if (updates.isEmpty) {
                      return const Text(
                        'No staff repair steps posted yet.',
                        style: TextStyle(color: muted),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final update in updates.reversed.take(2))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F5FF),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${update.authorName} · ${update.createdAt == null ? 'Just now' : _formatTimeAgo(update.createdAt!)}',
                                    style: const TextStyle(
                                      color: brand,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (update.note.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      update.note,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (update.completedSteps.isNotEmpty)
                                    _activitySteps(
                                      'Done',
                                      update.completedSteps,
                                      const Color(0xFF138A68),
                                    ),
                                  if (update.nextSteps.isNotEmpty)
                                    _activitySteps(
                                      'Next',
                                      update.nextSteps,
                                      const Color(0xFFB36B00),
                                    ),
                                  if (update.photoUrl?.isNotEmpty == true) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        update.photoUrl!,
                                        height: 150,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Text(
                                          'Repair photo could not be loaded.',
                                          style: TextStyle(color: muted),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap to view the complete timeline  ›',
                    style: TextStyle(
                      color: brand,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _activitySteps(String label, List<String> steps, Color color) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            Text(
              '$label:',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
            ...steps.map(
              (step) => Text(
                '• $step',
                style: const TextStyle(color: ink),
              ),
            ),
          ],
        ),
      );
}

class MyIssuesPage extends StatelessWidget {
  const MyIssuesPage({
    super.key,
    required this.uid,
    required this.watchIssues,
    required this.watchMyIssueIds,
    required this.updateIssue,
    required this.deleteIssue,
    required this.dismissDeletionRequest,
    required this.uploadPhoto,
    required this.onOpenIssue,
    required this.onMessage,
    this.pickPhoto,
  });

  final String uid;
  final Stream<List<CampusIssue>> Function() watchIssues;
  final Stream<List<String>> Function(String) watchMyIssueIds;
  final Future<void> Function(CampusIssue) updateIssue;
  final Future<void> Function(String) deleteIssue;
  final Future<void> Function(String) dismissDeletionRequest;
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) uploadPhoto;
  final ValueChanged<CampusIssue> onOpenIssue;
  final ValueChanged<String> onMessage;
  final Future<XFile?> Function()? pickPhoto;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const Scaffold(
        body: _EmptyState(
          title: 'Sign in to view your issues',
          subtitle: 'Sign in to see the issues you have reported.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My issues')),
      body: StreamBuilder<List<String>>(
        stream: watchMyIssueIds(uid),
        builder: (context, idSnapshot) {
          if (idSnapshot.hasError) {
            return _ErrorBanner(
              message: 'Could not load your issue list: ${idSnapshot.error}',
            );
          }
          if (!idSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final issueIds = idSnapshot.data!.toSet();
          return StreamBuilder<List<CampusIssue>>(
            stream: watchIssues(),
            builder: (context, issueSnapshot) {
              if (issueSnapshot.hasError) {
                return _ErrorBanner(
                  message:
                      'Could not load issue details: ${issueSnapshot.error}',
                );
              }
              if (!issueSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final issues = issueSnapshot.data!
                  .where((issue) => issueIds.contains(issue.id))
                  .toList(growable: false);
              if (issues.isEmpty) {
                return const _EmptyState(
                  title: 'No reports yet',
                  subtitle: 'Issues you report will be listed here.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Reports you submitted',
                    style: TextStyle(
                      color: ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Track progress, edit an unassigned report, or manage a deletion request.',
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ...issues.map(
                    (issue) => _MyIssueCard(
                      issue: issue,
                      updateIssue: updateIssue,
                      deleteIssue: deleteIssue,
                      dismissDeletionRequest: dismissDeletionRequest,
                      uploadPhoto: uploadPhoto,
                      onOpenIssue: onOpenIssue,
                      onMessage: onMessage,
                      pickPhoto: pickPhoto,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MyIssueCard extends StatefulWidget {
  const _MyIssueCard({
    required this.issue,
    required this.updateIssue,
    required this.deleteIssue,
    required this.dismissDeletionRequest,
    required this.uploadPhoto,
    required this.onOpenIssue,
    required this.onMessage,
    this.pickPhoto,
  });

  final CampusIssue issue;
  final Future<void> Function(CampusIssue) updateIssue;
  final Future<void> Function(String) deleteIssue;
  final Future<void> Function(String) dismissDeletionRequest;
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) uploadPhoto;
  final ValueChanged<CampusIssue> onOpenIssue;
  final ValueChanged<String> onMessage;
  final Future<XFile?> Function()? pickPhoto;

  @override
  State<_MyIssueCard> createState() => _MyIssueCardState();
}

class _MyIssueCardState extends State<_MyIssueCard> {
  bool _busy = false;

  bool get _canEdit =>
      widget.issue.status == IssueStatus.reported &&
      widget.issue.assignedTo.isEmpty;

  bool get _canDelete =>
      _canEdit ||
      (widget.issue.status == IssueStatus.rejected &&
          widget.issue.assignedTo.isEmpty) ||
      (widget.issue.status == IssueStatus.resolved &&
          widget.issue.deletionRequestStatus == 'pending');

  Future<void> _edit() async {
    final draft = await showDialog<_IssueEditDraft>(
      context: context,
      builder: (_) => _IssueEditDialog(
        issue: widget.issue,
        pickPhoto: widget.pickPhoto,
      ),
    );
    if (!mounted || draft == null) return;
    final issue = widget.issue;
    final previous = (
      title: issue.title,
      description: issue.description,
      category: issue.category,
      severity: issue.severity,
      location: issue.location,
      building: issue.building,
      floor: issue.floor,
      room: issue.room,
      photoUrl: issue.imageUrl,
    );
    setState(() => _busy = true);
    try {
      String? photoUrl = issue.imageUrl;
      if (draft.removePhoto) {
        photoUrl = null;
      } else if (draft.photo != null) {
        final contentType = _imageContentType(draft.photo!.name);
        if (contentType == null) {
          throw ArgumentError('Choose a JPG, PNG, or WebP image.');
        }
        final bytes = await draft.photo!.readAsBytes();
        if (bytes.lengthInBytes > 5 * 1024 * 1024) {
          throw ArgumentError('Choose an image smaller than 5 MB.');
        }
        photoUrl = await widget.uploadPhoto(
          bytes: bytes,
          fileName: draft.photo!.name,
          contentType: contentType,
        );
      }
      issue
        ..title = draft.title
        ..description = draft.description
        ..category = draft.category
        ..severity = draft.severity
        ..building = draft.building
        ..floor = draft.floor
        ..room = draft.room
        ..location = _composeLocation(
          draft.building,
          draft.floor,
          draft.room,
        )
        ..imageUrl = photoUrl;
      await widget.updateIssue(issue);
      widget.onMessage('Your issue was updated.');
    } catch (error) {
      issue
        ..title = previous.title
        ..description = previous.description
        ..category = previous.category
        ..severity = previous.severity
        ..location = previous.location
        ..building = previous.building
        ..floor = previous.floor
        ..room = previous.room
        ..imageUrl = previous.photoUrl;
      widget.onMessage('Could not update your issue: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final awaitingApproval = widget.issue.deletionRequestStatus == 'pending';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(awaitingApproval ? 'Approve deletion?' : 'Delete report?'),
        content: Text(
          awaitingApproval
              ? 'Approving will delete this resolved issue immediately. Admin will not need to repeat the action.'
              : 'This will permanently delete your report because no repair worker is assigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(awaitingApproval ? 'Approve & delete' : 'Delete issue'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.deleteIssue(widget.issue.id);
      widget.onMessage(
        awaitingApproval
            ? 'Your approval was recorded and the issue was deleted.'
            : 'Your issue was deleted.',
      );
    } catch (error) {
      widget.onMessage('Could not delete issue: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepIssue() async {
    setState(() => _busy = true);
    try {
      await widget.dismissDeletionRequest(widget.issue.id);
      widget.onMessage('Deletion request declined. Your issue was kept.');
    } catch (error) {
      widget.onMessage('Could not respond to deletion request: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.issue.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${widget.issue.id} · ${widget.issue.location}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _StatusPill(widget.issue.status),
                onTap: () => widget.onOpenIssue(widget.issue),
              ),
              if (widget.issue.deletionRequestStatus == 'pending') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Admin is asking your permission to delete this resolved issue.',
                    style: TextStyle(height: 1.35),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_canEdit)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit report'),
                    ),
                  if (_canDelete)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        widget.issue.deletionRequestStatus == 'pending'
                            ? 'Approve & delete'
                            : 'Delete report',
                      ),
                    ),
                  if (widget.issue.deletionRequestStatus == 'pending')
                    TextButton(
                      onPressed: _busy ? null : _keepIssue,
                      child: const Text('Keep issue'),
                    ),
                  TextButton.icon(
                    onPressed: () => widget.onOpenIssue(widget.issue),
                    icon: const Icon(Icons.timeline_outlined),
                    label: const Text('View progress'),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      );
}

class _IssueEditDraft {
  const _IssueEditDraft({
    required this.title,
    required this.description,
    required this.category,
    required this.severity,
    required this.building,
    required this.floor,
    required this.room,
    required this.photo,
    required this.removePhoto,
  });

  final String title;
  final String description;
  final String category;
  final String severity;
  final String building;
  final String floor;
  final String room;
  final XFile? photo;
  final bool removePhoto;
}

class _IssueEditDialog extends StatefulWidget {
  const _IssueEditDialog({required this.issue, this.pickPhoto});

  final CampusIssue issue;
  final Future<XFile?> Function()? pickPhoto;

  @override
  State<_IssueEditDialog> createState() => _IssueEditDialogState();
}

class _IssueEditDialogState extends State<_IssueEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _building;
  late final TextEditingController _floor;
  late final TextEditingController _room;
  late String _category;
  late String _severity;
  XFile? _photo;
  bool _removePhoto = false;
  bool _picking = false;
  String? _photoError;
  String? _validationError;

  static const _categories = [
    'Electrical',
    'Plumbing',
    'Furniture',
    'Cleanliness',
    'Internet',
    'Safety',
    'Other',
  ];
  static const _severities = ['Low', 'Medium', 'High', 'Urgent'];

  @override
  void initState() {
    super.initState();
    final issue = widget.issue;
    _title = TextEditingController(text: issue.title);
    _description = TextEditingController(text: issue.description);
    _building = TextEditingController(text: issue.building);
    _floor = TextEditingController(text: issue.floor);
    _room = TextEditingController(text: issue.room);
    _category = _categories.contains(issue.category) ? issue.category : 'Other';
    _severity =
        _severities.contains(issue.severity) ? issue.severity : 'Medium';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _building.dispose();
    _floor.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _picking = true;
      _photoError = null;
    });
    try {
      final photo = await (widget.pickPhoto?.call() ??
          ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
            maxWidth: 1600,
          ));
      if (!mounted || photo == null) return;
      if (_imageContentType(photo.name) == null) {
        setState(() => _photoError = 'Choose a JPG, PNG, or WebP image.');
        return;
      }
      final bytes = await photo.readAsBytes();
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        setState(() => _photoError = 'Choose an image smaller than 5 MB.');
        return;
      }
      setState(() {
        _photo = photo;
        _removePhoto = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _photoError = 'Could not select photo: $error');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _save() {
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (title.length < 4 || title.length > 70) {
      setState(() => _validationError = 'Title must be 4 to 70 characters.');
      return;
    }
    if (description.length < 10 || description.length > 500) {
      setState(
        () => _validationError = 'Description must be 10 to 500 characters.',
      );
      return;
    }
    if (_building.text.trim().length < 2 ||
        _floor.text.trim().isEmpty ||
        _room.text.trim().length < 2) {
      setState(
        () => _validationError = 'Complete the building, floor, and area.',
      );
      return;
    }
    Navigator.pop(
      context,
      _IssueEditDraft(
        title: title,
        description: description,
        category: _category,
        severity: _severity,
        building: _building.text.trim(),
        floor: _floor.text.trim(),
        room: _room.text.trim(),
        photo: _photo,
        removePhoto: _removePhoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit your issue'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _title,
                  maxLength: 70,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _category = value ?? _category),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: _severities
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _severity = value ?? _severity),
                ),
                TextField(
                  controller: _building,
                  decoration: const InputDecoration(labelText: 'Building'),
                ),
                TextField(
                  controller: _floor,
                  decoration: const InputDecoration(labelText: 'Floor'),
                ),
                TextField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: 'Room / area'),
                ),
                const SizedBox(height: 8),
                if (!_removePhoto &&
                    _photo == null &&
                    widget.issue.imageUrl?.isNotEmpty == true)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.issue.imageUrl!,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Text('Current photo could not be loaded.'),
                    ),
                  ),
                if (_photo != null)
                  FutureBuilder<Uint8List>(
                    future: _photo!.readAsBytes(),
                    builder: (context, snapshot) => snapshot.hasData
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              snapshot.data!,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const LinearProgressIndicator(),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _picking ? null : _pickPhoto,
                      icon: _picking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _photo == null ? 'Change photo' : 'Photo selected',
                      ),
                    ),
                    if (_photo != null ||
                        widget.issue.imageUrl?.isNotEmpty == true)
                      TextButton(
                        onPressed: _picking
                            ? null
                            : () => setState(() {
                                  _photo = null;
                                  _removePhoto = true;
                                }),
                        child: const Text('Remove photo'),
                      ),
                  ],
                ),
                if (_photoError != null)
                  Text(
                    _photoError!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                if (_validationError != null)
                  Text(
                    _validationError!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _picking ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _picking ? null : _save,
            child: const Text('Save changes'),
          ),
        ],
      );
}

String _composeLocation(String building, String floor, String room) => [
      building.trim(),
      floor.trim(),
      room.trim()
    ].where((part) => part.isNotEmpty).join(' · ');

String _formatTimeAgo(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inDays >= 1) return '${elapsed.inDays}d ago';
  if (elapsed.inHours >= 1) return '${elapsed.inHours}h ago';
  if (elapsed.inMinutes >= 1) return '${elapsed.inMinutes}m ago';
  return 'Just now';
}

class ManageAllIssuesPage extends StatefulWidget {
  const ManageAllIssuesPage({
    super.key,
    required this.watchIssues,
    required this.requestDeletion,
    required this.onOpenIssue,
    required this.onMessage,
  });

  final Stream<List<CampusIssue>> Function() watchIssues;
  final Future<void> Function(String) requestDeletion;
  final ValueChanged<CampusIssue> onOpenIssue;
  final ValueChanged<String> onMessage;

  @override
  State<ManageAllIssuesPage> createState() => _ManageAllIssuesPageState();
}

class _ManageAllIssuesPageState extends State<ManageAllIssuesPage> {
  String _filter = 'All';
  String _query = '';
  final Set<String> _requesting = {};

  Future<void> _requestDeletion(CampusIssue issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request student approval'),
        content: Text(
          'Ask the student who reported “${issue.title}” for permission to delete this resolved issue? It will only be deleted after their approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _requesting.add(issue.id));
    try {
      await widget.requestDeletion(issue.id);
      widget.onMessage(
        'Approval request sent. The issue will delete automatically if the student approves.',
      );
    } catch (error) {
      widget.onMessage('Could not request deletion: $error');
    } finally {
      if (mounted) setState(() => _requesting.remove(issue.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Manage all issues')),
        body: StreamBuilder<List<CampusIssue>>(
          stream: widget.watchIssues(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorBanner(
                message: 'Could not load all issues: ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final issues = snapshot.data!.where((issue) {
              final matchesQuery =
                  '${issue.id} ${issue.title} ${issue.description} ${issue.location}'
                      .toLowerCase()
                      .contains(_query.toLowerCase());
              final matchesFilter = switch (_filter) {
                'Open' => issue.isOpen,
                'Resolved' => issue.status == IssueStatus.resolved,
                'Needs review' => issue.status == IssueStatus.reported ||
                    issue.status == IssueStatus.verified,
                _ => true,
              };
              return matchesQuery && matchesFilter;
            }).toList(growable: false);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Review, filter, and manage every campus report.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title, location or issue ID',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Open', 'Needs review', 'Resolved']
                        .map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              label: Text(value),
                              selected: _filter == value,
                              onSelected: (_) =>
                                  setState(() => _filter = value),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                if (issues.isEmpty)
                  const _EmptyState(
                    title: 'No matching issues',
                    subtitle: 'Change your search or filter.',
                  ),
                ...issues.map(
                  (issue) => Column(
                    children: [
                      IssueTile(
                        issue: issue,
                        onTap: () => widget.onOpenIssue(issue),
                      ),
                      if (issue.status == IssueStatus.resolved)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OutlinedButton.icon(
                              onPressed: _requesting.contains(issue.id) ||
                                      issue.deletionRequestStatus == 'pending'
                                  ? null
                                  : () => _requestDeletion(issue),
                              icon: _requesting.contains(issue.id)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline),
                              label: Text(
                                issue.deletionRequestStatus == 'pending'
                                    ? 'Awaiting student approval'
                                    : 'Request deletion approval',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class ReportIssuePage extends StatefulWidget {
  const ReportIssuePage({
    super.key,
    required this.onSubmit,
    required this.onSimilar,
    required this.onMarkAffected,
  });
  final Future<void> Function(CampusIssue, Uint8List?, String?, String?)
      onSubmit;
  final List<CampusIssue> Function(String, String) onSimilar;
  final Future<bool> Function(String) onMarkAffected;
  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final building = TextEditingController();
  final floor = TextEditingController();
  final room = TextEditingController();
  String category = 'Electrical';
  String severity = 'Medium';
  bool anonymous = false;
  bool checkedSimilar = false;
  bool submitting = false;
  bool _affectedSubmitting = false;
  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoContentType;
  final ImagePicker _imagePicker = ImagePicker();
  List<CampusIssue> similar = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _draftSaveTimer;
  bool _draftQueued = false;
  String? _draftIssueId;
  final categories = const [
    'Electrical',
    'Plumbing',
    'Furniture',
    'Cleanliness',
    'Internet',
    'Safety',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    title.addListener(_scheduleDraftSave);
    description.addListener(_scheduleDraftSave);
    building.addListener(_scheduleDraftSave);
    floor.addListener(_scheduleDraftSave);
    room.addListener(_scheduleDraftSave);
    unawaited(_loadPreferences().then((_) => _restoreDraft()));
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged, onError: (Object error) {
      if (mounted) _showMessage('Could not monitor network status: $error');
    });
  }

  String? get _draftStorageKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'campusplus_issue_draft_$uid';
  }

  Future<void> _restoreDraft() async {
    final key = _draftStorageKey;
    if (key == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final encodedDraft = preferences.getString(key);
      if (encodedDraft == null) return;
      final draft = jsonDecode(encodedDraft) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        title.text = draft['title'] as String? ?? '';
        description.text = draft['description'] as String? ?? '';
        building.text = draft['building'] as String? ?? '';
        floor.text = draft['floor'] as String? ?? '';
        room.text = draft['room'] as String? ?? '';
        category = draft['category'] as String? ?? category;
        severity = draft['severity'] as String? ?? severity;
        anonymous = draft['anonymous'] as bool? ?? anonymous;
        _draftIssueId = draft['issueId'] as String?;
        _draftQueued = draft['queued'] as bool? ?? false;
        final image = draft['photoBase64'] as String?;
        if (image != null) {
          _photoBytes = base64Decode(image);
          _photoName = draft['photoName'] as String?;
          _photoContentType = draft['photoContentType'] as String?;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _draftQueued
                ? 'Offline report draft restored. It will submit when connected.'
                : 'Your unsent report draft was restored.',
          ),
        ),
      );
      if (_draftQueued) {
        final connectivity = await Connectivity().checkConnectivity();
        if (_hasNetwork(connectivity)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_submitReport());
          });
        }
      }
    } catch (error) {
      if (mounted) _showMessage('Could not restore saved report draft: $error');
    }
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistDraft().catchError((Object error) {
        if (mounted) _showMessage('Could not save report draft: $error');
      }));
    });
  }

  Future<void> _persistDraft() async {
    final key = _draftStorageKey;
    if (key == null) return;
    final hasContent = title.text.trim().isNotEmpty ||
        description.text.trim().isNotEmpty ||
        building.text.trim().isNotEmpty ||
        floor.text.trim().isNotEmpty ||
        room.text.trim().isNotEmpty ||
        _photoBytes != null;
    final preferences = await SharedPreferences.getInstance();
    if (!hasContent) {
      await preferences.remove(key);
      return;
    }
    await preferences.setString(
      key,
      jsonEncode({
        'title': title.text,
        'description': description.text,
        'building': building.text,
        'floor': floor.text,
        'room': room.text,
        'category': category,
        'severity': severity,
        'anonymous': anonymous,
        'photoBase64': _photoBytes == null ? null : base64Encode(_photoBytes!),
        'photoName': _photoName,
        'photoContentType': _photoContentType,
        'issueId': _draftIssueId,
        'queued': _draftQueued,
      }),
    );
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  Future<bool> _networkAvailable() async {
    try {
      return _hasNetwork(await Connectivity().checkConnectivity());
    } catch (error) {
      if (mounted) _showMessage('Could not check network status: $error');
      return false;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_draftQueued && _hasNetwork(results) && !submitting) {
      unawaited(_submitReport());
    }
  }

  Future<void> _submitReport() async {
    if (submitting || !formKey.currentState!.validate()) return;
    if (!await _networkAvailable()) {
      setState(() {
        _draftQueued = true;
        _draftIssueId ??= _newIssueId();
      });
      try {
        await _persistDraft();
      } catch (error) {
        if (mounted) _showMessage('Could not save report locally: $error');
        return;
      }
      if (mounted) {
        _showMessage(
            'No connection. Your report is saved and will sync later.');
      }
      return;
    }
    final id = _draftIssueId ?? _newIssueId();
    setState(() {
      submitting = true;
      _draftIssueId = id;
      _draftQueued = false;
    });
    final fullLocation =
        '${building.text.trim()} · ${floor.text.trim()} · ${room.text.trim()}';
    var submitted = false;
    try {
      await _persistDraft();
      await widget.onSubmit(
        CampusIssue(
          id: id,
          title: title.text.trim(),
          description: description.text.trim(),
          category: category,
          location: fullLocation,
          building: building.text.trim(),
          floor: floor.text.trim(),
          room: room.text.trim(),
          reporter: anonymous
              ? 'Anonymous'
              : FirebaseAuth.instance.currentUser?.displayName ?? 'Student',
          isAnonymous: anonymous,
          severity: severity,
          createdAt: DateTime.now(),
          history: const ['Reported · Just now'],
        ),
        _photoBytes,
        _photoName,
        _photoContentType,
      );
      submitted = true;
    } catch (error) {
      final offline = !await _networkAvailable();
      if (mounted) {
        setState(() => _draftQueued = offline);
      }
      try {
        await _persistDraft();
      } catch (saveError) {
        if (mounted) {
          _showMessage('Could not preserve report draft: $saveError');
        }
      }
      if (mounted) {
        _showMessage(
          offline
              ? 'Connection lost. Your report is saved and will sync later.'
              : 'Could not submit report; your draft is saved: $error',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
    if (submitted) {
      final key = _draftStorageKey;
      if (key != null) {
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.remove(key);
        } catch (error) {
          if (mounted) {
            _showMessage('Report submitted, but draft cleanup failed: $error');
          }
        }
      }
      if (mounted) {
        setState(() {
          title.clear();
          description.clear();
          building.clear();
          floor.clear();
          room.clear();
          category = 'Electrical';
          severity = 'Medium';
          _photoBytes = null;
          _photoName = null;
          _photoContentType = null;
          _draftIssueId = null;
          _draftQueued = false;
          checkedSimilar = false;
          similar = [];
        });
      }
    }
  }

  String _newIssueId() => 'CP-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _loadPreferences() async {
    try {
      final value = await FirebaseIssueRepository.anonymousReportsByDefault();
      if (mounted) setState(() => anonymous = value);
    } catch (error) {
      if (mounted) _showMessage('Could not load report settings: $error');
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _connectivitySubscription?.cancel();
    title.removeListener(_scheduleDraftSave);
    description.removeListener(_scheduleDraftSave);
    building.removeListener(_scheduleDraftSave);
    floor.removeListener(_scheduleDraftSave);
    room.removeListener(_scheduleDraftSave);
    title.dispose();
    description.dispose();
    building.dispose();
    floor.dispose();
    room.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      final contentType = _imageContentType(file.name);
      if (contentType == null) {
        if (mounted) _showMessage('Choose a JPG, PNG, or WebP image.');
        return;
      }
      if (mounted) {
        setState(() {
          _photoBytes = bytes;
          _photoName = file.name;
          _photoContentType = contentType;
        });
        _scheduleDraftSave();
      }
    } catch (error) {
      if (mounted) _showMessage('Could not select photo: $error');
    }
  }

  Future<void> _showPhotoPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Help improve your campus',
          style:
              TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Share a clear description so the right team can help.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Issue title'),
              TextFormField(
                controller: title,
                maxLength: 70,
                decoration: const InputDecoration(
                  hintText: 'e.g. Broken lights in corridor',
                ),
                validator: (v) => (v == null || v.trim().length < 4)
                    ? 'Enter at least 4 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Category'),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  setState(() => category = v ?? category);
                  _scheduleDraftSave();
                },
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Building'),
              TextFormField(
                controller: building,
                decoration: const InputDecoration(
                  hintText: 'e.g. Engineering Building',
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter a building'
                    : null,
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Floor'),
              TextFormField(
                controller: floor,
                decoration: const InputDecoration(
                  hintText: 'e.g. 2nd floor',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a floor or level'
                    : null,
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Room or area'),
              TextFormField(
                controller: room,
                decoration: const InputDecoration(
                  hintText: 'e.g. Room 204 or east corridor',
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter a room or nearby area'
                    : null,
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Describe the issue'),
              TextFormField(
                controller: description,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'What happened? Where exactly?',
                ),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Please add a little more detail'
                    : null,
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Severity'),
              Wrap(
                spacing: 8,
                children: ['Low', 'Medium', 'High', 'Urgent']
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s),
                        selected: severity == s,
                        onSelected: (_) {
                          setState(() => severity = s);
                          _scheduleDraftSave();
                        },
                      ),
                    )
                    .toList(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: anonymous,
                onChanged: (v) async {
                  setState(() => anonymous = v);
                  try {
                    await FirebaseIssueRepository.setAnonymousReportsByDefault(
                        v);
                  } catch (error) {
                    if (mounted) {
                      _showMessage(
                          'Could not save anonymous preference: $error');
                    }
                  }
                  _scheduleDraftSave();
                },
                title: const Text(
                  'Report anonymously',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Your name will not be shown on the public issue card.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: submitting ? null : _showPhotoPicker,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(_photoName == null
                    ? 'Attach a photo (optional, max 5 MB)'
                    : 'Change photo · $_photoName'),
              ),
              if (_photoBytes != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _photoBytes!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _photoBytes = null;
                        _photoName = null;
                        _photoContentType = null;
                      });
                      _scheduleDraftSave();
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove photo'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final fullLocation =
                        '${building.text.trim()} · ${floor.text.trim()} · ${room.text.trim()}';
                    setState(() {
                      similar = widget.onSimilar(category, fullLocation);
                      checkedSimilar = true;
                    });
                    if (similar.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No matching open issue found. You can submit your report.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check similar open issues'),
                ),
              ),
              if (checkedSimilar && similar.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Similar open issues found',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...similar.map(
                        (i) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(i.title),
                          subtitle:
                              Text('${i.id} · ${i.affectedCount} affected'),
                          trailing: TextButton(
                            onPressed: _affectedSubmitting
                                ? null
                                : () async {
                                    setState(() => _affectedSubmitting = true);
                                    try {
                                      final added =
                                          await widget.onMarkAffected(i.id);
                                      if (!added) {
                                        _showMessage(
                                          'You have already marked yourself affected.',
                                        );
                                      } else {
                                        setState(() {
                                          i.affectedCount++;
                                        });
                                        _showMessage(
                                          'Your affected vote was saved.',
                                        );
                                      }
                                    } catch (error) {
                                      _showMessage(
                                        'Could not save your vote: $error',
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                            () => _affectedSubmitting = false);
                                      }
                                    }
                                  },
                            child: const Text('I’m affected'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: submitting ? null : _submitReport,
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(submitting ? 'Submitting...' : 'Submit report'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reports are saved to your campus Firebase database.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
    super.key,
    required this.issue,
    required this.role,
    required this.onChanged,
    required this.onMarkAffected,
    required this.onVerify,
    required this.onToggleFollow,
    required this.checkFollowing,
    required this.checkAffected,
    required this.checkVerification,
    required this.loadStaffUsers,
    required this.watchWorkUpdates,
    required this.addWorkUpdate,
    required this.uploadPhoto,
    required this.onMessage,
  });
  final CampusIssue issue;
  final String role;
  final Future<void> Function(CampusIssue) onChanged;
  final Future<bool> Function(String) onMarkAffected;
  final Future<bool> Function(String, String) onVerify;
  final Future<bool> Function(String) onToggleFollow;
  final Future<bool> Function(String) checkFollowing;
  final Future<bool> Function(String) checkAffected;
  final Future<bool> Function(String) checkVerification;
  final Future<List<Map<String, dynamic>>> Function() loadStaffUsers;
  final Stream<List<WorkUpdate>> Function(String) watchWorkUpdates;
  final Future<void> Function({
    required String issueId,
    required String note,
    required List<String> completedSteps,
    required List<String> nextSteps,
    String? photoUrl,
  }) addWorkUpdate;
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) uploadPhoto;
  final void Function(String) onMessage;
  @override
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  CampusIssue get issue => widget.issue;
  bool get student => widget.role == 'Student';
  bool get admin => widget.role == 'Authority / Admin';
  bool get staff => widget.role == 'Maintenance Staff';
  bool get assignedVerifier =>
      staff &&
      issue.verificationAssignedTo == FirebaseAuth.instance.currentUser?.uid &&
      issue.status == IssueStatus.verificationRequested;
  bool get assignedWorker =>
      staff && issue.assignedTo == FirebaseAuth.instance.currentUser?.uid;
  bool _followLoading = false;
  bool _hasConfirmedAffected = false;
  bool _verificationRecorded = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
    _loadVerificationState();
  }

  Future<void> _loadVerificationState() async {
    if (!student) return;
    try {
      final state = await Future.wait([
        widget.checkAffected(issue.id),
        widget.checkVerification(issue.id),
      ]);
      if (!mounted) return;
      setState(() {
        _hasConfirmedAffected = state[0];
        _verificationRecorded = state[1];
      });
    } catch (error) {
      widget.onMessage('Could not load verification eligibility: $error');
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final following = await widget.checkFollowing(issue.id);
      if (mounted) setState(() => issue.following = following);
    } catch (error) {
      widget.onMessage('Could not load follow status: $error');
    }
  }

  Future<void> _toggleFollowing() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    try {
      final following = await widget.onToggleFollow(issue.id);
      if (mounted) setState(() => issue.following = following);
      widget.onMessage(
        following ? 'Following issue updates.' : 'Unfollowed issue.',
      );
    } catch (error) {
      widget.onMessage('Could not update follow status: $error');
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(issue.id)),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE7F7FF), Color(0xFFEDEBFF)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 14,
                  top: 12,
                  child: _StatusPill(issue.status),
                ),
                Center(
                  child: Icon(
                    _issueCategoryIcon(issue.category),
                    size: 70,
                    color: brand.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
          if (issue.imageUrl != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                issue.imageUrl!,
                height: 240,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ErrorBanner(
                  message: 'Could not load this issue photo.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: Text(issue.title,
                    style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: ink))),
            _StatusPill(issue.status)
          ]),
          const SizedBox(height: 10),
          Text(issue.description,
              style: const TextStyle(color: muted, height: 1.5)),
          const SizedBox(height: 18),
          _detailRow(Icons.category_outlined, 'Category', issue.category),
          _detailRow(Icons.location_on_outlined, 'Location', issue.location),
          _detailRow(Icons.flag_outlined, 'Severity', issue.severity),
          _detailRow(
            Icons.priority_high,
            'Priority',
            '${issue.priority}${issue.priorityOverride.isNotEmpty ? ' · Admin override' : ' · automatic'}',
          ),
          if (issue.department.isNotEmpty)
            _detailRow(Icons.groups_outlined, 'Department', issue.department),
          if (issue.assignedTo.isNotEmpty)
            _detailRow(
              Icons.engineering_outlined,
              'Assigned to',
              issue.assigneeDisplayName,
            ),
          if (issue.verificationAssignedTo.isNotEmpty)
            _detailRow(
              Icons.fact_check_outlined,
              'Verifier',
              issue.verifierDisplayName,
            ),
          if (issue.verificationNote.isNotEmpty)
            _detailRow(
              Icons.assignment_turned_in_outlined,
              'Inspection note',
              issue.verificationNote,
            ),
          if (issue.expectedBy != null)
            _detailRow(
              Icons.schedule_outlined,
              'Expected by',
              '${issue.expectedBy!.day}/${issue.expectedBy!.month}/${issue.expectedBy!.year}',
            ),
          _detailRow(Icons.people_alt_outlined, 'Affected students',
              '${issue.affectedCount}'),
          _detailRow(Icons.person_outline, 'Reported by',
              issue.isAnonymous ? 'Anonymous' : issue.reporter),
          if (issue.hasBreachedSla)
            const _ErrorBanner(
                message: 'The expected response time has passed.'),
          if (issue.resolutionSummary.isNotEmpty)
            _detailRow(
              Icons.checklist_outlined,
              'Resolution',
              issue.resolutionSummary,
            ),
          if (issue.resolutionPhotoUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'Resolution photo',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                issue.resolutionPhotoUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ErrorBanner(
                  message: 'Could not load the resolution photo.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text('Issue timeline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...issue.history.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, size: 19, color: brand),
                const SizedBox(width: 10),
                Expanded(child: Text(h, style: const TextStyle(height: 1.4)))
              ]))),
          const SizedBox(height: 14),
          _workProgressSection(),
          if (student && issue.isOpen) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final added = await widget.onMarkAffected(issue.id);
                    if (!added) {
                      widget.onMessage(
                          'You have already marked yourself affected.');
                      return;
                    }
                    setState(() {
                      issue.affectedCount++;
                      _hasConfirmedAffected = true;
                    });
                    widget.onMessage('Your affected vote was saved.');
                  } catch (error) {
                    widget.onMessage('Could not save your vote: $error');
                  }
                },
                icon: const Icon(Icons.people_outline),
                label: Text('I’m affected · ${issue.affectedCount}')),
            OutlinedButton.icon(
                onPressed: _followLoading ? null : _toggleFollowing,
                icon: Icon(issue.following
                    ? Icons.notifications_active
                    : Icons.notifications_none),
                label: Text(
                    issue.following ? 'Following updates' : 'Follow issue')),
          ],
          if (admin) ...[
            const SizedBox(height: 18),
            const Text('Admin actions',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            if (issue.status == IssueStatus.reported ||
                issue.status == IssueStatus.rejected)
              OutlinedButton.icon(
                onPressed: _requestVerificationDialog,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Request staff verification'),
              ),
            const SizedBox(height: 10),
            if (issue.status == IssueStatus.verified ||
                issue.status == IssueStatus.assigned)
              OutlinedButton.icon(
                  onPressed: () => _assignDialog(context),
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('Assign repair work')),
            OutlinedButton.icon(
              onPressed: _priorityDialog,
              icon: const Icon(Icons.tune),
              label: const Text('Set priority override'),
            ),
          ],
          if (staff && issue.isOpen) ...[
            const SizedBox(height: 18),
            const Text('Staff actions',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (assignedVerifier) ...[
                _action('Confirm issue is damaged', IssueStatus.verified),
                _action('Mark as not damaged', IssueStatus.rejected),
              ],
              if (assignedWorker && issue.status == IssueStatus.inProgress)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Post each repair step so students and staff can follow the work.',
                    style: TextStyle(color: muted),
                  ),
                ),
              if (assignedWorker && issue.status == IssueStatus.assigned)
                _action('Start repair work', IssueStatus.inProgress),
              if (assignedWorker && issue.status == IssueStatus.inProgress)
                FilledButton.tonal(
                  onPressed: _addWorkUpdate,
                  child: const Text('Post progress update'),
                ),
              if (assignedWorker && issue.status == IssueStatus.inProgress)
                _action('Submit completion', IssueStatus.resolved),
            ]),
          ],
          if (student && issue.status == IssueStatus.resolved) ...[
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8E8F1))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Is the issue fixed?',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      if (!_hasConfirmedAffected)
                        const Text(
                          'Only students who confirmed being affected before resolution can vote.',
                          style: TextStyle(color: muted),
                        )
                      else if (_verificationRecorded)
                        const Text(
                          'Your verification has already been recorded.',
                          style: TextStyle(color: muted),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: ['Yes, fixed', 'Still exists', 'Not sure']
                              .map(
                                (vote) => OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      final recorded = await widget.onVerify(
                                        issue.id,
                                        vote,
                                      );
                                      if (!recorded) {
                                        widget.onMessage(
                                          'You have already verified this issue, or you had not confirmed being affected.',
                                        );
                                        if (mounted) {
                                          setState(() =>
                                              _verificationRecorded = true);
                                        }
                                        return;
                                      }
                                      setState(() {
                                        _verificationRecorded = true;
                                        issue.verificationVotes[FirebaseAuth
                                            .instance.currentUser!.uid] = vote;
                                        issue.verificationCount++;
                                        if (vote == 'Still exists') {
                                          issue.stillExistsVotes++;
                                        }
                                        issue.history = [
                                          ...issue.history,
                                          'Student verification: $vote',
                                        ];
                                        if (issue.hasMajorityStillExistsVotes) {
                                          issue.status = IssueStatus.inProgress;
                                          issue.history = [
                                            ...issue.history,
                                            'Reopened after student verification',
                                          ];
                                        }
                                      });
                                      widget.onMessage(
                                          'Your verification was saved.');
                                    } catch (error) {
                                      widget.onMessage(
                                        'Could not save verification: $error',
                                      );
                                    }
                                  },
                                  child: Text(vote),
                                ),
                              )
                              .toList(),
                        ),
                    ])),
          ],
        ]),
      );

  Widget _workProgressSection() => StreamBuilder<List<WorkUpdate>>(
        stream: widget.watchWorkUpdates(issue.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorBanner(
              message: 'Could not load staff progress: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }
          final updates = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Repair progress',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...updates.map(
                (update) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0xFFEDEBFF),
                              child: Icon(
                                Icons.engineering_outlined,
                                size: 17,
                                color: brand,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                update.authorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              update.createdAt == null
                                  ? 'Just now'
                                  : _formatUpdateDate(update.createdAt!),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        if (update.note.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(update.note),
                        ],
                        if (update.photoUrl != null &&
                            update.photoUrl!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              update.photoUrl!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const _ErrorBanner(
                                message: 'Could not load this repair photo.',
                              ),
                            ),
                          ),
                        ],
                        if (update.completedSteps.isNotEmpty)
                          _stepsList(
                            'Completed',
                            update.completedSteps,
                            Icons.check_circle_outline,
                            const Color(0xFF138A68),
                          ),
                        if (update.nextSteps.isNotEmpty)
                          _stepsList(
                            'Still to do',
                            update.nextSteps,
                            Icons.pending_outlined,
                            const Color(0xFFB36B00),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _stepsList(
    String title,
    List<String> steps,
    IconData icon,
    Color color,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            ...steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 17, color: color),
                    const SizedBox(width: 7),
                    Expanded(child: Text(step)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  String _formatUpdateDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} · '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  Future<void> _addWorkUpdate() async {
    final values = await showDialog<WorkProgressDraft>(
      context: context,
      builder: (context) => const WorkProgressDialog(),
    );
    if (!mounted || values == null) return;
    try {
      await widget.addWorkUpdate(
        issueId: issue.id,
        note: values.note,
        completedSteps: values.completedSteps.split('\n'),
        nextSteps: values.nextSteps.split('\n'),
        photoUrl:
            values.photo == null ? null : await _uploadPhoto(values.photo!),
      );
      widget.onMessage('Progress update posted.');
    } catch (error) {
      widget.onMessage('Could not post progress update: $error');
    }
  }

  Future<String> _uploadPhoto(XFile photo) async {
    final contentType = _imageContentType(photo.name);
    if (contentType == null) {
      throw ArgumentError('Choose a JPG, PNG, or WebP image.');
    }
    final bytes = await photo.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    return widget.uploadPhoto(
      bytes: bytes,
      fileName: photo.name,
      contentType: contentType,
    );
  }

  Widget _action(String label, IssueStatus status) => FilledButton.tonal(
      onPressed: () async {
        String? resolutionSummary;
        String? resolutionPhotoUrl;
        String? inspectionNote;
        if (status == IssueStatus.resolved && staff) {
          final completion = await _requestResolutionSummary();
          if (completion == null) return;
          resolutionSummary = completion.summary;
          if (completion.photo != null) {
            try {
              resolutionPhotoUrl = await _uploadPhoto(completion.photo!);
            } catch (error) {
              widget.onMessage('Could not upload resolution photo: $error');
              return;
            }
          }
        }
        if (assignedVerifier &&
            (status == IssueStatus.verified ||
                status == IssueStatus.rejected)) {
          inspectionNote = await _requestInspectionNote(status);
          if (inspectionNote == null) return;
        }
        if (!mounted) return;
        final previousStatus = issue.status;
        final previousHistory = issue.history;
        final previousResolutionSummary = issue.resolutionSummary;
        final previousResolutionPhotoUrl = issue.resolutionPhotoUrl;
        final previousInspectionNote = issue.verificationNote;
        final previousVerifier = issue.verificationAssignedTo;
        final previousVerifierName = issue.verificationAssignedToName;
        final wasAssignedVerifier = assignedVerifier;
        setState(() {
          issue.status = status;
          if (resolutionSummary != null) {
            issue.resolutionSummary = resolutionSummary;
          }
          if (resolutionPhotoUrl != null) {
            issue.resolutionPhotoUrl = resolutionPhotoUrl;
          } else if (status == IssueStatus.resolved) {
            issue.resolutionPhotoUrl = '';
          }
          if (inspectionNote != null) {
            issue.verificationNote = inspectionNote;
          }
          if (wasAssignedVerifier &&
              (status == IssueStatus.verified ||
                  status == IssueStatus.rejected)) {
            issue.verificationAssignedTo = '';
            issue.verificationAssignedToName = '';
          }
          issue.history = [
            ...issue.history,
            if (status == IssueStatus.verified && wasAssignedVerifier)
              'Staff inspection confirmed the issue · $inspectionNote'
            else if (status == IssueStatus.rejected && wasAssignedVerifier)
              'Staff inspection found no damage · $inspectionNote'
            else
              '${status.label} · just now',
          ];
        });
        try {
          await widget.onChanged(issue);
          widget.onMessage('Status changed to ${status.label}.');
        } catch (error) {
          setState(() {
            issue.status = previousStatus;
            issue.history = previousHistory;
            issue.resolutionSummary = previousResolutionSummary;
            issue.resolutionPhotoUrl = previousResolutionPhotoUrl;
            issue.verificationNote = previousInspectionNote;
            issue.verificationAssignedTo = previousVerifier;
            issue.verificationAssignedToName = previousVerifierName;
          });
          widget.onMessage('Could not update issue: $error');
        }
      },
      child: Text(label));

  Future<String?> _requestInspectionNote(IssueStatus result) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => InspectionNoteDialog(
        result: result,
        initialNote: issue.verificationNote,
      ),
    );
    if (note == null) return null;
    return note;
  }

  Future<void> _requestVerificationDialog() async {
    List<Map<String, dynamic>> staffUsers;
    try {
      staffUsers = await widget.loadStaffUsers();
    } catch (error) {
      widget.onMessage('Could not load staff accounts: $error');
      return;
    }
    if (!mounted) return;
    if (staffUsers.isEmpty) {
      widget.onMessage(
        'Add a staff member from Profile → Manage accounts before requesting an inspection.',
      );
      return;
    }
    String? selectedUid;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request staff inspection'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedUid,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Inspecting staff'),
            items: staffUsers
                .map(
                  (user) => DropdownMenuItem(
                    value: user['uid'] as String,
                    child: Text(
                      user['displayName'] as String? ??
                          user['email'] as String? ??
                          'Staff member',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (uid) => setDialogState(() => selectedUid = uid),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedUid == null
                  ? null
                  : () {
                      final selected = staffUsers.firstWhere(
                        (user) => user['uid'] == selectedUid,
                      );
                      Navigator.pop(context, {
                        'uid': selectedUid!,
                        'name': selected['displayName'] as String? ??
                            selected['email'] as String? ??
                            'Staff member',
                      });
                    },
              child: const Text('Request verification'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final previousStatus = issue.status;
    final previousVerifier = issue.verificationAssignedTo;
    final previousVerifierName = issue.verificationAssignedToName;
    final previousHistory = issue.history;
    setState(() {
      issue.status = IssueStatus.verificationRequested;
      issue.verificationAssignedTo = result['uid']!;
      issue.verificationAssignedToName = result['name']!;
      issue.history = [
        ...issue.history,
        'Staff inspection requested for ${result['name']} · just now',
      ];
    });
    try {
      await widget.onChanged(issue);
      widget.onMessage('Inspection requested from ${result['name']}.');
    } catch (error) {
      setState(() {
        issue.status = previousStatus;
        issue.verificationAssignedTo = previousVerifier;
        issue.verificationAssignedToName = previousVerifierName;
        issue.history = previousHistory;
      });
      widget.onMessage('Could not request staff verification: $error');
    }
  }

  Future<({String summary, XFile? photo})?> _requestResolutionSummary() async {
    final result = await showDialog<({String summary, XFile? photo})>(
      context: context,
      builder: (context) => ResolutionSummaryDialog(
        initialSummary: issue.resolutionSummary,
      ),
    );
    return result;
  }

  Future<void> _priorityDialog() async {
    final options = ['Automatic', 'Low', 'Medium', 'High', 'Urgent'];
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Override automatic priority'),
        children: options
            .map(
              (option) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, option),
                child: Text(
                  issue.priorityOverride.isEmpty
                      ? option == 'Automatic'
                          ? '$option · current'
                          : option
                      : issue.priorityOverride == option
                          ? '$option · current'
                          : option,
                ),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || selection == null) return;
    final previousOverride = issue.priorityOverride;
    final previousHistory = issue.history;
    setState(() {
      issue.priorityOverride = selection == 'Automatic' ? '' : selection;
      issue.history = [
        ...issue.history,
        'Priority ${selection == 'Automatic' ? 'returned to automatic' : 'set to $selection'} · just now',
      ];
    });
    try {
      await widget.onChanged(issue);
      widget.onMessage('Priority updated.');
    } catch (error) {
      setState(() {
        issue.priorityOverride = previousOverride;
        issue.history = previousHistory;
      });
      widget.onMessage('Could not update priority: $error');
    }
  }

  Future<void> _assignDialog(BuildContext context) async {
    List<Map<String, dynamic>> staffUsers;
    try {
      staffUsers = await widget.loadStaffUsers();
    } catch (error) {
      widget.onMessage('Could not load staff accounts: $error');
      return;
    }
    if (!context.mounted) return;
    if (staffUsers.isEmpty) {
      widget.onMessage(
        'Add a staff member from Profile → Manage accounts, then assign this issue again.',
      );
      return;
    }
    String? selectedUid = staffUsers
        .where((user) => user['uid'] == issue.assignedTo)
        .firstOrNull?['uid'] as String?;
    String department = _departments.contains(issue.department)
        ? issue.department
        : _defaultDepartment(issue.category);
    DateTime expectedBy =
        issue.expectedBy ?? DateTime.now().add(const Duration(days: 3));
    final result = await showDialog<(String, String, DateTime)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign maintenance staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedUid,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Staff member'),
                items: staffUsers
                    .map((user) => DropdownMenuItem(
                          value: user['uid'] as String,
                          child: Text(
                            user['displayName'] as String? ??
                                user['email'] as String? ??
                                'Staff member',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (uid) => setDialogState(() => selectedUid = uid),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: department,
                decoration:
                    const InputDecoration(labelText: 'Responsible department'),
                items: _departments
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => department = value ?? department),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: expectedBy.isBefore(DateTime.now())
                        ? DateTime.now()
                        : expectedBy,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setDialogState(() {
                      expectedBy =
                          DateTime(date.year, date.month, date.day, 17);
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  'Expected by ${expectedBy.day}/${expectedBy.month}/${expectedBy.year}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedUid == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        (selectedUid!, department, expectedBy),
                      ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      final previousAssignee = issue.assignedTo;
      final previousAssigneeName = issue.assignedToName;
      final previousStatus = issue.status;
      final previousVerifier = issue.verificationAssignedTo;
      final previousVerifierName = issue.verificationAssignedToName;
      final previousDepartment = issue.department;
      final previousExpectedBy = issue.expectedBy;
      final previousHistory = issue.history;
      setState(() {
        issue.assignedTo = result.$1;
        final assignedStaff = staffUsers.firstWhere(
          (user) => user['uid'] == result.$1,
        );
        issue.assignedToName = assignedStaff['displayName'] as String? ??
            assignedStaff['email'] as String? ??
            'Maintenance staff';
        issue.verificationAssignedTo = '';
        issue.verificationAssignedToName = '';
        issue.department = result.$2;
        issue.expectedBy = result.$3;
        issue.status = IssueStatus.assigned;
        issue.history = [
          ...issue.history,
          'Repair assigned to ${issue.assignedToName} · ${result.$2} · ETA ${result.$3.day}/${result.$3.month}/${result.$3.year}',
        ];
      });
      try {
        await widget.onChanged(issue);
        widget.onMessage('Assigned to maintenance staff.');
      } catch (error) {
        setState(() {
          issue.assignedTo = previousAssignee;
          issue.assignedToName = previousAssigneeName;
          issue.status = previousStatus;
          issue.verificationAssignedTo = previousVerifier;
          issue.verificationAssignedToName = previousVerifierName;
          issue.department = previousDepartment;
          issue.expectedBy = previousExpectedBy;
          issue.history = previousHistory;
        });
        widget.onMessage('Could not assign issue: $error');
      }
    }
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 19, color: brand),
        const SizedBox(width: 10),
        SizedBox(
            width: 125,
            child: Text(label,
                style: const TextStyle(color: muted, fontSize: 13))),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)))
      ]));
}

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key, required this.issues});
  final List<CampusIssue> issues;
  @override
  Widget build(BuildContext context) {
    final open = issues.where((i) => i.isOpen).length;
    final resolved =
        issues.where((i) => i.status == IssueStatus.resolved).length;
    final byCategory = <String, int>{};
    final byBuilding = <String, int>{};
    final recurrenceGroups = <String, int>{};
    final resolutionDurations = <int>[];
    final slaIssues = <CampusIssue>[];
    var recurringIncidents = 0;
    for (final issue in issues) {
      byCategory.update(issue.category, (currentCount) => currentCount + 1,
          ifAbsent: () => 1);
      final building = issue.building.isNotEmpty
          ? issue.building
          : issue.location.split(' · ').first.trim();
      byBuilding.update(
        building,
        (currentCount) => currentCount + 1,
        ifAbsent: () => 1,
      );
      final recurrenceKey =
          '${issue.category.toLowerCase()}|${issue.location.toLowerCase()}';
      recurrenceGroups.update(recurrenceKey, (currentCount) => currentCount + 1,
          ifAbsent: () => 1);
      if (issue.createdAt != null && issue.resolvedAt != null) {
        resolutionDurations
            .add(issue.resolvedAt!.difference(issue.createdAt!).inHours);
      }
      if (issue.expectedBy != null &&
          (issue.isOpen || issue.resolvedAt != null)) {
        slaIssues.add(issue);
      }
    }
    recurringIncidents = recurrenceGroups.values
        .where((groupSize) => groupSize > 1)
        .fold(0, (total, groupSize) => total + groupSize);
    final missedSla = slaIssues.where((issue) {
      final completion = issue.resolvedAt;
      return completion != null
          ? completion.isAfter(issue.expectedBy!)
          : issue.hasBreachedSla;
    }).length;
    final slaRate = slaIssues.isEmpty
        ? 'N/A'
        : '${((slaIssues.length - missedSla) / slaIssues.length * 100).round()}%';
    final averageResolutionHours = resolutionDurations.isEmpty
        ? null
        : (resolutionDurations.reduce((a, b) => a + b) /
                resolutionDurations.length)
            .round();
    final maxValue = [open, resolved, issues.length - open - resolved]
        .reduce((a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1, 100);
    return Scaffold(
        appBar: AppBar(title: const Text('Campus analytics')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          const Text('Issue overview',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
          const SizedBox(height: 6),
          const Text(
              'Live issue counts from the campus reports available to your account.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 20),
          _metric(
              'Total issues', issues.length.toString(), Icons.list_alt, brand),
          _metric('Open issues', open.toString(), Icons.pending_actions,
              const Color(0xFFDB8B21)),
          _metric('Resolved issues', resolved.toString(), Icons.task_alt,
              const Color(0xFF159A78)),
          _metric(
            'Average resolution time',
            averageResolutionHours == null
                ? 'N/A'
                : '${averageResolutionHours}h',
            Icons.timer_outlined,
            const Color(0xFF1D8BC1),
          ),
          _metric(
            'SLA on-time rate',
            slaRate,
            Icons.speed_outlined,
            const Color(0xFF159A78),
          ),
          _metric(
            'Recurring incidents',
            recurringIncidents.toString(),
            Icons.repeat,
            const Color(0xFFDB8B21),
          ),
          const SizedBox(height: 20),
          const Text('Status distribution',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          ...[
            ('Open', open, const Color(0xFF6D5CE8)),
            ('Resolved', resolved, const Color(0xFF159A78)),
            ('Other', issues.length - open - resolved, const Color(0xFFDB8B21)),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: Text(e.$1)), Text('${e.$2}')]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: e.$2 / maxValue,
                      minHeight: 9,
                      color: e.$3,
                      backgroundColor: e.$3.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _breakdown('Issues by category', byCategory),
          _breakdown('Issues by building', byBuilding),
        ]));
  }

  Widget _breakdown(String title, Map<String, int> counts) {
    final values = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxCount = values.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        ...values.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value}'),
                  ],
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: entry.value / maxCount,
                  minHeight: 7,
                  color: brand,
                  backgroundColor: brand.withValues(alpha: 0.12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String title, String value, IconData icon, Color color) =>
      Card(
          child: ListTile(
              leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color)),
              title: Text(title),
              trailing: Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800))));
}

class IssueTile extends StatelessWidget {
  const IssueTile({super.key, required this.issue, required this.onTap});
  final CampusIssue issue;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 66,
                        height: 72,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDEBFF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: issue.imageUrl == null
                            ? Icon(_issueCategoryIcon(issue.category),
                                color: brand, size: 30)
                            : Image.network(
                                issue.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(_issueCategoryIcon(issue.category),
                                        color: brand, size: 30),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: Text(issue.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15))),
                                  const SizedBox(width: 6),
                                  _StatusPill(issue.status)
                                ]),
                            const SizedBox(height: 5),
                            Text(issue.location,
                                style: const TextStyle(
                                    color: muted, fontSize: 12)),
                            if (issue.assignedTo.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.engineering_outlined,
                                    size: 14,
                                    color: brand,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Assigned to ${issue.assigneeDisplayName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: brand,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.people_outline,
                                  size: 15, color: muted),
                              const SizedBox(width: 4),
                              Text('${issue.affectedCount} affected',
                                  style: const TextStyle(
                                      color: muted, fontSize: 12)),
                              const Spacer(),
                              Text('${issue.priority} priority',
                                  style: TextStyle(
                                      color: issue.priority == 'Urgent' ||
                                              issue.priority == 'High'
                                          ? Colors.redAccent
                                          : muted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12))
                            ]),
                          ])),
                    ]))),
      );
}

class InspectionNoteDialog extends StatefulWidget {
  const InspectionNoteDialog({
    super.key,
    required this.result,
    required this.initialNote,
  });

  final IssueStatus result;
  final String initialNote;

  @override
  State<InspectionNoteDialog> createState() => _InspectionNoteDialogState();
}

class _InspectionNoteDialogState extends State<InspectionNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.result == IssueStatus.verified
              ? 'Confirm issue inspection'
              : 'Explain inspection result',
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          maxLength: 300,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What did you inspect and find?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _controller.text.trim().length < 5
                ? null
                : () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Submit inspection'),
          ),
        ],
      );
}

typedef WorkProgressDraft = ({
  String note,
  String completedSteps,
  String nextSteps,
  XFile? photo,
});

class WorkProgressDialog extends StatefulWidget {
  const WorkProgressDialog({super.key, this.pickPhoto});

  final Future<XFile?> Function()? pickPhoto;

  @override
  State<WorkProgressDialog> createState() => _WorkProgressDialogState();
}

class _WorkProgressDialogState extends State<WorkProgressDialog> {
  final _note = TextEditingController();
  final _completedSteps = TextEditingController();
  final _nextSteps = TextEditingController();
  XFile? _photo;
  String? _photoError;
  bool _pickingPhoto = false;

  bool get _canSubmit =>
      _note.text.trim().length >= 3 &&
      (_completedSteps.text.trim().isNotEmpty ||
          _nextSteps.text.trim().isNotEmpty) &&
      !_pickingPhoto;

  @override
  void dispose() {
    _note.dispose();
    _completedSteps.dispose();
    _nextSteps.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() {
      _pickingPhoto = true;
      _photoError = null;
    });
    try {
      final photo = await (widget.pickPhoto?.call() ??
          ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
            maxWidth: 1200,
          ));
      if (!mounted || photo == null) return;
      setState(() => _photo = photo);
    } catch (error) {
      if (mounted) {
        setState(() => _photoError = 'Could not select photo: $error');
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Post repair progress'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _note,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Progress note',
                    hintText: 'Briefly describe the work so far',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _completedSteps,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Completed steps',
                    hintText: 'One step per line',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nextSteps,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Remaining / next steps',
                    hintText: 'One step per line',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickingPhoto ? null : _choosePhoto,
                  icon: _pickingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _photo == null
                        ? 'Add repair photo'
                        : 'Photo: ${_photo!.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_photo != null)
                  TextButton(
                    onPressed: _pickingPhoto
                        ? null
                        : () => setState(() => _photo = null),
                    child: const Text('Remove photo'),
                  ),
                if (_photoError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _photoError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _pickingPhoto ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canSubmit
                ? () => Navigator.pop(
                      context,
                      (
                        note: _note.text.trim(),
                        completedSteps: _completedSteps.text,
                        nextSteps: _nextSteps.text,
                        photo: _photo,
                      ),
                    )
                : null,
            child: const Text('Post update'),
          ),
        ],
      );
}

class ResolutionSummaryDialog extends StatefulWidget {
  const ResolutionSummaryDialog({
    super.key,
    required this.initialSummary,
    this.pickPhoto,
  });

  final String initialSummary;
  final Future<XFile?> Function()? pickPhoto;

  @override
  State<ResolutionSummaryDialog> createState() =>
      _ResolutionSummaryDialogState();
}

class _ResolutionSummaryDialogState extends State<ResolutionSummaryDialog> {
  late final TextEditingController _summary;
  XFile? _photo;
  String? _photoError;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _summary = TextEditingController(text: widget.initialSummary);
  }

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() {
      _pickingPhoto = true;
      _photoError = null;
    });
    try {
      final photo = await (widget.pickPhoto?.call() ??
          ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
            maxWidth: 1200,
          ));
      if (!mounted || photo == null) return;
      setState(() => _photo = photo);
    } catch (error) {
      if (mounted) {
        setState(() => _photoError = 'Could not select photo: $error');
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Describe the completed work'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _summary,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Resolution summary',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickingPhoto ? null : _choosePhoto,
              icon: _pickingPhoto
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _photo == null
                    ? 'Add completion photo'
                    : 'Photo: ${_photo!.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_photo != null)
              TextButton(
                onPressed:
                    _pickingPhoto ? null : () => setState(() => _photo = null),
                child: const Text('Remove photo'),
              ),
            if (_photoError != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _photoError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _pickingPhoto ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _summary.text.trim().length < 10 || _pickingPhoto
                ? null
                : () => Navigator.pop(
                      context,
                      (summary: _summary.text.trim(), photo: _photo),
                    ),
            child: const Text('Submit completion'),
          ),
        ],
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final IssueStatus status;
  @override
  Widget build(BuildContext context) {
    final color = status == IssueStatus.resolved
        ? const Color(0xFF138A68)
        : status == IssueStatus.rejected
            ? Colors.redAccent
            : status == IssueStatus.inProgress
                ? const Color(0xFFB36B00)
                : brand;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20)),
        child: Text(status.label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final String time;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: CircleAvatar(
              backgroundColor: const Color(0xFFEDEBFF),
              child: Icon(icon, color: brand)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
              padding: const EdgeInsets.only(top: 5), child: Text(body)),
          trailing:
              Text(time, style: const TextStyle(color: muted, fontSize: 10)),
          onTap: onTap));
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: ink)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(children: [
        const Icon(Icons.search_off, size: 45, color: muted),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: muted))
      ]));
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEEE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message, style: const TextStyle(color: Colors.redAccent)),
      );
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.repository});

  final FirebaseIssueRepository repository;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoContentType;
  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.repository
          .getUserProfile(FirebaseAuth.instance.currentUser!.uid);
      _name.text = profile['displayName'] as String? ?? '';
      _photoUrl = profile['photoUrl'] as String?;
    } catch (error) {
      if (mounted) _showMessage('Could not load profile: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final contentType = _imageContentType(file.name);
      if (bytes.lengthInBytes > 5 * 1024 * 1024 || contentType == null) {
        if (mounted) {
          _showMessage('Choose a JPG, PNG, or WebP image smaller than 5 MB.');
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoName = file.name;
        _photoContentType = contentType;
      });
    } catch (error) {
      _showMessage('Could not select profile photo: $error');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_photoBytes != null &&
          _photoName != null &&
          _photoContentType != null) {
        _photoUrl = await widget.repository.uploadProfilePhoto(
          bytes: _photoBytes!,
          fileName: _photoName!,
          contentType: _photoContentType!,
        );
      }
      await widget.repository.updateProfile(
        displayName: _name.text,
        photoUrl: _photoUrl,
      );
      if (!mounted) return;
      _showMessage('Profile updated.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) _showMessage('Could not save profile: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: const Color(0xFFE7E5FF),
                          foregroundImage: _photoBytes != null
                              ? MemoryImage(_photoBytes!)
                              : _photoUrl == null
                                  ? null
                                  : NetworkImage(_photoUrl!) as ImageProvider,
                          child: _photoBytes == null && _photoUrl == null
                              ? const Icon(
                                  Icons.person_outline,
                                  size: 48,
                                  color: brand,
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: IconButton.filled(
                            onPressed: _saving ? null : _choosePhoto,
                            icon: const Icon(Icons.camera_alt_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 2
                                  ? 'Enter at least 2 characters.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue:
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.email_outlined),
                            helperText:
                                'Email changes are managed through account verification.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save profile'),
                  ),
                ],
              ),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.repository});

  final FirebaseIssueRepository repository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _savingPush = false;
  bool _anonymousDefault = false;
  bool _loadingAnonymous = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final value = await FirebaseIssueRepository.anonymousReportsByDefault();
    if (mounted) {
      setState(() {
        _anonymousDefault = value;
        _loadingAnonymous = false;
      });
    }
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _savingPush = true);
    try {
      await PushNotificationService.instance.setEnabled(value);
      if (mounted) {
        _showMessage(
          value ? 'Push alerts enabled.' : 'Push alerts disabled.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Could not update push settings: $error');
    } finally {
      if (mounted) setState(() => _savingPush = false);
    }
  }

  Future<void> _toggleAnonymous(bool value) async {
    setState(() => _anonymousDefault = value);
    try {
      await FirebaseIssueRepository.setAnonymousReportsByDefault(value);
    } catch (error) {
      if (mounted) _showMessage('Could not save preference: $error');
    }
  }

  Future<void> _resetPassword() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: FirebaseAuth.instance.currentUser!.email!,
      );
      if (mounted) _showMessage('Password reset email sent.');
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(error.message ?? 'Could not send reset email.');
    } catch (error) {
      if (mounted) _showMessage('Could not send reset email: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.repository.watchUserProfile(
            FirebaseAuth.instance.currentUser!.uid,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorBanner(
                message: 'Could not load settings: ${snapshot.error}',
              );
            }
            final profile = snapshot.data?.data();
            if (profile == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final pushEnabled = profile['pushEnabled'] as bool? ?? false;
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pushEnabled,
                  onChanged: _savingPush ? null : _togglePush,
                  title: const Text('Push notifications'),
                  subtitle: const Text(
                    'Get assignment and issue status alerts on this device.',
                  ),
                  secondary: _savingPush
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                ),
                const Divider(height: 30),
                const Text(
                  'Privacy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _anonymousDefault,
                  onChanged: _loadingAnonymous ? null : _toggleAnonymous,
                  title: const Text('Report anonymously by default'),
                  subtitle: const Text(
                    'Your identity remains restricted to authorized campus staff.',
                  ),
                  secondary: const Icon(Icons.visibility_off_outlined),
                ),
                const Divider(height: 30),
                const Text(
                  'Account security',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('Change password'),
                  subtitle: const Text('Send a secure password reset email.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _resetPassword,
                ),
              ],
            );
          },
        ),
      );
}

class ManageAccountsPage extends StatefulWidget {
  const ManageAccountsPage({super.key, required this.repository});

  final FirebaseIssueRepository repository;

  @override
  State<ManageAccountsPage> createState() => _ManageAccountsPageState();
}

class _CreateStaffDialog extends StatefulWidget {
  const _CreateStaffDialog({required this.repository});

  final FirebaseIssueRepository repository;

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String _department = _departments.first;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createStaffAccount(
        displayName: _name.text,
        email: _email.text,
        password: _password.text,
        department: _department,
        phone: _phone.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not create staff account: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add staff member'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                            ? 'Enter the staff member name.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => value == null ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(value.trim())
                        ? 'Enter a valid email address.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: _departments
                        .map(
                          (department) => DropdownMenuItem(
                            value: department,
                            child: Text(department),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _department = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact number (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Temporary password',
                      helperText: 'At least 6 characters; share it securely.',
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _hidePassword = !_hidePassword,
                        ),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.length < 6
                        ? 'Use at least 6 characters.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: _hidePassword,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                    validator: (value) => value != _password.text
                        ? 'Passwords do not match.'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create staff account'),
          ),
        ],
      );
}

class _ManageAccountsPageState extends State<ManageAccountsPage> {
  String? _updatingUid;

  Future<void> _createStaff() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateStaffDialog(repository: widget.repository),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff account created successfully.')),
      );
    }
  }

  Future<void> _changeRole(String uid, String role) async {
    setState(() => _updatingUid = uid);
    try {
      await widget.repository.updateUserRole(uid, role);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account role updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update account role: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Manage accounts')),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.repository.watchUsers(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorBanner(
                message: 'Could not load accounts: ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final accounts = snapshot.data!;
            if (accounts.isEmpty) {
              return const _EmptyState(
                title: 'No accounts found',
                subtitle: 'Student accounts will appear here after sign-up.',
              );
            }
            final currentUid = FirebaseAuth.instance.currentUser!.uid;
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Create staff accounts directly or change the role of an existing account.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _createStaff,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add staff member'),
                  ),
                ),
                const SizedBox(height: 12),
                ...accounts.map((account) {
                  final uid = account['uid'] as String;
                  final role = account['role'] as String? ?? 'student';
                  final isSelf = uid == currentUid;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEDEBFF),
                        child: Icon(
                          role == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : role == 'staff'
                                  ? Icons.handyman_outlined
                                  : Icons.school_outlined,
                          color: brand,
                        ),
                      ),
                      title: Text(
                        account['displayName'] as String? ??
                            account['email'] as String? ??
                            uid,
                      ),
                      subtitle: Text(
                        '${account['email'] ?? ''}\n${isSelf ? 'Your account · ' : ''}Role: ${role.toUpperCase()}',
                      ),
                      isThreeLine: true,
                      trailing: _updatingUid == uid
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : DropdownButton<String>(
                              value: const {'student', 'staff', 'admin'}
                                      .contains(role)
                                  ? role
                                  : 'student',
                              onChanged: isSelf
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _changeRole(uid, value);
                                      }
                                    },
                              items: const [
                                DropdownMenuItem(
                                  value: 'student',
                                  child: Text('Student'),
                                ),
                                DropdownMenuItem(
                                  value: 'staff',
                                  child: Text('Staff'),
                                ),
                                DropdownMenuItem(
                                  value: 'admin',
                                  child: Text('Admin'),
                                ),
                              ],
                            ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
}

class SupportPage extends StatefulWidget {
  const SupportPage({
    super.key,
    required this.repository,
    required this.isAdmin,
    required this.isStudent,
  });

  final FirebaseIssueRepository repository;
  final bool isAdmin;
  final bool isStudent;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _suggestionController = TextEditingController();
  final _suggestionFormKey = GlobalKey<FormState>();
  bool _sending = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await widget.repository.submitSupportRequest(
        subject: _subject.text,
        message: _message.text,
      );
      _subject.clear();
      _message.clear();
      if (mounted) _showMessage('Your support request was sent.');
    } catch (error) {
      if (mounted) _showMessage('Could not send request: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolveRequest(String id) async {
    try {
      await widget.repository.updateSupportStatus(id, 'resolved');
    } catch (error) {
      if (mounted) _showMessage('Could not update support request: $error');
    }
  }

  Future<void> _submitSuggestion() async {
    if (!_suggestionFormKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await widget.repository.submitSuggestion(_suggestionController.text);
      _suggestionController.clear();
      if (mounted) _showMessage('Your suggestion was sent for review.');
    } catch (error) {
      if (mounted) _showMessage('Could not send suggestion: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _updateSuggestion(String id, String status) async {
    try {
      await widget.repository.updateSuggestionStatus(id, status);
    } catch (error) {
      if (mounted) _showMessage('Could not update suggestion: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _suggestionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Help & support')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'How can we help?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('How do I report an issue?'),
              children: [
                ListTile(
                  title: Text(
                    'Open the Report tab, include the exact location and details, then submit. Photos are optional.',
                  ),
                ),
              ],
            ),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('How can I follow progress?'),
              children: [
                ListTile(
                  title: Text(
                    'Open an issue to view its timeline. Enable push notifications in Settings for status alerts.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Send a support request',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: (value) =>
                        value == null || value.trim().length < 4
                            ? 'Enter a short subject.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _message,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        value == null || value.trim().length < 10
                            ? 'Please add a little more detail.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _submit,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(_sending ? 'Sending...' : 'Send request'),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isStudent) ...[
              const SizedBox(height: 24),
              const Text(
                'Suggest an improvement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Share an idea for improving campus services or facilities.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 10),
              Form(
                key: _suggestionFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _suggestionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Your suggestion',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value == null || value.trim().length < 10
                              ? 'Please add at least 10 characters.'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _sending ? null : _submitSuggestion,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Send suggestion'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.isAdmin) ...[
              const SizedBox(height: 28),
              const Text(
                'Support inbox',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: widget.repository.watchSupportMessages(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorBanner(
                      message:
                          'Could not load support inbox: ${snapshot.error}',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  final tickets = snapshot.data!;
                  if (tickets.isEmpty) {
                    return const _EmptyState(
                      title: 'Inbox is clear',
                      subtitle: 'New support requests will show here.',
                    );
                  }
                  return Column(
                    children: tickets.map((ticket) {
                      final resolved = ticket['status'] == 'resolved';
                      return Card(
                        child: ListTile(
                          title: Text(ticket['subject'] as String? ?? ''),
                          subtitle: Text(
                            '${ticket['email'] ?? ''}\n${ticket['message'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: resolved
                              ? const Icon(
                                  Icons.task_alt,
                                  color: Color(0xFF138A68),
                                )
                              : IconButton(
                                  tooltip: 'Mark resolved',
                                  onPressed: () => _resolveRequest(
                                    ticket['id'] as String,
                                  ),
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                  ),
                                ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Student suggestions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: widget.repository.watchSuggestions(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorBanner(
                      message: 'Could not load suggestions: ${snapshot.error}',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  final suggestions = snapshot.data!;
                  if (suggestions.isEmpty) {
                    return const _EmptyState(
                      title: 'No suggestions yet',
                      subtitle: 'Student ideas will appear here for review.',
                    );
                  }
                  return Column(
                    children: suggestions.map((suggestion) {
                      final status = suggestion['status'] as String? ?? 'open';
                      return Card(
                        child: ListTile(
                          title: Text(suggestion['message'] as String? ?? ''),
                          subtitle: Text(
                            '${suggestion['email'] ?? ''} · ${status.toUpperCase()}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Review suggestion',
                            onSelected: (value) => _updateSuggestion(
                              suggestion['id'] as String,
                              value,
                            ),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'reviewed',
                                child: Text('Mark reviewed'),
                              ),
                              PopupMenuItem(
                                value: 'implemented',
                                child: Text('Mark implemented'),
                              ),
                              PopupMenuItem(
                                value: 'declined',
                                child: Text('Decline'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      );
}

String? _imageContentType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}
