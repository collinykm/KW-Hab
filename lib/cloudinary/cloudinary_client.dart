import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A Cloudinary request that failed. [code] is short and safe to show the
/// page (never the key or secret): `not_configured`, `unauthorized`,
/// `not_enabled` (add-on not turned on), `limit` (out of credits), `timeout`,
/// `network`, `bad_response`, `http_<status>`.
class CloudinaryException implements Exception {
  const CloudinaryException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => 'CloudinaryException($code${message.isEmpty ? '' : ': $message'})';
}

/// Credentials for one Cloudinary product environment, from `.env`:
/// `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`, or
/// a single `CLOUDINARY_URL=cloudinary://<key>:<secret>@<cloud name>`.
class CloudinaryConfig {
  const CloudinaryConfig({this.cloudName, this.apiKey, this.apiSecret});

  factory CloudinaryConfig.fromSettings(Map<String, String> settings) {
    var cloud = settings['CLOUDINARY_CLOUD_NAME'];
    var key = settings['CLOUDINARY_API_KEY'];
    var secret = settings['CLOUDINARY_API_SECRET'];
    final url = Uri.tryParse(settings['CLOUDINARY_URL'] ?? '');
    if (url != null && url.scheme == 'cloudinary') {
      final user = url.userInfo.split(':');
      cloud ??= url.host.isEmpty ? null : url.host;
      if (user.length == 2) {
        key ??= Uri.decodeComponent(user[0]);
        secret ??= Uri.decodeComponent(user[1]);
      }
    }
    return CloudinaryConfig(cloudName: cloud, apiKey: key, apiSecret: secret);
  }

  final String? cloudName;
  final String? apiKey;
  final String? apiSecret;

  bool get isConfigured => cloudName != null && apiKey != null && apiSecret != null;
}

/// The Cloudinary calls KW Hab uses. Everything here runs on the Dart side,
/// so the API secret never reaches Facebook's page.
///
/// - [askAboutImage]: AI Vision (Analyze API) answers a question about an
///   image at a URL, without storing the image.
/// - [caption]: AI Content Analysis describes an image, also without storing it.
class CloudinaryClient {
  CloudinaryClient(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final CloudinaryConfig config;
  final http.Client _client;

  bool get isConfigured => config.isConfigured;

  static const Duration analyzeTimeout = Duration(seconds: 45);

  String get _cloud {
    if (!isConfigured) {
      throw const CloudinaryException('not_configured', 'Cloudinary keys are not set');
    }
    return config.cloudName!;
  }

  Map<String, String> get _basicAuth => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.apiKey}:${config.apiSecret}'))}',
      };

  /// Asks Cloudinary AI Vision [prompt] about the image at [image] and
  /// returns its answer. Needs the AI Vision add-on.
  Future<String> askAboutImage(Uri image, String prompt) async {
    final uri = Uri.https('api.cloudinary.com', '/v2/analysis/$_cloud/analyze/ai_vision_general');
    final response = await _send(
      () => _client.post(
        uri,
        headers: {..._basicAuth, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'source': {'uri': image.toString()},
          'prompts': [prompt],
        }),
      ),
      analyzeTimeout,
    );
    return parseVisionAnswer(response.body);
  }

  /// A one-sentence caption for the image at [image], from Cloudinary AI
  /// Content Analysis. A fallback for when AI Vision isn't available.
  Future<String> caption(Uri image) async {
    final uri = Uri.https('api.cloudinary.com', '/v2/analysis/$_cloud/analyze/captioning');
    final response = await _send(
      () => _client.post(
        uri,
        headers: {..._basicAuth, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'source': {'uri': image.toString()},
        }),
      ),
      analyzeTimeout,
    );
    try {
      final caption = jsonDecode(response.body)['data']['analysis']['data']['caption'];
      if (caption is String && caption.trim().isNotEmpty) return caption.trim();
    } catch (_) {
      // Falls through.
    }
    throw const CloudinaryException('bad_response', 'No caption');
  }

  /// The first answer in an AI Vision response.
  static String parseVisionAnswer(String body) {
    try {
      final json = jsonDecode(body);
      final responses = json['data']['analysis']['responses'] as List;
      final value = (responses.first as Map)['value'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    } catch (_) {
      // Falls through.
    }
    throw const CloudinaryException('bad_response', 'No answer from AI Vision');
  }

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const CloudinaryException('timeout', 'Cloudinary took too long');
    } on CloudinaryException {
      rethrow;
    } catch (e) {
      throw CloudinaryException('network', '$e');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    // Cloudinary sometimes repeats the API key in its errors: keep it out of logs.
    final message = errorMessage(response.body).replaceAll(config.apiKey!, '<key>');
    debugPrint('[kw-hab:cloudinary] HTTP ${response.statusCode}: $message');
    throw CloudinaryException(_codeFor(response.statusCode, message), message);
  }

  /// The `error.message` of a Cloudinary error response, if there is one.
  static String errorMessage(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'];
      if (error is Map && error['message'] is String) return error['message'] as String;
      if (error is String) return error;
    } catch (_) {
      // Not JSON.
    }
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  static String _codeFor(int status, String message) {
    final text = message.toLowerCase();
    if (status == 401) return 'unauthorized';
    if (status == 429 || text.contains('quota') || text.contains('credit')) return 'limit';
    if (text.contains('add-on') || text.contains('addon') || text.contains('subscri') ||
        text.contains('not enabled') || text.contains('not activated')) {
      return 'not_enabled';
    }
    if (status == 402 || status == 403) return 'not_enabled';
    return 'http_$status';
  }
}
