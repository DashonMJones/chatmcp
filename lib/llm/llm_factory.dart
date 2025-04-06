import 'openai_client.dart';
import 'claude_client.dart';
import 'deepseek_client.dart';
import 'base_llm_client.dart';
import 'ollama_client.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:logging/logging.dart';
import 'model.dart' as llm_model;

enum LLMProvider { openAI, claude, ollama, deepSeek }

class LLMFactory {
  static BaseLLMClient create(LLMProvider provider,
      {required String apiKey, required String baseUrl}) {
    switch (provider) {
      case LLMProvider.openAI:
        return OpenAIClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.claude:
        return ClaudeClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.deepSeek:
        return DeepSeekClient(apiKey: apiKey, baseUrl: baseUrl);
      case LLMProvider.ollama:
        return OllamaClient(baseUrl: baseUrl);
    }
  }
}

class LLMFactoryHelper {
  static final nonChatModelKeywords = {"whisper", "tts", "dall-e", "embedding"};

  static bool isChatModel(llm_model.Model model) {
    return !nonChatModelKeywords.any((keyword) => model.name.contains(keyword));
  }

  static final Map<String, LLMProvider> providerMap = {
    "openai": LLMProvider.openAI,
    "claude": LLMProvider.claude,
    "deepseek": LLMProvider.deepSeek,
    "ollama": LLMProvider.ollama,
  };

  static BaseLLMClient createFromModel(llm_model.Model currentModel) {
    final setting =
        ProviderManager.settingsProvider.apiSettings[currentModel.provider];

    // 获取配置信息
    final apiKey = setting?.apiKey ?? '';
    final baseUrl = setting?.apiEndpoint ?? '';

    Logger.root.fine(
        'Using API Key: ${apiKey.isEmpty ? 'empty' : apiKey.substring(0, 10)}***** for provider: ${currentModel.provider} model: $currentModel');

    // 创建 LLM 客户端
    return LLMFactory.create(
        LLMFactoryHelper.providerMap[currentModel.provider] ??
            (throw ArgumentError("Unknown provider: $currentModel")),
        apiKey: apiKey,
        baseUrl: baseUrl);
  }

  static Future<List<llm_model.Model>> getAvailableModels() async {
    List<llm_model.Model> models = [];
    for (var provider in LLMFactoryHelper.providerMap.entries) {
      final apiKey =
          ProviderManager.settingsProvider.apiSettings[provider.key]?.apiKey ??
              '';
      final baseUrl = ProviderManager
              .settingsProvider.apiSettings[provider.key]?.apiEndpoint ??
          '';

      if (baseUrl.isEmpty) {
        continue;
      }
      final client =
          LLMFactory.create(provider.value, apiKey: apiKey, baseUrl: baseUrl);
      models.addAll((await client.models()).map((model) =>
          llm_model.Model(name: model, label: model, provider: provider.key)));
    }

    return models;
  }
}
