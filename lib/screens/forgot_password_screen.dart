import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/inline_alert.dart';

/// Alur lupa password: minta kode 6 digit, lalu verifikasi dan set
/// password baru. Dirancang dua langkah dalam satu layar.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  int _step = 0;
  String? _errorMessage;
  String? _debugCode;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.forgotPassword(_emailController.text.trim());
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (res['status'] == 200) {
        _step = 1;
        final data = res['data'];
        _debugCode = data is Map ? data['debug_code']?.toString() : null;
      } else {
        _errorMessage = _messageFrom(res, 'Gagal mengirim kode.');
      }
    });
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    if (!_resetFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.resetPassword(
      email: _emailController.text.trim(),
      code: _codeController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _confirmController.text,
    );

    if (!mounted) return;

    if (res['status'] == 200) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = _messageFrom(res, 'Kode salah atau sudah kedaluwarsa.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCodeStep = _step == 1;

    return AuthScaffold(
      title: isCodeStep ? 'Verifikasi kode' : 'Lupa password',
      subtitle: isCodeStep
          ? 'Masukkan kode 6 digit yang dikirim ke email kamu, lalu buat password baru.'
          : 'Masukkan email akun kamu. Kami akan mengirim kode verifikasi untuk mengatur ulang password.',
      footer: TextButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        child: const Text('Kembali ke halaman masuk'),
      ),
      child: isCodeStep ? _buildResetForm() : _buildEmailForm(),
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            InlineAlert(message: _errorMessage!),
            const SizedBox(height: 18),
          ],
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isLoading ? null : _sendCode(),
            decoration: const InputDecoration(
              hintText: 'nama@perusahaan.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Email wajib diisi';
              if (!email.contains('@') || !email.contains('.')) {
                return 'Format email belum benar';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _isLoading ? null : _sendCode,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Kirim kode'),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            InlineAlert(message: _errorMessage!),
            const SizedBox(height: 18),
          ],
          if (_debugCode != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Mode pengembangan: kode verifikasi kamu $_debugCode',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.greenDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 6,
            decoration: const InputDecoration(
              hintText: 'Kode 6 digit',
              counterText: '',
              prefixIcon: Icon(Icons.pin_outlined, size: 20),
            ),
            validator: (value) {
              final code = value?.trim() ?? '';
              if (code.length != 6) return 'Kode harus 6 digit';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Password baru',
              prefixIcon: Icon(Icons.key_rounded, size: 20),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Wajib diisi';
              if (value.length < 8) return 'Minimal 8 karakter';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isLoading ? null : _resetPassword(),
            decoration: const InputDecoration(
              hintText: 'Ulangi password baru',
              prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Konfirmasi tidak cocok';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Simpan password baru'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _isLoading ? null : _sendCode,
            child: const Text('Kirim ulang kode'),
          ),
        ],
      ),
    );
  }
}

String _messageFrom(Map<String, dynamic> response, String fallback) {
  final data = response['data'];

  if (data is Map) {
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }

    final message = data['message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString();
    }
  }

  return fallback;
}
