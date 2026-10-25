# General-server proxy check contract

`bin/proxy_contract.bash check --input-fd N` inspects the six general-server
proxy artifacts on Rocky Linux 8.10. It compares their contents with explicit
site inputs and returns a value-free readiness result. The checker reads
configuration as data and never sources a profile or an input file.

## Execution and source identity

| Property | Requirement |
| --- | --- |
| Production execution | Root, through `/bin/bash -p` |
| Parser | `/usr/bin/python3`, or `/usr/libexec/platform-python` when the first path is absent; Python runs with `-I -B` |
| Source | One complete `proxy_contract.bash` artifact, with the SHA-256 supplied in the private input |
| Source file | A regular file with one hard link, the execution account's ownership, and safe permissions |
| Source FD | `/proc/self/fd/N` or `/dev/fd/N`; an anonymous source must have write, shrink, grow, and seal seals |
| Input FD | Descriptor `3` through `63`, open read-only, backed by a regular file or a memory file |
| Input permissions | Root:root, mode `0600` in production; one hard link for a persistent file |
| Local test execution | `--test-root` selects an existing absolute directory, owned by the test account; `/` is rejected |

The caller opens the persistent input after becoming root. The server owns
that input and its values; neither an inline value nor its base64 encoding
belongs in the raw command or process arguments. A public source transported
through a memory file does not make inline private input safe.
The embedded parser travels as public Python source in `-c`; it uses no shell
heredoc. Private values enter only through the input descriptor.

The checker validates the actual execution source against `script_sha256`.
A source streamed only to Bash's standard input has no source binding and
does not satisfy this interface. A memory source must remain sealed throughout
execution. The caller must authenticate the source before executing it;
the checker's checksum does not authorize execution of untrusted code.

## Private input fields

The descriptor contains ASCII `key=value` lines separated by LF, with exactly
these seven fields. A final LF is optional. Blank lines, carriage returns,
and other control characters are rejected. Field order is arbitrary.
Duplicate, missing, and unknown fields are rejected. Values never enter
shell evaluation.

| Field | Accepted value |
| --- | --- |
| `schema` | `3` |
| `scope` | `general-server` |
| `existing_keys` | `reconcile` |
| `proxy_url` | `http://` or `https://`, a nonempty host using letters, digits, dots, and hyphens, an optional decimal port from 1 to 65535 without leading zeros, and an optional trailing slash |
| `no_proxy` | Explicit comma-separated site bypass text; letters, digits, dots, commas, colons, slashes, underscores, wildcards, plus signs, and hyphens; empty is accepted |
| `maven_non_proxy_hosts` | Explicit Maven bypass text; letters, digits, dots, wildcards, colons, underscores, hyphens, and pipe separators; empty is accepted |
| `script_sha256` | Lowercase, 64-character SHA-256 of the complete executed Bash source |

Proxy credentials, IPv6 proxy authorities, URL queries, and URL fragments
are outside the supported URL grammar. Site bypass values are explicit;
the checker supplies no cloud default and derives no value from a login shell.
Input is limited to 64 KiB, each configuration file to 1 MiB, and source to 4 MiB.

Schema 3 selects this read-only check. `existing_keys=reconcile` permits
checking matching unmarked assignments; it does not perform a reconciliation.
The writing commands retain their schema-1 and schema-2 contracts.

## Configuration files and supported syntax

The producer's general-server inventory supplies the paths. The independent
tuple fixture is `tests/fixtures/proxy-general-server-artifacts.tsv`.

| Identity | Path | Required values |
| --- | --- | --- |
| `profile` | `/etc/profile.d/95cloud-provision-proxy.sh` | Eight exported lower-case and upper-case HTTP, HTTPS, FTP, and bypass variables |
| `environment` | `/etc/environment` | The same eight variables as assignments |
| `dnf` | `/etc/dnf/dnf.conf` | `proxy` in `[main]` |
| `pip` | `/etc/pip.conf` | `proxy` in `[global]` |
| `git` | `/etc/gitconfig` | `proxy` in `[http]` and `[https]` |
| `maven` | `/etc/maven-proxy-settings.xml` | One explicitly active HTTP proxy and one explicitly active HTTPS proxy, with the desired host, port, and bypass text |

