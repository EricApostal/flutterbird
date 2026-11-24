import 'match_pattern.dart';

/// API permissions Firefox understands, each with the line its install
/// prompt shows, or null when the permission is granted without a prompt.
///
/// The wording follows Firefox's own prompts so that a user who has seen
/// them elsewhere reads the same thing here.
const Map<String, String?> apiPermissions = {
  'activeTab': null,
  'alarms': null,
  'background': null,
  'bookmarks': 'Read and modify bookmarks',
  'browserSettings': 'Read and modify browser settings',
  'browsingData': 'Clear recent browsing history, cookies, and related data',
  'captivePortal': null,
  'clipboardRead': 'Get data from the clipboard',
  'clipboardWrite': 'Input data to the clipboard',
  'contextMenus': null,
  'contextualIdentities': null,
  'cookies': null,
  'declarativeNetRequest': 'Block content on any page',
  'declarativeNetRequestFeedback': null,
  'declarativeNetRequestWithHostAccess': null,
  'devtools': 'Extend developer tools to access your data in open tabs',
  'dns': 'Access IP address and hostname information',
  'downloads':
      'Download files and read and modify the browser’s download history',
  'downloads.open': 'Open files downloaded to your computer',
  'find': 'Read the text of all open tabs',
  'geckoProfiler': 'Access browser performance information',
  'geolocation': 'Access your location',
  'history': 'Access browsing history',
  'identity': null,
  'idle': null,
  'management': 'Monitor extension usage and manage themes',
  'menus': null,
  'menus.overrideContext': null,
  'nativeMessaging': 'Exchange messages with programs other than Firefox',
  'notifications': 'Display notifications to you',
  'pageCapture': null,
  'pkcs11': 'Provide cryptographic authentication services',
  'privacy': 'Read and modify privacy settings',
  'proxy': 'Control browser proxy settings',
  'publicSuffix': null,
  'scripting': null,
  'search': 'Search the web',
  'sessions': 'Access recently closed tabs',
  'storage': null,
  'tabGroups': null,
  'tabHide': 'Hide and show browser tabs',
  'tabs': 'Access browser tabs',
  'theme': null,
  'topSites': 'Access browsing history',
  'unlimitedStorage': null,
  'userScripts': null,
  'webNavigation': 'Access browser activity during navigation',
  'webRequest': null,
  'webRequestAuthProvider': null,
  'webRequestBlocking': null,
  'webRequestFilterResponse': null,
  'webRequestFilterResponse.serviceWorkerScript': null,
};

bool isKnownPermission(String name) => apiPermissions.containsKey(name);

/// What an install or update prompt should tell the user.
class PermissionPrompt {
  const PermissionPrompt({
    this.hostLines = const [],
    this.apiLines = const [],
    this.dataCollectionLines = const [],
    this.hasAllSitesAccess = false,
  });

  /// Lines about which websites the extension can read and change.
  final List<String> hostLines;

  /// Lines about browser features the extension can use.
  final List<String> apiLines;

  /// Lines about the data the developer says the extension collects.
  final List<String> dataCollectionLines;

  /// True when the extension can reach every website.
  final bool hasAllSitesAccess;

  List<String> get lines => [...hostLines, ...apiLines];

  /// True when there is nothing to warn about, so no prompt is needed beyond
  /// "add this extension?".
  bool get isEmpty => hostLines.isEmpty && apiLines.isEmpty;
}

const int _maxNamedHosts = 4;

/// Builds the prompt for an extension that asks for [permissions] and
/// [hostPatterns].
PermissionPrompt describePermissions({
  required Iterable<String> permissions,
  required Iterable<String> hostPatterns,
  Iterable<String> requiredDataCollection = const [],
}) {
  final hostLines = <String>[];
  var allSites = false;

  final wildcardDomains = <String>{};
  final namedSites = <String>{};

  for (final source in hostPatterns) {
    final pattern = MatchPattern.tryParse(source);
    if (pattern == null) continue;

    if (pattern.isAllUrls) {
      allSites = true;
    } else if (pattern.host == null) {
      namedSites.add('local files');
    } else if (pattern.matchesSubdomains) {
      wildcardDomains.add(pattern.host!);
    } else {
      namedSites.add(pattern.host!);
    }
  }

  if (allSites) {
    hostLines.add('Access your data for all websites');
  } else {
    final domains = wildcardDomains.toList()..sort();
    final sites = namedSites.toList()..sort();

    for (final domain in domains.take(_maxNamedHosts)) {
      hostLines.add('Access your data for sites in the $domain domain');
    }
    final extraDomains = domains.length - _maxNamedHosts;
    if (extraDomains > 0) {
      hostLines.add(
        'Access your data in $extraDomains other '
        '${extraDomains == 1 ? 'domain' : 'domains'}',
      );
    }

    for (final site in sites.take(_maxNamedHosts)) {
      hostLines.add('Access your data for $site');
    }
    final extraSites = sites.length - _maxNamedHosts;
    if (extraSites > 0) {
      hostLines.add(
        'Access your data on $extraSites other '
        '${extraSites == 1 ? 'site' : 'sites'}',
      );
    }
  }

  final apiLines = <String>[];
  for (final permission in permissions) {
    final line = apiPermissions[permission];
    // Several permissions share a sentence (topSites and history, say).
    if (line != null && !apiLines.contains(line)) apiLines.add(line);
  }

  return PermissionPrompt(
    hostLines: hostLines,
    apiLines: apiLines,
    dataCollectionLines: _describeDataCollection(requiredDataCollection),
    hasAllSitesAccess: allSites,
  );
}

List<String> _describeDataCollection(Iterable<String> required) {
  final categories = required.toSet();
  if (categories.isEmpty) return const [];

  if (categories.length == 1 && categories.first == 'none') {
    return const [
      "The developer says this extension doesn't require data collection.",
    ];
  }

  final names = [
    for (final category in categories)
      if (category != 'none') _humanize(category),
  ]..sort();
  if (names.isEmpty) return const [];
  return ['The developer says this extension collects: ${names.join(', ')}.'];
}

/// `browsingActivity` → `browsing activity`.
String _humanize(String camelCase) {
  return camelCase
      .replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => ' ${match.group(0)!.toLowerCase()}',
      )
      .trim();
}

/// Everything in [next] that [granted] does not already cover. Used by
/// updates, which prompt only for what is new.
List<String> addedPermissions({
  required Iterable<String> granted,
  required Iterable<String> next,
}) {
  final have = granted.toSet();
  return [
    for (final permission in next)
      if (!have.contains(permission)) permission,
  ];
}
