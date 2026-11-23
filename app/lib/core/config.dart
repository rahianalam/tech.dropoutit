/// Build with `--dart-define=API_URL=https://api.tech.dropout.it/api/v1` for release.
/// Android emulator reaches the host machine at 10.0.2.2.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000/api/v1');