Profile and environment files support literal single assignments, single or
double quoted values, blank lines, and hash comments separated by whitespace.
Profile assignments require `export` for proxy variables and no whitespace
around `=`. A quoted reference to an earlier proxy assignment is
accepted in a profile, including the producer's upper-case aliases.
Other expressions, shell commands, and command substitutions are rejected.
Configuration uses LF line endings; control characters and other whitespace
separators are rejected.

INI files support section headers, `key=value` lines, blank lines, and hash
or semicolon comment lines. Git values support complete double quoted literals
or unquoted literals, with hash or semicolon comments. Single quotes are literal
characters in Git values. Backslash escapes and concatenated quoted fragments
are rejected, including in unrelated assignments. Git section and key names
are case insensitive, as defined by the [Git configuration syntax](https://git-scm.com/docs/git-config#_syntax).
DNF and pip require the exact sections `[main]` and `[global]`, respectively,
and the exact key `proxy`. Their proxy values must be literal and unquoted.
DNF and pip entries cannot be indented or continued onto another line.
Duplicate sections, duplicate INI keys, duplicate Git proxy keys, proxy overrides
outside the required sections, and Git includes are rejected.
Unrelated assignments and sections do not affect comparisons.

Maven accepts a `settings` root with either the Maven 1.0.0 namespace or no
namespace. Proxy entries require explicit `active=true`; `active=false`
entries are ignored. Duplicate active protocols or IDs, duplicate proxy
fields, credentials, malformed XML, and DTD or entity declarations are rejected.
The Maven host is compared exactly as written in `proxy_url`, as in every
other file, with no case folding. Other Maven settings are not comparison
inputs.

All six files and their parent directories must have root ownership, root
read access, and safe permissions in production. Directories also require
root search access. Group or world write permissions and special mode bits
are rejected. Files must be regular with exactly one hard link. Parent
symlinks, leaf symlinks, and non-regular files are rejected.

`/etc/os-release` is read as data. Its standard relative link is accepted
only within the selected root, with safe ownership and path components.
The resolved `ID` and `VERSION_ID` must be `rocky` and `8.10`.

## Results and caller rules

| Exit code | Result | Caller behavior |
| --- | --- | --- |
| `0` | All six files match and pass safety checks | Accept the prerequisite |
| `2` | A required file or key is missing, or a value differs | Report preparation required; a group or focused install must stop |
| `1` | Invalid input, unsupported syntax, unsafe filesystem state, source mismatch, concurrent change, or an inspection error | Stop and report the safe diagnostic |

A successful inspection emits exactly one stdout line. For prepared files:

```text
proxy_contract schema=3 mode=check scope=general-server os=rocky identities=6 status=ready
```

For missing or different settings, the same line ends with `status=needs-change`.
An exit-1 result has no success stdout. Stderr contains only fixed identity,
key, and reason tokens, with this shape:

```text
proxy_contract identity=maven key=content reason=missing-file
```

Callers must validate both the exit status and the exact stdout shape.
An Ansible check task must execute the checker with `check_mode: false`,
retain `no_log` on private transport, and expose only validated diagnostics.
Ansible's `--check` flag alone does not inspect the proxy configuration.

## Read-only inspection boundaries

The checker creates no configuration, runtime directory, temporary file,
lock, or receipt. It opens configuration with no-follow and no-atime flags
and checks content and metadata again before returning. It also rechecks
input and source metadata. It preserves existing file contents and metadata.

An applied lock under `/run` is neither read nor required. Matching files
remain ready after runtime state is lost. No schema-2 lock migration occurs.
The checker does not inspect accounts, SSH configuration, sudo configuration,
other profile scripts, repository-specific configuration files, or process
environment overrides. Readiness describes the listed files; callers also
need verification in their actual Ansible and detached build contexts.

## Local verification command

The local suite runs the shipped Bash CLI, the real schema-2 reconciliation,
and the installed Ansible raw/local path against shipped filesystem fixtures:

```bash
make check-proxy-checker
```

The suite requires Linux memory-file support and Python 3.8 or later.
The raw probe runs when `ansible-playbook` is installed. Native pip comparisons
run when `pip` is installed; native Git comparisons require `git`.

It covers unmarked and managed files, missing and different values, runtime
loss, unsafe paths and syntax, inherited startup configuration, private
descriptors, source binding, and unchanged filesystem snapshots. The raw
probe executes under `--check` with `become=false`. Native root/become
execution and physical-target readiness require their own target evidence.
