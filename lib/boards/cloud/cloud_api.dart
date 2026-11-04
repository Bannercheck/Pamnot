import '../sync/backend.dart';

/// Why connecting to the collaboration server failed, in the terms the setup
/// wizard and the join sheet explain to people.
enum CloudProblem {
  /// No network, DNS, TLS, timeouts, 5xx.
  unreachable,

  /// The server rejected the publishable key (401/403).
  badKey,

  /// `pamnot_info` is missing: the setup SQL was not run (wizard step 2).
  sqlMissing,

  /// The SQL is from an older version of Pamnot.
  sqlOutdated,

  /// Anonymous sign-ins are off (wizard step 3).
  anonymousDisabled,

  /// New sign-ups are off for the project.
  signupsDisabled,

  /// Too many attempts; try again later.
  rateLimited,

  /// This device already uses another server.
  otherServer,

  unknown,
}

class CloudFailure implements Exception {
  const CloudFailure(this.problem, [this.cause]);

  final CloudProblem problem;
  final Object? cause;

  @override
  String toString() => 'CloudFailure($problem, $cause)';
}

/// The network side of [CloudService], behind an interface so the service is
/// testable without a server. Production: SupabaseCloudApi. Methods throw
/// [CloudFailure].
abstract class CloudApi {
  /// Creates the client for [url] and [key], restoring a saved session for
  /// that server if there is one. At most one client exists at a time.
  Future<void> start(String url, String key);

  /// Removes every channel, signs out when [signOut] (this destroys an
  /// anonymous identity) and disposes the client.
  Future<void> stop({required bool signOut});

  /// The signed-in user of the started client, or null.
  String? get userId;

  /// Called when the session ends without [stop] (revoked, expired for good).
  set onSignedOut(void Function()? callback);

  /// Reaches the server with the key (`/auth/v1/settings`).
  Future<void> probe();

  /// `pamnot_info()` → `schema`.
  Future<int> schemaVersion();

  /// Signs in anonymously with [name] as metadata; returns the user id.
  Future<String> signInAnonymously(String name);

  /// Upserts the caller's row in `profiles`.
  Future<void> saveProfile(String name, int colorIndex);

  /// The board backend on the started client.
  BoardBackend backend(String host);
}
