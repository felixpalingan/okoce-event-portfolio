
import 'package:flutter/material.dart';

class Page1Nama extends StatefulWidget {
  final Function(String) onNext;
  const Page1Nama({super.key, required this.onNext});

  @override
  State<Page1Nama> createState() => _Page1NamaState();
}

class _Page1NamaState extends State<Page1Nama> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      widget.onNext(_nameController.text);
    }
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
            height: availableHeight < 400 ? 400 : availableHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Selamat datang! Siapa nama lengkap Anda?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Nama tidak boleh kosong' : null,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 32),
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