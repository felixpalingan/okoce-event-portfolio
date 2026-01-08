
import 'package:flutter/material.dart';

class Page3Password extends StatefulWidget {
  final Function(String) onNext;
  const Page3Password({super.key, required this.onNext});

  @override
  State<Page3Password> createState() => _Page3PasswordState();
}

class _Page3PasswordState extends State<Page3Password> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLengthValid = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswordLength);
  }

  void _validatePasswordLength() {
    setState(() {
      _isLengthValid = _passwordController.text.length >= 5;
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_validatePasswordLength);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      widget.onNext(_passwordController.text);
    }
  }

  Widget _buildCriteriaRow(String text, bool isValid) {
    final color = isValid ? Colors.green : Colors.red;
    final icon = isValid ? Icons.check_circle_outline : Icons.highlight_off;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;
    final screenPadding = MediaQuery.of(context).padding;
    final availableHeight = MediaQuery.of(context).size.height - appBarHeight - screenPadding.top - screenPadding.bottom - 48;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SizedBox(
            height: availableHeight < 450 ? 450 : availableHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Buat password Anda',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password tidak boleh kosong';
                    if (v.length < 5) return 'Password minimal 5 karakter';
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Konfirmasi Password',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (v) => v != _passwordController.text ? 'Password tidak cocok' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),

                const SizedBox(height: 24),
                _buildCriteriaRow('Minimal 5 karakter', _isLengthValid),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Lanjut'),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}