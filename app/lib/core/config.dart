/// Build with `--dart-define=API_URL=https://api.tech.dropout.it/api/v1` for release.
/// Android emulator reaches the host machine at 10.0.2.2.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000/api/v1');

/// Public site for the privacy policy and account-deletion pages.
const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://api.tech.dropout.it');

/// Play Store / App Store builds (`--dart-define=STORE_BUILD=true`): recorded courses are
/// bought on the website, not in the app, to follow the stores' payment rules for digital
/// content. Free courses, bought courses and paid 1:1 sessions work as usual.
const storeBuild = bool.fromEnvironment('STORE_BUILD');
