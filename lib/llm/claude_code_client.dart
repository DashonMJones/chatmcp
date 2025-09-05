import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'base_llm_client.dart';
import 'model.dart';

/// Claude Code client backed by the `claude` CLI.
///
/// This client shells out to the Claude Code SDK CLI, so it works without
/// directly using Anthropic HTTP APIs. It expects the `claude` binary to be
/// available on PATH (or via a configured absolute path), and that the user
/// has already authenticated per Claude Code SDK docs.
///
/// Non-goals:
/// - Tool calling is not wired, as Claude Code has its own tool system
///   (Read/Write/Bash). We ignore `tools` in requests.
class ClaudeCodeClient extends BaseLLMClient {
  /// Path or name of the Claude Code CLI executable. Defaults to `claude`.
  final String executable;

  ClaudeCodeClient({String? executablePath}) : executable = (executablePath == null || executablePath.isEmpty) ? '/home/dashon/.local/bin/claude' : executablePath;

  @override
  Future<LLMResponse> chatCompletion(CompletionRequest request) async {
    final prompt = _buildPromptFromMessages(request.messages);

    // Use JSON output for reliable parsing
    final args = <String>['-p', prompt, '--output-format', 'json', '--dangerously-skip-permissions'];

    Logger.root.info('🚀 ClaudeCodeClient: Starting chatCompletion');
    Logger.root.info('📝 ClaudeCodeClient: Prompt length: ${prompt.length}');
    Logger.root.info('⚙️  ClaudeCodeClient: Args: ${args.join(' ')}');

    try {
      Logger.root.info('🔄 ClaudeCodeClient: Calling Process.run...');
      final result = await Process.run(executable, args, runInShell: true, workingDirectory: '/home/dashon');

      Logger.root.info('✅ ClaudeCodeClient: Process completed with exit code: ${result.exitCode}');

      if (result.exitCode != 0) {
        Logger.root.severe('❌ ClaudeCodeClient: Process failed - stderr: ${result.stderr}');
        throw Exception(
          result.stderr is String && (result.stderr as String).isNotEmpty ? result.stderr : 'Claude Code CLI exited with ${result.exitCode}',
        );
      }

      final output = result.stdout is String ? result.stdout as String : utf8.decode((result.stdout as List<int>));
      Logger.root.info('📋 ClaudeCodeClient: Output length: ${output.length}');
      
      final content = _parseClaudeCodeJsonOutput(output);
      Logger.root.info('🎯 ClaudeCodeClient: Parsed content length: ${content.length}');
      
      return LLMResponse(content: content);
    } catch (e) {
      // Surface a structured error via BaseLLMClient.handleError contract
      throw await handleError(e, 'Claude Code', executable, jsonEncode({'args': args}));
    }
  }

