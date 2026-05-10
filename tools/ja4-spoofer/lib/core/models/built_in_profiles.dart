import 'fingerprint_profile.dart';

/// Built-in fingerprint profiles.
///
/// Intentionally empty: library defaults (NSS / OpenSSL / BoringSSL "as-is")
/// are not imitation targets, and we do not ship synthetic browser profiles
/// here. Real profiles are added by the user via capture or import.
const builtInProfiles = <FingerprintProfile>[];
