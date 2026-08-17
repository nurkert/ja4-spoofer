/// The patched TLS stack a launch target is built against.
///
/// Every enforcement guarantee in this app is stack-specific: the same profile
/// reaches the wire differently through BoringSSL, NSS and OpenSSL, because
/// each patch can rewrite a different subset of the ClientHello. Callers derive
/// this from [AppLaunchConfig.profileFormat].
enum Ja4Stack {
  boringssl('BoringSSL'),
  nss('NSS'),
  openssl('OpenSSL');

  const Ja4Stack(this.displayName);

  /// Human-readable name used in enforcement messages.
  final String displayName;

  /// Maps a descriptor's `profile_format` to a stack, or null when the target
  /// is not one of the three patched libraries.
  static Ja4Stack? fromProfileFormat(String? profileFormat) =>
      switch (profileFormat) {
        'boringssl' => Ja4Stack.boringssl,
        'nss' => Ja4Stack.nss,
        'openssl' => Ja4Stack.openssl,
        _ => null,
      };
}
