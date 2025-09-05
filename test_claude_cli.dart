import 'dart:io';
import 'dart:convert';

void main() async {
  print('Testing Claude CLI directly...');
  
  // Test if claude command exists
  try {
    final which = await Process.run('which', ['claude']);
    if (which.exitCode == 0) {
      print('✅ Claude CLI found at: ${which.stdout.toString().trim()}');
    } else {
      print('❌ Claude CLI not found in PATH');
      return;
    }
  } catch (e) {
    print('❌ Error checking for claude: $e');
    return;
  }

  // Test simple claude command
  try {
    print('🔄 Testing claude --help...');
    final help = await Process.run('claude', ['--help']).timeout(Duration(seconds: 10));
    print('✅ Claude help exit code: ${help.exitCode}');
    if (help.stdout.toString().isNotEmpty) {
      print('📄 Help output (first 200 chars): ${help.stdout.toString().substring(0, 200)}...');
    }
  } catch (e) {
    print('❌ Error running claude --help: $e');
  }

  // Test simple prompt
  try {
    print('🔄 Testing simple prompt...');
    final result = await Process.run(
      'claude', 
      ['-p', 'Say "Hello World"', '--output-format', 'json', '--dangerously-skip-permissions'],
      workingDirectory: '/home/dashon'
    ).timeout(Duration(seconds: 30));
    
    print('✅ Simple prompt exit code: ${result.exitCode}');
    print('📄 Stdout: ${result.stdout}');
    if (result.stderr.toString().isNotEmpty) {
      print('⚠️  Stderr: ${result.stderr}');
    }
  } catch (e) {
    print('❌ Error with simple prompt: $e');
  }
}
