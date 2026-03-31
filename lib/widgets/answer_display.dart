import 'package:flutter/material.dart';

class AnswerDisplayPage extends StatelessWidget {
  final Map<String, dynamic> questionData;

  const AnswerDisplayPage({super.key, required this.questionData});

  @override
  Widget build(BuildContext context) {
    // Determine type
    final String type = questionData['type'] ?? 'unknown';
    final String questionText = questionData['question'] ?? "No Question Text";

    // Multiple Choice Data
    final String correct = questionData['correct_option'] ?? "Unknown";

    // True/False Group Data
    final List<dynamic> tfItems = (type == 'true_false_group')
        ? (questionData['options'] ?? [])
        : [];

    return Scaffold(
      appBar: AppBar(title: const Text("Found Answer")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("MATCHED QUESTION:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(questionText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20, thickness: 2),

            const SizedBox(height: 10),

            // --- RENDER BASED ON TYPE ---
            if (type == 'multiple_choice') ...[
              const Text("CORRECT ANSWER:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  correct,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ] else if (type == 'true_false_group') ...[
              const Text("STATEMENTS & ANSWERS:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: tfItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = tfItems[index];
                    final String statement = item['statement'];
                    final bool isTrue = item['answer'] == true;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              statement,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // True/False Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isTrue ? Colors.green : Colors.red,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isTrue ? "V" : "F",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            if (type == 'multiple_choice') const Spacer(),

            const SizedBox(height: 20),
            if (questionData['location'] != null)
              Center(child: Text("Page: ${questionData['location']['page']}", style: const TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }
}