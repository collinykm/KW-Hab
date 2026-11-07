import 'package:url_launcher/url_launcher.dart';

const String kHomeUrl = 'https://www.facebook.com/';

/// Hosts that stay inside the app. Everything else opens in the default browser.
const List<String> kInAppDomains = [
  'facebook.com',
  'facebook.net',
  'fb.com',
  'fb.me',
  'fbcdn.net',
  'fbsbx.com',
  'messenger.com',
  'meta.com',
];

/// Facebook's outbound link shims (l.facebook.com/l.php?u=...).
const List<String> kLinkShimHosts = ['l.facebook.com', 'lm.facebook.com', 'l.messenger.com'];

bool isInAppHost(String host) {
  host = host.toLowerCase();
  return kInAppDomains.any((d) => host == d || host.endsWith('.$d'));
}

/// Returns the external destination for a link, or null if it should load in-app.
Uri? externalTarget(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isEmpty || const ['about', 'data', 'blob', 'javascript'].contains(scheme)) {
    return null;
  }
  if (scheme != 'http' && scheme != 'https') {
    // mailto:, tel:, itms-apps:, etc.
    return uri;
  }
  if (kLinkShimHosts.contains(uri.host.toLowerCase())) {
    final target = uri.queryParameters['u'];
    final parsed = target == null ? null : Uri.tryParse(target);
    if (parsed != null && !isInAppHost(parsed.host)) return parsed;
    return null;
  }
  return isInAppHost(uri.host) ? null : uri;
}

Future<void> openExternally(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
