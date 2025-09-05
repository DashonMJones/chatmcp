import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

// Simple test of ClaudeCodeClient logic without Flutter dependencies
class LLMResponse {
  final String content;
  LLMResponse({required this.content});
}

class ChatMessage {
  final String role;
  final String? content;
  ChatMessage({required this.role, this.content});
}

class CompletionRequest {
  final List<ChatMessage> messages;
  CompletionRequest({required this.messages});
}

class SimpleClaudeCodeClient {
  final String executable;
  
  SimpleClaudeCodeClient({String? executablePath}) 
    : executable = (executablePath == null || executablePath.isEmpty) 
        ? '/home/dashon/.local/bin/claude' 
        : executablePath;

  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request) async* {
    final prompt = _buildPromptFromMessages(request.messages);
    final args = <String>['-p', prompt, '--output-format', 'json', '--dangerously-skip-permissions'];

    print('🚀 ClaudeCodeClient STREAM: Starting chatStreamCompletion');
    print('📝 ClaudeCodeClient STREAM: Prompt length: ${prompt.length}');
    print('⚙️  ClaudeCodeClient STREAM: Args: ${args.join(' ')}');

    try {
      print('🔄 ClaudeCodeClient STREAM: Running Process.run...');
      final result = await Process.run(
        executable, 
        args, 
        workingDirectory: '/home/dashon'
      ).timeout(Duration(seconds: 60));

      print('✅ ClaudeCodeClient STREAM: Process completed with exit code: ${result.exitCode}');
      
      if (result.exitCode != 0) {
        final errorMsg = result.stderr?.toString() ?? 'Unknown error';
        print('❌ ClaudeCodeClient STREAM: Process failed: $errorMsg');
        throw Exception('Claude Code CLI exited with ${result.exitCode}: $errorMsg');
      }

      final output = result.stdout.toString();
      print('📄 ClaudeCodeClient STREAM: Output length: ${output.length}');
      
      if (output.trim().isEmpty) {
        print('⚠️  ClaudeCodeClient STREAM: Empty output from CLI');
        return;
      }

      try {
        final obj = jsonDecode(output);
        print('📦 ClaudeCodeClient STREAM: Parsed JSON type: ${obj['type']}');
        
        if (obj['type'] == 'result' && obj['result'] != null) {
          final content = obj['result'].toString();
          print('💬 ClaudeCodeClient STREAM: Yielding result: ${content.length} chars');
          yield LLMResponse(content: content);
        } else {
          print('⚠️  ClaudeCodeClient STREAM: Unexpected JSON structure: ${obj.keys}');
        }
      } catch (jsonError) {
        print('❌ ClaudeCodeClient STREAM: JSON parse error: $jsonError');
        print('📄 Raw output: $output');
        throw Exception('Failed to parse Claude Code response: $jsonError');
      }
    } catch (e) {
      print('❌ ClaudeCodeClient STREAM: Error: $e');
      rethrow;
    }
  }

  String _buildPromptFromMessages(List<ChatMessage> messages) {
    const int maxMessages = 12;
    final recent = messages.length <= maxMessages ? messages : messages.sublist(messages.length - maxMessages);

    final buffer = StringBuffer();
    for (final m in recent) {
      final content = (m.content ?? '').trim();
      if (content.isEmpty) continue;
      switch (m.role) {
        case 'system':
          buffer.writeln('System: $content');
          break;
        case 'user':
          buffer.writeln('User: $content');
          break;
        case 'assistant':
          buffer.writeln('Assistant: $content');
          break;
        default:
          break;
      }
    }
    return buffer.toString().trim();
  }
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  final client = SimpleClaudeCodeClient();
  final request = CompletionRequest(messages: [
    ChatMessage(role: 'user', content: 'What is 2+2? Give a short answer.')
  ]);

  print('Testing Claude Code client...');
  
  try {
    await for (final response in client.chatStreamCompletion(request)) {
      print('✅ Received response: ${response.content}');
    }
    print('🎉 Test completed successfully!');
  } catch (e) {
    print('❌ Test failed: $e');
  }
}
