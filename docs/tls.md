# TLS ClientHello and Cipher-Suite Order

JA4 Spoofer works by controlling fields in the TLS ClientHello. Cipher-suite
order matters because TLS defines the client list as an ordered preference list.

## TLS 1.2

TLS 1.2 defines `ClientHello.cipher_suites` in RFC 5246, section 7.4.1.2:

> This is a list of the cryptographic options supported by the client, with the
> client's first preference first.

That order is visible on the wire and is one of the signals used by TLS
fingerprinting systems.

## TLS 1.3

TLS 1.3 keeps the same preference-list idea in RFC 8446, section 4.1.2:

> A list of the symmetric cipher options [...] in descending order of client
> preference.

Servers must ignore cipher suites they do not recognize, do not support, or do
not want to use, then continue processing the remaining list. JA4 Spoofer uses
that tolerance for controlled experiments with reordered or synthetic offer
lists.