  @override
  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request) async* {
    final prompt = _buildPromptFromMessages(request.messages);

    // Claude CLI doesn't support true streaming, so we use regular JSON and simulate streaming
    final args = <String>['-p', prompt, '--output-format', 'json', '--dangerously-skip-permissions'];

    Logger.root.info('🚀 ClaudeCodeClient STREAM: Starting chatStreamCompletion');
    Logger.root.info('📝 ClaudeCodeClient STREAM: Prompt length: ${prompt.length}');
    Logger.root.info('⚙️  ClaudeCodeClient STREAM: Args: ${args.join(' ')}');

    try {
      Logger.root.info('🔄 ClaudeCodeClient STREAM: Running Process.run...');
      final result = await Process.run(
        executable, 
        args, 
        workingDirectory: '/home/dashon'
      ).timeout(Duration(seconds: 60));

      Logger.root.info('✅ ClaudeCodeClient STREAM: Process completed with exit code: ${result.exitCode}');
      
      if (result.exitCode != 0) {
        final errorMsg = result.stderr?.toString() ?? 'Unknown error';
        Logger.root.severe('❌ ClaudeCodeClient STREAM: Process failed: $errorMsg');
        throw Exception('Claude Code CLI exited with ${result.exitCode}: $errorMsg');
      }

      final output = result.stdout.toString();
      Logger.root.info('📄 ClaudeCodeClient STREAM: Output length: ${output.length}');
      
      if (output.trim().isEmpty) {
        Logger.root.warning('⚠️  ClaudeCodeClient STREAM: Empty output from CLI');
        return;
      }

      try {
        final obj = jsonDecode(output);
        Logger.root.info('📦 ClaudeCodeClient STREAM: Parsed JSON type: ${obj['type']}');
        
        if (obj['type'] == 'result' && obj['result'] != null) {
          final content = obj['result'].toString();
          Logger.root.info('💬 ClaudeCodeClient STREAM: Yielding result: ${content.length} chars');
          yield LLMResponse(content: content);
        } else {
          Logger.root.warning('⚠️  ClaudeCodeClient STREAM: Unexpected JSON structure: ${obj.keys}');
        }
      } catch (jsonError) {
        Logger.root.severe('❌ ClaudeCodeClient STREAM: JSON parse error: $jsonError');
        Logger.root.severe('📄 Raw output: $output');
        throw Exception('Failed to parse Claude Code response: $jsonError');
      }
    } catch (e) {
      throw await handleError(e, 'Claude Code', executable, jsonEncode({'args': args}));
    }
  }

  @override
  Future<List<String>> models() async {
    // Claude Code CLI does not expose a model listing endpoint.
    // Return a common set; users can customize in settings.
    return <String>['claude-3-7-sonnet', 'claude-3-opus', 'claude-3-5-sonnet', 'claude-3-5-haiku'];
  }

  String _buildPromptFromMessages(List<ChatMessage> messages) {
    // Keep recent context small to avoid overly long shell args.
    const int maxMessages = 12;
    final recent = messages.length <= maxMessages ? messages : messages.sublist(messages.length - maxMessages);

    final buffer = StringBuffer();
    for (final m in recent) {
      final content = (m.content ?? '').trim();
      if (content.isEmpty) continue;
      switch (m.role) {
        case MessageRole.system:
          buffer.writeln('System: $content');
          break;
        case MessageRole.user:
          buffer.writeln('User: $content');
          break;
        case MessageRole.assistant:
          buffer.writeln('Assistant: $content');
          break;
        default:
          // Ignore tool/function/error/loading in prompt for Claude Code
          break;
      }
    }
    return buffer.toString().trim();
  }

  /// Parse JSON output from `claude -p --output-format json`.
  /// The CLI typically prints a single JSON object. If multiple JSONL lines
  /// are present, prefer the final `result` type; otherwise accumulate
  /// assistant messages.
  String _parseClaudeCodeJsonOutput(String output) {
    output = output.trim();
    if (output.isEmpty) return '';

    // Try strict JSON first
    try {
      final obj = jsonDecode(output);
      final type = obj is Map<String, dynamic> ? obj['type'] : null;
      if (type == 'result') {
        return (obj['result'] ?? '').toString();
      }
      if (type == 'assistant') {
        return _extractTextFromAssistantMessage(obj['message']);
      }
      // Some versions might output a flat object with `result`
      if (obj is Map<String, dynamic> && obj.containsKey('result')) {
        return (obj['result'] ?? '').toString();
      }
    } catch (_) {
      // Fall through to JSONL mode
    }

    // Fallback: parse line-by-line as JSONL
    String aggregated = '';
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final obj = jsonDecode(trimmed);
        final type = obj['type'];
        if (type == 'assistant') {
          aggregated += _extractTextFromAssistantMessage(obj['message']);
        } else if (type == 'result') {
          if (aggregated.isEmpty) {
            aggregated = (obj['result'] ?? '').toString();
          }
        }
      } catch (_) {
        continue;
      }
    }
    return aggregated;
  }

  /// Extract plain text from an Anthropic SDK `Message` object
  /// produced by Claude Code CLI JSON messages.
  String _extractTextFromAssistantMessage(dynamic messageObj) {
    if (messageObj == null) return '';
    try {
      final content = messageObj['content'];
      if (content is List) {
        final texts = <String>[];
        for (final part in content) {
          if (part is Map<String, dynamic>) {
            final type = part['type'];
            if (type == 'text' && part['text'] is String) {
              texts.add(part['text'] as String);
            }
          }
        }
        return texts.join('');
      }
    } catch (e) {
      Logger.root.fine('Failed to parse assistant message content: $e');
    }
    return '';
  }
}
