# Third-Party and Open-Source Notices

KT Wallet is licensed under MPL-2.0. Its Flutter/Dart dependency lockfile is
`pubspec.lock`; native iOS dependency versions are recorded in each
`Podfile.lock`, and Android dependencies are resolved by Gradle.

Important security and runtime components include:

- Trust Wallet Core — wallet derivation and transaction signing
  (Apache-2.0).
- Flutter and Dart — application runtime and UI framework (BSD-style
  licenses).
- drift and SQLite — local structured persistence (MIT / public domain).
- cryptography and Pointy Castle — signature verification primitives
  (BSD-style licenses).
- local_auth, mobile_scanner and flutter_secure_storage — platform
  authentication, camera scanning and protected local metadata storage
  (BSD-style licenses).

This summary is not a replacement for the copyright and license files shipped
by each dependency. Release packaging must generate the complete notices from
the resolved dependency graph and preserve every upstream license.
