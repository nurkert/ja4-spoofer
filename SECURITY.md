# Security Policy

## Scope

JA4 Spoofer patches TLS stacks (BoringSSL, NSS, OpenSSL) to enable controlled
ClientHello / JA4 fingerprint experiments. It is intended for:

- Interoperability testing against TLS deployments you control or are
  authorized to test.
- Defensive analysis — building detections, training models, validating
  fingerprint coverage.
- Academic research on TLS fingerprinting.

It is **not** intended for, and the maintainers do not condone:

- Evading abuse detection or rate limiting on services you do not own.
- Circumventing access controls, paywalls, or terms-of-service restrictions.
- Bulk impersonation or credential-stuffing infrastructure.

Use responsibly. The patches you build with this tool inherit the
licenses of their upstream projects; modifying them does not lift your
obligations under those licenses or applicable law.

## Reporting a vulnerability

If you find a security issue **in JA4 Spoofer itself** (not in the patched
upstream TLS stacks — those have their own disclosure processes), please:

1. Do **not** open a public GitHub issue.
2. Email the maintainer at the address in the repository commit history.
3. Include a description, a minimal reproducer, and the commit SHA you
   tested against.

You can expect an initial response within 7 days. Coordinated disclosure
windows depend on severity; the maintainer will agree on a timeline with
you before any public write-up.

## Threat model

A few classes of issue *are* in scope:

- Shell injection or arbitrary-code-execution paths reachable from user
  data (profile JSON, captured fingerprints, descriptor YAMLs).
- Local privilege escalation via files the app writes
  (`~/.ja4-spoofer/runtime/<version>/`).
- Tampering attacks where a malicious profile causes the app to overwrite
  data outside the runtime directory.

Out of scope:

- Network-level fingerprint detectability (that is the point of the tool).
- Vulnerabilities in upstream BoringSSL / NSS / OpenSSL — report those to
  the respective projects.
- Issues that require an attacker to already have local code execution.
