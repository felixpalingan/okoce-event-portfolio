
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/utils/http_client.dart';

class TestScreen extends StatefulWidget {
  final int eventId;
  final String testType;

  const TestScreen({super.key, required this.eventId, required this.testType});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<dynamic> _questions = [];

  final Map<String, String> _answers = {};

  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final response = await HttpClient.get('/api/events/${widget.eventId}/test/questions');

      if (response.statusCode == 200) {
        setState(() {
          _questions = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        _showError("Gagal memuat soal: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Error: $e");
    }
  }

  Future<void> _submitAnswers() async {
    if (_answers.length < _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Harap jawab semua pertanyaan sebelum submit.")),
      );
      return;
    }

    setState(() { _isSubmitting = true; });

    try {
      final response = await HttpClient.post('/api/events/${widget.eventId}/test/submit', {
        'answers': _answers
      });

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Hasil Tes"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 60),
                const SizedBox(height: 16),
                Text("${widget.testType} Selesai!", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Nilai Kamu: ${data['score']}", style: const TextStyle(fontSize: 24, color: Colors.blue)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(true);
                },
                child: const Text("Tutup"),
              )
            ],
          ),
        );
      } else {
        _showError("Gagal submit: ${data['message']}");
        setState(() { _isSubmitting = false; });
      }
    } catch (e) {
      _showError("Error: $e");
      setState(() { _isSubmitting = false; });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _nextPage() {
    if (_currentIndex < _questions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testType),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Soal ${_currentIndex + 1}/${_questions.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final q = _questions[index];
                final qNum = q['number'].toString();

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(q['text'], style: const TextStyle(fontSize: 18, height: 1.4)),
                      const SizedBox(height: 24),

                      _buildOption(qNum, 'A', q['options']['A']),
                      _buildOption(qNum, 'B', q['options']['B']),
                      _buildOption(qNum, 'C', q['options']['C']),
                      _buildOption(qNum, 'D', q['options']['D']),
                    ],
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                if (_currentIndex > 0)
                  TextButton(
                    onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease),
                    child: const Text("Sebelumnya"),
                  ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : () {
                    if (_currentIndex == _questions.length - 1) {
                      _submitAnswers();
                    } else {
                      _nextPage();
                    }
                  },
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_currentIndex == _questions.length - 1 ? "Kirim Jawaban" : "Lanjut"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(String qNum, String code, String text) {
    final isSelected = _answers[qNum] == code;

    return GestureDetector(
      onTap: () {
        setState(() {
          _answers[qNum] = code;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.white,
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.blue : Colors.grey[200],
              ),
              child: Text(code, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}