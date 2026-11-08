import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kw_hab/injections/injection_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InjectionBundle bundle;
  setUpAll(() async => bundle = await InjectionBundle.load(rootBundle));

  test('discovers area files from every folder', () {
    expect(bundle.css.keys, contains('hide-right-column'));
    expect(bundle.css['hide-right-column'], contains('role="complementary"'));
  });

  test('ignores files starting with an underscore', () {
    expect(bundle.js.keys.where((k) => k.startsWith('_')), isEmpty);
    expect(bundle.html.keys.where((k) => k.startsWith('_')), isEmpty);
  });

  test('runtime gets the html templates in place of its placeholder', () {
    final script = bundle.runtimeScript();
    expect(script, isNot(contains('__KW_HAB_HTML__')));
    expect(script, contains('window.kwHab'));
  });

  test('sensitive info warning ships its css, js and popup template', () {
    expect(bundle.css.keys, contains('sensitive-info'));
    expect(bundle.js.keys, contains('sensitive-info'));
    expect(bundle.html['sensitive-info'], contains('Do you want to proceed?'));
  });

  test('one user script per js area, plus css bootstrap and runtime', () {
    expect(bundle.userScripts(), hasLength(2 + bundle.js.length));
  });
}
