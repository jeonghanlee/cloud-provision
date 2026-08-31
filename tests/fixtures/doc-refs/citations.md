# Doc-refs extraction fixture

Read by tests/check-doc-refs.bash. Its extraction self-test asserts that the
citation pattern finds exactly the pinned coordinates below - the live corpus
can legitimately hold zero citations (a register reset drops the content that
carried them), so pattern drift is detected here instead. The hashes are
deliberately fake: the self-test verifies extraction only, never resolution.
Editing this file changes what the self-test expects; keep the two in step.

A single-line coordinate: `bin/fixture.bash:12@0123abc`.

A range coordinate with a full-length hash:
`configure/fixture-data:3-9@abcdef0123456789abcdef0123456789abcdef01`.

Decoys the pattern must not extract: a non-local prefix
`vendor/tool.bash:5@0123abc`, a coordinate outside backticks
bin/fixture.bash:12@0123abc, and a plain word:12 pair.
