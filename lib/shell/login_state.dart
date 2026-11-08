import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Facebook sets the `c_user` cookie (the account's numeric id) once someone
/// is logged in, and clears it on logout.
const String kFacebookUserCookie = 'c_user';

/// The logged-in Facebook account id in [controller]'s cookie store, or null
/// when nobody is logged in.
Future<String?> loggedInUserId(InAppWebViewController controller) async {
  try {
    final cookie = await CookieManager.instance().getCookie(
      url: WebUri('https://www.facebook.com/'),
      name: kFacebookUserCookie,
      webViewController: controller,
    );
    final value = cookie?.value?.toString() ?? '';
    return value.isEmpty ? null : value;
  } catch (e) {
    debugPrint('[kw-hab:shell] could not read login cookie: $e');
    return null;
  }
}

Future<bool> isLoggedIn(InAppWebViewController controller) async =>
    await loggedInUserId(controller) != null;
