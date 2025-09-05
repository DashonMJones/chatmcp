import 'package:chatmcp/llm/claude_client.dart';
import 'package:chatmcp/llm/model.dart';
import 'package:logging/logging.dart';

void main() async {
  // Enable logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Test Claude client (no API key needed for local Claude Code)
  final client = ClaudeClient(
    baseUrl: 'http://localhost:8080', // Your local Claude endpoint
  );

  try {
    print('Testing Claude connection...');
    
    final request = CompletionRequest(
      model: 'claude', // Try generic model name for local setup
      messages: [
        ChatMessage(
          role: MessageRole.user,
          content: 'Hello, can you respond with just "test successful"?',
        ),
      ],
      modelSetting: ModelSetting(
        maxTokens: 100,
        temperature: 0.7,
      ),
    );

    print('Sending request...');
    final response = await client.chatCompletion(request);
    print('Response: ${response.content}');
    
  } catch (e, stackTrace) {
    print('Error: $e');
    print('Stack trace: $stackTrace');
  }
}
