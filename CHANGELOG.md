# Changelog

Notable changes to jsonlib. Format follows [Keep a Changelog](https://keepachangelog.com/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`0.1.0-dev`, no tag: the crates that use this one — adash, and anything reading
or writing JSON beside it — pin it **by path**, so the commit is the version
until that changes. A consumer's release records which commit it was verified
against.

## [Unreleased]

### Added

- The whole crate: [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) read and
  written exactly, with no lenient mode — no comments, trailing commas,
  unquoted keys, single quotes, `NaN`, hexadecimal or leading zeros. A parser
  that quietly accepts more than the standard produces documents other tools
  reject, and the author hears about it from somebody else's error message.

## Releasing

No procedure yet. What it has to settle first is whether consumers keep pinning
by path; a tag on a crate nobody resolves by version is a label rather than a
release.
