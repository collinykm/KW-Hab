import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/support_contact.dart';
import 'staff_notifier.dart';

/// One way of delivering a [StaffAlert] (SMS, email).
abstract class AlertChannel {
  ContactMethod get method;

  /// Sends [alert] to [address] and returns the service's id for the message
  /// (to look it up in the Twilio or Resend dashboard), if it gave one.
  /// Throws [AlertDeliveryException] on failure.
  Future<String?> send(String address, StaffAlert alert);
}

class AlertDeliveryException implements Exception {
  AlertDeliveryException(this.message);
  final String message;

  @override
  String toString() => 'AlertDeliveryException: $message';
}

/// Texts alerts through Twilio's Messages API.
///
/// [from] is a Twilio phone number (`+15195550123`) or a Messaging Service
/// SID (`MG…`).
///
/// Signs in with an API key ([apiKeySid] `SK…` and [apiKeySecret]) when given,
/// otherwise with the account's [authToken]. Either way [accountSid] is the
/// `AC…` account the messages are sent from.
class TwilioSmsChannel implements AlertChannel {
  TwilioSmsChannel({
    required this.accountSid,
    this.authToken = '',
    this.apiKeySid = '',
    this.apiKeySecret = '',
    required this.from,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final String accountSid;
  final String authToken;
  final String apiKeySid;
  final String apiKeySecret;
  final String from;
  final Duration timeout;
  final http.Client _client;

  @override
  ContactMethod get method => ContactMethod.phone;

  String get _credentials =>
      apiKeySid.isNotEmpty ? '$apiKeySid:$apiKeySecret' : '$accountSid:$authToken';

  Uri get endpoint =>
      Uri.https('api.twilio.com', '/2010-04-01/Accounts/$accountSid/Messages.json');

  @override
  Future<String?> send(String address, StaffAlert alert) async {
    final to = normalizePhoneNumber(address);
    if (to == null) throw AlertDeliveryException('not a phone number Twilio can text');
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Basic ${base64Encode(utf8.encode(_credentials))}',
            },
            // A Map body is sent form-encoded, which is what Twilio expects.
            body: {
              'To': to,
              if (from.startsWith('MG')) 'MessagingServiceSid': from else 'From': from,
              'Body': alert.smsBody,
            },
          )
          .timeout(timeout);
    } catch (e) {
      throw AlertDeliveryException('Twilio request failed: $e');
    }
    if (response.statusCode ~/ 100 != 2) {
      throw AlertDeliveryException(
          'Twilio HTTP ${response.statusCode}: ${_errorMessage(response.body)}');
    }
    return _field(response.body, 'sid');
  }
}

/// Emails alerts through Resend.
///
/// [from] must be on a domain verified in Resend, e.g.
/// `KW Hab Alerts <alerts@example.org>`. Resend's test sender
/// `onboarding@resend.dev` only delivers to the Resend account's own address.
class ResendEmailChannel implements AlertChannel {
  ResendEmailChannel({
    required this.apiKey,
    required this.from,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  static const String defaultFrom = 'KW Hab Alerts <onboarding@resend.dev>';
  static final Uri endpoint = Uri.https('api.resend.com', '/emails');

  final String apiKey;
  final String from;
  final Duration timeout;
  final http.Client _client;

  @override
  ContactMethod get method => ContactMethod.email;

  @override
  Future<String?> send(String address, StaffAlert alert) async {
    final to = address.trim();
    if (!to.contains('@')) throw AlertDeliveryException('not an email address');
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'from': from,
              'to': [to],
              'subject': alert.emailSubject,
              'text': '${alert.summary}\n\nSent at ${alert.at.toLocal()}',
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw AlertDeliveryException('Resend request failed: $e');
    }
    if (response.statusCode ~/ 100 != 2) {
      throw AlertDeliveryException(
          'Resend HTTP ${response.statusCode}: ${_errorMessage(response.body)}');
    }
    return _field(response.body, 'id');
  }
}

/// A phone number as typed in onboarding, in the E.164 form Twilio needs.
/// Numbers without a country code are taken as North American (+1).
/// Returns null when it can't be a phone number.
String? normalizePhoneNumber(String input) {
  final trimmed = input.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (trimmed.startsWith('+')) {
    return digits.length >= 8 && digits.length <= 15 ? '+$digits' : null;
  }
  if (digits.length == 10) return '+1$digits';
  if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
  return null;
}

String? _field(String body, String name) {
  try {
    final value = (jsonDecode(body) as Map)[name];
    if (value is String) return value;
  } catch (_) {}
  return null;
}

/// Twilio and Resend both put the reason in `message`.
String _errorMessage(String body) {
  try {
    final message = (jsonDecode(body) as Map)['message'];
    if (message is String) return message;
  } catch (_) {}
  return body.length > 300 ? '${body.substring(0, 300)}…' : body;
}
