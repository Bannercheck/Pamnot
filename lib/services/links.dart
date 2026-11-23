import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://github.com/Bannercheck/Pamnot/blob/main/PRIVACY.md';
const supportUrl = 'https://github.com/Bannercheck/Pamnot/issues';

typedef UrlOpener = Future<bool> Function(Uri uri);

/// Opens [uri] outside the app. Tests replace it to see what would open.
UrlOpener openExternal = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens Pamnot's page in the system Settings app, the only way back once a
/// permission was refused.
Future<bool> openAppSettings() => openExternal(Uri.parse('app-settings:'));
