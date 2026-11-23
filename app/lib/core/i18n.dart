import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App language. English is the default; the EN/বাংলা switch in the top bar changes it
/// and the choice is remembered on the device.
enum Lang { en, bn }

Lang _current = Lang.en;
Lang get currentLang => _current;
bool get isBangla => _current == Lang.bn;

/// Inline translation: `t('My courses', 'আমার কোর্স')`.
/// Keeping both texts side by side means a new screen can never miss a translation.
String t(String en, String bn) => _current == Lang.bn ? bn : en;

/// Same as [t], for places where a local variable is already called `t`.
String tr(String en, String bn) => t(en, bn);

const _storage = FlutterSecureStorage();
const _key = 'lang';

/// Call once before runApp so the first frame is already in the saved language.
Future<void> loadSavedLang() async {
  try {
    _current = (await _storage.read(key: _key)) == 'bn' ? Lang.bn : Lang.en;
  } catch (_) {
    _current = Lang.en;
  }
}

final langProvider = NotifierProvider<LangController, Lang>(LangController.new);

class LangController extends Notifier<Lang> {
  @override
  Lang build() => _current;

  Future<void> set(Lang lang) async {
    if (lang == _current) return;
    _current = lang;
    state = lang;
    try {
      await _storage.write(key: _key, value: lang.name);
    } catch (_) {}
  }

  void toggle() => set(_current == Lang.en ? Lang.bn : Lang.en);
}
