// screens/register_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pensaconnect/repositories/prayer_repository.dart'
    show PrayerRepository;
import '../providers/auth_provider.dart';
import '../theme/app_style.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;

  // Mirrors backend/utils.py validate_name — letters, spaces, hyphens,
  // apostrophes (incl. accented letters).
  static final _nameRegex = RegExp(r"^[a-zA-Zà-ÿÀ-Ÿ '\-]+$");
  // Mirrors backend/utils.py validate_username.
  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
  // Mirrors backend/utils.py validate_email's basic pattern.
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  // Mirrors backend/utils.py validate_phone_number, applied after the
  // same whitespace/hyphen/parenthesis stripping the backend does.
  static final _phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');

  String? _validateName(String? value, String fieldName) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName is required';
    if (v.length < 2) return '$fieldName must be at least 2 characters';
    if (v.length > 50) return '$fieldName must be less than 50 characters';
    if (!_nameRegex.hasMatch(v)) {
      return '$fieldName can only contain letters, spaces, hyphens, and apostrophes';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Username is required';
    if (v.length < 3) return 'Username must be at least 3 characters';
    if (v.length > 30) return 'Username must be less than 30 characters';
    if (!_usernameRegex.hasMatch(v)) {
      return 'Only letters, numbers, and underscores allowed';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Please enter a valid email address';
    return null;
  }

  String? _validatePhone(String? value) {
    // Optional — backend only checks format when something was entered.
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final stripped = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!_phoneRegex.hasMatch(stripped)) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final p = value ?? '';
    if (p.isEmpty) return 'Password is required';
    if (p.length < 8) return 'Password must be at least 8 characters';
    if (p.length > 128) return 'Password must be less than 128 characters';
    return null;
  }

  Future<void> _register() async {
    // Catches empty/malformed fields immediately, with an inline
    // message under the exact field that needs fixing — no round trip
    // to the server needed just to find out a name field was left
    // blank or a password was missing a number.
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register({
      "first_name": _firstNameController.text.trim(),
      "last_name": _lastNameController.text.trim(),
      "username": _usernameController.text.trim(),
      "email": _emailController.text.trim(),
      "phone_number": _phoneController.text.trim(),
      "password": _passwordController.text.trim(),
    });

    if (!mounted) return;

    if (success) {
      // Registration already returns a live session (see
      // AuthProvider.register), so there's no reason to send someone
      // who just filled out this whole form back to the login screen
      // to type their new username and password again — take them
      // straight into the app, same as a normal login would.
      final loggedInUserId = authProvider.currentUser?.id;
      if (loggedInUserId != null) {
        context.read<PrayerRepository>().setCurrentUserId(loggedInUserId);
      }
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error ?? 'Registration failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.inkDusk, AppColors.emberGold],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.go('/'),
                  ),
                  Expanded(
                    child: Text(
                      'Create your account',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // balances the back button
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    // --- Side-by-Side Name Fields ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstNameController,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => _validateName(v, 'First name'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastNameController,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => _validateName(v, 'Last name'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'e.g. Gayivor_E',
                      ),
                      validator: _validateUsername,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone number (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _register,
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Create account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
