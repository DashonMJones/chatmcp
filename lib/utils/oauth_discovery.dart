import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Result of OAuth discovery for an MCP server
class OAuthDiscoveryResult {
  /// Whether the server requires OAuth authentication
  final bool requiresOAuth;
  
  /// OAuth authorization endpoint URL
  final String? authorizationUrl;
  
  /// OAuth token endpoint URL
  final String? tokenUrl;
  
  /// OAuth client ID (may be null for public clients)
  final String? clientId;
  
  /// OAuth scope string
  final String? scope;
  
  /// OAuth redirect URI
  final String? redirectUri;

  const OAuthDiscoveryResult({
    required this.requiresOAuth,
    this.authorizationUrl,
    this.tokenUrl,
    this.clientId,
    this.scope,
    this.redirectUri,
  });
}

/// Service for automatically discovering OAuth configuration from MCP servers
/// 
/// Implements RFC 8414 (OAuth 2.0 Authorization Server Metadata) and RFC 7591
/// (OAuth 2.0 Dynamic Client Registration) for automatic OAuth discovery.
class OAuthDiscoveryService {
  static final Logger _logger = Logger('OAuthDiscoveryService');

  /// Automatically discovers OAuth configuration for an MCP server URL
  static Future<OAuthDiscoveryResult> discoverOAuth(String serverUrl) async {
    try {
      _logger.info('Discovering OAuth configuration for: $serverUrl');
      
      final baseUri = Uri.parse(serverUrl);
      final baseUrl = '${baseUri.scheme}://${baseUri.host}:${baseUri.port}';
      
      // Try multiple discovery methods
      var result = await _tryWellKnownEndpoint(baseUrl);
      if (result.requiresOAuth) return result;
      
      result = await _tryDirectServerProbe(serverUrl);
      if (result.requiresOAuth) return result;
      
      result = await _tryOAuthMetadataEndpoint(baseUrl);
      if (result.requiresOAuth) return result;
      
      // No OAuth required
      return OAuthDiscoveryResult(requiresOAuth: false);
      
    } catch (e) {
      _logger.warning('OAuth discovery failed: $e');
      return OAuthDiscoveryResult(requiresOAuth: false);
    }
  }

