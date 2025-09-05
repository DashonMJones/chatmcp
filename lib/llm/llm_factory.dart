import 'openai_client.dart';
import 'claude_client.dart';
import 'deepseek_client.dart';
import 'base_llm_client.dart';
import 'ollama_client.dart';
import 'gemini_client.dart';
import 'foundry_client.dart';
import 'copilot_client.dart';
import 'claude_code_client.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:logging/logging.dart';
import 'model.dart' as llm_model;

enum LLMProvider { openai, claude, ollama, deepseek, gemini, foundry, claudeCode, copilot }

class LLMFactory {
  static BaseLLMClient create(LLMProvider provider, {required String apiKey, required String baseUrl, String? apiVersion}) {
    switch (provider) {
      case LLMProvider.openai:
        return OpenAIClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.claude:
        return ClaudeClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.claudeCode:
        Logger.root.info('🏭 LLMFactory: Creating ClaudeCodeClient');
        try {
          final client = ClaudeCodeClient();
          Logger.root.info('✅ LLMFactory: ClaudeCodeClient created successfully');
          return client;
        } catch (e) {
          Logger.root.severe('❌ LLMFactory: Failed to create ClaudeCodeClient: $e');
          rethrow;
        }
      case LLMProvider.deepseek:
        return DeepSeekClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.ollama:
        return OllamaClient(baseUrl: baseUrl);
      case LLMProvider.gemini:
        return GeminiClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.foundry:
        return FoundryClient(apiKey: apiKey, baseUrl: baseUrl, apiVersion: apiVersion);
      case LLMProvider.copilot:
        return CopilotClient(apiKey: apiKey);
    }
  }
}

class LLMFactoryHelper {
  static final nonChatModelKeywords = {"whisper", "tts", "dall-e", "embedding"};

  static bool isChatModel(llm_model.Model model) {
    return !nonChatModelKeywords.any((keyword) => model.name.contains(keyword));
  }

  static final Map<String, LLMProvider> providerMap = {
    "openai": LLMProvider.openai,
    "claude": LLMProvider.claude,
    "claude-code": LLMProvider.claudeCode,
    "deepseek": LLMProvider.deepseek,
    "ollama": LLMProvider.ollama,
    "gemini": LLMProvider.gemini,
    "foundry": LLMProvider.foundry,
    "copilot": LLMProvider.copilot,
  };

  static String _maskApiKey(String apiKey) {
    if (apiKey.isEmpty) return 'empty';
    if (apiKey.length <= 8) return '***';
    return '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
  }

  static void _logApiKeyUsage(String provider, String model, String apiKey) {
    final maskedKey = _maskApiKey(apiKey);
    Logger.root.info('Using API key for provider: $provider, model: $model, key: $maskedKey');
  }

  static BaseLLMClient createFromModel(llm_model.Model currentModel) {
    Logger.root.info('🔍 LLMFactory: Creating client for model - providerId: ${currentModel.providerId}, name: ${currentModel.name}, apiStyle: ${currentModel.apiStyle}');
    
    try {
      final setting = ProviderManager.settingsProvider.apiSettings.firstWhere((element) => element.providerId == currentModel.providerId);

      Logger.root.info('⚙️  LLMFactory: Found setting for provider ${currentModel.providerId} - enabled: ${setting.enable ?? true}');

      // Check if the provider is enabled (null means enabled, only false means disabled)
      final isEnabled = setting.enable ?? true;
      if (!isEnabled) {
        Logger.root.warning('❌ LLMFactory: Provider ${currentModel.providerId} is disabled');
        throw Exception('Provider ${currentModel.providerId} is disabled');
      }

      // Set apiKey and baseUrl
      final apiKey = setting.apiKey;
      final baseUrl = setting.apiEndpoint;

      _logApiKeyUsage(currentModel.providerId, currentModel.name, apiKey);

      var provider = LLMFactoryHelper.providerMap[currentModel.providerId];
      Logger.root.info('🗺️  LLMFactory: Mapped provider from providerId: $provider');

      provider ??= LLMProvider.values.byName(currentModel.apiStyle);
      Logger.root.info('🎯 LLMFactory: Final provider selection: $provider');

      // Create LLM client
      Logger.root.info('🏭 LLMFactory: About to create client for provider: $provider');
      return LLMFactory.create(provider, apiKey: apiKey, baseUrl: baseUrl);
    } catch (e) {
      // If no matching provider is found, use default OpenAI
      Logger.root.warning('No matching provider found: ${currentModel.providerId}, using default OpenAI configuration');

      var openAISetting = ProviderManager.settingsProvider.apiSettings.firstWhere(
        (element) => element.providerId == "openai",
        orElse: () => LLMProviderSetting(apiKey: '', apiEndpoint: '', providerId: 'openai'),
      );

      return OpenAIClient(apiKey: openAISetting.apiKey, baseUrl: openAISetting.apiEndpoint);
    }
  }
}
