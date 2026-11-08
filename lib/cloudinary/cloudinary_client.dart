import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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

/// An image stored in Cloudinary.
class CloudinaryAsset {
  const CloudinaryAsset({
    required this.publicId,
    required this.secureUrl,
    required this.width,
    required this.height,
  });

  final String publicId;
  final Uri secureUrl;
  final int width;
  final int height;
}

/// The Cloudinary calls KW Hab uses. Everything here runs on the Dart side,
/// so the API secret never reaches Facebook's page.
///
/// - [askAboutImage]: AI Vision (Analyze API) answers a question about an
///   image at a URL, without storing the image.
/// - [upload]: signed upload of the user's own photo.
/// - [transformed] + [download]: on-the-fly transformations such as
///   generative restore (`e_gen_restore`).
/// - [editImage]: Image Generation (image to image), for repairing and
///   colourising old photos.
class CloudinaryClient {
  CloudinaryClient(
    this.config, {
    http.Client? client,
    this.pollInterval = const Duration(seconds: 2),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final CloudinaryConfig config;
  final Duration pollInterval;
  final http.Client _client;
  final DateTime Function() _clock;

  bool get isConfigured => config.isConfigured;

  static const Duration analyzeTimeout = Duration(seconds: 45);
  static const Duration uploadTimeout = Duration(seconds: 60);
  static const Duration generateTimeout = Duration(seconds: 150);

  /// Cloudinary's free plan limit for one image upload.
  static const int maxUploadBytes = 10 * 1024 * 1024;

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

  /// Uploads [bytes] (a JPEG or PNG) into [folder] with a signed request.
  Future<CloudinaryAsset> upload(Uint8List bytes, {required String folder}) async {
    final cloud = _cloud;
    if (bytes.isEmpty) throw const CloudinaryException('bad_image', 'No image');
    if (bytes.length > maxUploadBytes) {
      throw const CloudinaryException('too_big', 'Image is over 10 MB');
    }
    final params = {
      'folder': folder,
      'timestamp': (_clock().millisecondsSinceEpoch ~/ 1000).toString(),
    };
    final request = http.MultipartRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/$cloud/image/upload'),
    )
      ..fields.addAll(params)
      ..fields['api_key'] = config.apiKey!
      ..fields['signature'] = sign(params, config.apiSecret!)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'));
    final response = await _send(
      () async => http.Response.fromStream(await _client.send(request)),
      uploadTimeout,
    );
    try {
      final json = jsonDecode(response.body) as Map;
      return CloudinaryAsset(
        publicId: json['public_id'] as String,
        secureUrl: Uri.parse(json['secure_url'] as String),
        width: (json['width'] as num).toInt(),
        height: (json['height'] as num).toInt(),
      );
    } catch (_) {
      throw const CloudinaryException('bad_response', 'Unexpected upload response');
    }
  }

  /// Cloudinary's request signature: the parameters sorted by name, joined
  /// as `a=1&b=2`, followed by the API secret, hashed with SHA-1.
  static String sign(Map<String, String> params, String secret) {
    final names = params.keys.toList()..sort();
    final joined = names.map((n) => '$n=${params[n]}').join('&');
    return sha1.convert(utf8.encode('$joined$secret')).toString();
  }

  /// [url] (a Cloudinary delivery URL) with [transformation] applied, e.g.
  /// `e_gen_restore/e_improve`.
  static Uri transformed(Uri url, String transformation) {
    final path = url.path;
    const marker = '/upload/';
    final at = path.indexOf(marker);
    if (at < 0) throw ArgumentError.value(url, 'url', 'not a Cloudinary upload URL');
    final split = at + marker.length;
    return url.replace(path: '${path.substring(0, split)}$transformation/${path.substring(split)}');
  }

  /// Downloads a delivery URL. Generative transformations answer 423 while
  /// Cloudinary is still making them, so this keeps asking until [timeout].
  Future<Uint8List> download(Uri url, {Duration timeout = const Duration(seconds: 120)}) async {
    final deadline = _clock().add(timeout);
    while (true) {
      final http.Response response;
      try {
        response = await _client.get(url).timeout(const Duration(seconds: 60));
      } on TimeoutException {
        throw const CloudinaryException('timeout', 'Download timed out');
      } catch (e) {
        throw CloudinaryException('network', '$e');
      }
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) return response.bodyBytes;
      if (response.statusCode == 423 && _clock().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      if (response.statusCode == 423) {
        throw const CloudinaryException('timeout', 'Still processing');
      }
      // Delivery errors carry the reason in a header, not the body.
      final reason = response.headers['x-cld-error'] ?? '';
      throw CloudinaryException(_codeFor(response.statusCode, reason), reason);
    }
  }

  /// Image Generation (image to image): makes a new image from [prompt],
  /// with [reference] as image `[1]`, stored at [publicId]. Returns its URL.
  Future<Uri> editImage({
    required Uri reference,
    required String prompt,
    required String publicId,
    String? aspectRatio,
  }) async {
    final uri = Uri.https('api.cloudinary.com', '/v2/generate/$_cloud/image_to_image');
    final response = await _send(
      () => _client.post(
        uri,
        headers: {..._basicAuth, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'reference_images': [
            {'source_type': 'url', 'url': reference.toString()},
          ],
          // Pinned: other models invented things in testing (a hat on a man
          // who wasn't wearing one), which isn't acceptable for family photos.
          'model': {'family': 'nano-banana', 'tier': 'premium'},
          if (aspectRatio != null) 'image_size': {'aspect_ratio': aspectRatio, 'resolution': '1K'},
          'target': {'target_type': 'managed_asset', 'public_id': publicId},
        }),
      ),
      generateTimeout,
    );
    try {
      final json = jsonDecode(response.body);
      final asset = (json['data']['assets'] as List).first as Map;
      debugPrint('[kw-hab:cloudinary] generated with ${asset['model']?['id']}, '
          'quota ${json['limits']?['addons_quota']}');
      return Uri.parse(asset['storage']['secure_url'] as String);
    } catch (_) {
      throw const CloudinaryException('bad_response', 'Unexpected generation response');
    }
  }

  /// The closest aspect ratio Image Generation accepts, for a
  /// [width] x [height] image.
  static String nearestAspectRatio(int width, int height) {
    const ratios = {'1:1': 1.0, '16:9': 16 / 9, '9:16': 9 / 16, '4:3': 4 / 3, '3:4': 3 / 4};
    final target = width / height;
    var best = '1:1';
    var bestDistance = double.infinity;
    ratios.forEach((name, value) {
      final distance = (value - target).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = name;
      }
    });
    return best;
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
    final message = errorMessage(response.body).replaceAll(config.apiKey ?? ' ', '<key>');
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