  /// Try RFC 8414 OAuth 2.0 Authorization Server Metadata
  static Future<OAuthDiscoveryResult> _tryWellKnownEndpoint(String baseUrl) async {
    try {
      final wellKnownUrl = '$baseUrl/.well-known/oauth-authorization-server';
      _logger.info('Trying well-known endpoint: $wellKnownUrl');
      
      final response = await http.get(
        Uri.parse(wellKnownUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final metadata = json.decode(response.body) as Map<String, dynamic>;
        
        final authorizationEndpoint = metadata['authorization_endpoint'] as String?;
        final tokenEndpoint = metadata['token_endpoint'] as String?;
        
        if (authorizationEndpoint != null && tokenEndpoint != null) {
          _logger.info('Found OAuth metadata via well-known endpoint');
          
          // Check if dynamic client registration is available
          final registrationEndpoint = metadata['registration_endpoint'] as String?;
          String? clientId = metadata['client_id'] as String?;
          
          // For servers like Notion that support dynamic registration and public clients,
          // we'll try to register a client dynamically if no client_id is provided
          if (clientId == null && registrationEndpoint != null) {
            clientId = await _tryDynamicClientRegistration(registrationEndpoint);
          }
          
          return OAuthDiscoveryResult(
            requiresOAuth: true,
            authorizationUrl: authorizationEndpoint,
            tokenUrl: tokenEndpoint,
            clientId: clientId, // May be null for public clients
            scope: metadata['scope'] as String? ?? 'read write',
            redirectUri: _generateRedirectUri(),
          );
        }
      }
    } catch (e) {
      _logger.fine('Well-known endpoint not available: $e');
    }
    
    return OAuthDiscoveryResult(requiresOAuth: false);
  }

  /// Try probing the MCP server directly for OAuth requirements
  static Future<OAuthDiscoveryResult> _tryDirectServerProbe(String serverUrl) async {
    try {
      _logger.info('Probing MCP server directly: $serverUrl');
      
      // For SSE endpoints, try connecting and check for auth requirements
      if (serverUrl.contains('/sse') || serverUrl.contains('/mcp')) {
        final response = await http.get(
          Uri.parse(serverUrl),
          headers: {'Accept': 'text/event-stream'},
        ).timeout(const Duration(seconds: 5));
        
        // Check for OAuth challenge in response headers or body
        final authHeader = response.headers['www-authenticate'];
        if (authHeader != null && authHeader.toLowerCase().contains('bearer')) {
          _logger.info('Server requires OAuth authentication');
          
          // Try to extract OAuth endpoints from response headers or body
          final authEndpoint = response.headers['x-oauth-authorization-url'];
          final tokenEndpoint = response.headers['x-oauth-token-url'];
          
          if (authEndpoint != null && tokenEndpoint != null) {
            return OAuthDiscoveryResult(
              requiresOAuth: true,
              authorizationUrl: authEndpoint,
              tokenUrl: tokenEndpoint,
              clientId: response.headers['x-oauth-client-id'],
              scope: response.headers['x-oauth-scope'] ?? 'read write',
              redirectUri: _generateRedirectUri(),
            );
          }
        }
        
        // Check for 401 Unauthorized response
        if (response.statusCode == 401) {
          _logger.info('Server returned 401, may require OAuth');
          
          // Try to parse OAuth challenge from response body
          try {
            final body = response.body;
            if (body.contains('oauth') || body.contains('authorization')) {
              final bodyJson = json.decode(body) as Map<String, dynamic>?;
              if (bodyJson != null) {
                final authUrl = bodyJson['authorization_url'] as String?;
                final tokenUrl = bodyJson['token_url'] as String?;
                
                if (authUrl != null && tokenUrl != null) {
                  return OAuthDiscoveryResult(
                    requiresOAuth: true,
                    authorizationUrl: authUrl,
                    tokenUrl: tokenUrl,
                    clientId: bodyJson['client_id'] as String?,
                    scope: bodyJson['scope'] as String? ?? 'read write',
                    redirectUri: _generateRedirectUri(),
                  );
                }
              }
            }
          } catch (e) {
            _logger.fine('Could not parse OAuth info from response body: $e');
          }
        }
      }
    } catch (e) {
      _logger.fine('Direct server probe failed: $e');
    }
    
    return OAuthDiscoveryResult(requiresOAuth: false);
  }

  /// Try OAuth metadata endpoint
  static Future<OAuthDiscoveryResult> _tryOAuthMetadataEndpoint(String baseUrl) async {
    try {
      final metadataUrl = '$baseUrl/oauth/metadata';
      _logger.info('Trying OAuth metadata endpoint: $metadataUrl');
      
      final response = await http.get(
        Uri.parse(metadataUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final metadata = json.decode(response.body) as Map<String, dynamic>;
        
        final authUrl = metadata['authorization_url'] as String?;
        final tokenUrl = metadata['token_url'] as String?;
        
        if (authUrl != null && tokenUrl != null) {
          _logger.info('Found OAuth metadata via /oauth/metadata endpoint');
          
          return OAuthDiscoveryResult(
            requiresOAuth: true,
            authorizationUrl: authUrl,
            tokenUrl: tokenUrl,
            clientId: metadata['client_id'] as String?,
            scope: metadata['scope'] as String? ?? 'read write',
            redirectUri: _generateRedirectUri(),
          );
        }
      }
    } catch (e) {
      _logger.fine('OAuth metadata endpoint not available: $e');
    }
    
    return OAuthDiscoveryResult(requiresOAuth: false);
  }

  /// Generate appropriate redirect URI for current platform
  static String _generateRedirectUri() {
    // Get current page URL and construct redirect URI
    final currentUrl = Uri.base;
    return '${currentUrl.origin}/oauth_callback.html';
  }

  /// Try dynamic client registration (RFC 7591)
  static Future<String?> _tryDynamicClientRegistration(String registrationEndpoint) async {
    try {
      _logger.info('Attempting dynamic client registration at: $registrationEndpoint');
      
      final clientMetadata = {
        'client_name': 'ChatMCP Client',
        'redirect_uris': [_generateRedirectUri()],
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
        'token_endpoint_auth_method': 'none', // Public client
        'application_type': 'web',
        'scope': 'read write',
      };
      
      final response = await http.post(
        Uri.parse(registrationEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(clientMetadata),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final registrationResponse = json.decode(response.body) as Map<String, dynamic>;
        final clientId = registrationResponse['client_id'] as String?;
        
        if (clientId != null) {
          _logger.info('Dynamic client registration successful, client_id: $clientId');
          return clientId;
        }
      } else {
        _logger.warning('Dynamic client registration failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _logger.warning('Dynamic client registration error: $e');
    }
    
    return null;
  }
}
