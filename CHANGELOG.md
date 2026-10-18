# Changelog

## 1.1.0 — 2026-10-18

- Update check at start: one console line when a newer release is out on
  GitHub. Silent otherwise; `set doorman_version_check false` turns it off.
- `escrow_ignore` in the manifest, so the resource stays fully readable when
  it is delivered as a Cfx.re asset.
- Releases are built by CI from a tag: tests, a check that the tag matches the
  manifest, then `doorman-vX.Y.Z.zip` attached to the release.

## 1.0.0 — 2026-10-18

- First release: `rate`, `cooldown`, `schema` and `exempt` in front of every
  net event, one shared tally per player, 86 tests that run without a server.
