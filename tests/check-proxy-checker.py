#!/usr/bin/env python3
"""Exercise the shipped check command against filesystem and descriptor boundaries."""

import ctypes
import fcntl
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest

TOP = Path(__file__).resolve().parent.parent
SOURCE = TOP / 'bin/proxy_contract.bash'
FIXTURE = TOP / 'tests/fixtures/proxy-general-server-unmarked'
MANIFEST = TOP / 'tests/fixtures/proxy-general-server-artifacts.tsv'
SOURCE_BYTES = SOURCE.read_bytes()
SOURCE_HASH = hashlib.sha256(SOURCE_BYTES).hexdigest()
READY = ('proxy_contract schema=3 mode=check scope=general-server os=rocky '
         'identities=6 status=ready\n')
NEEDS_CHANGE = READY.replace('status=ready', 'status=needs-change')
INPUT = (FIXTURE / 'desired.input').read_text().replace('@SCRIPT_SHA256@', SOURCE_HASH)
ROWS = [line.split('\t') for line in MANIFEST.read_text().splitlines()[1:]]
PATHS = {row[1]: row[2].lstrip('/') for row in ROWS}


def memory_fd(name, data, sealed=True, mode=0o600):
    writer = os.memfd_create(name, os.MFD_ALLOW_SEALING)
    try:
        os.fchmod(writer, mode)
        os.write(writer, data)
        if sealed:
            fcntl.fcntl(writer, fcntl.F_ADD_SEALS, 15)
        reader = os.open('/proc/self/fd/' + str(writer), os.O_RDONLY)
    finally:
        os.close(writer)
    return reader


def snapshot(root):
    result = {}
    for directory, names, filenames in os.walk(root, followlinks=False):
        for name in sorted(names + filenames):
            path = Path(directory) / name
            value = path.lstat()
            data = None
            if stat.S_ISREG(value.st_mode):
                fd = os.open(path, os.O_RDONLY | os.O_NOATIME)
                try:
                    data = os.read(fd, value.st_size + 1)
                finally:
                    os.close(fd)
            result[str(path.relative_to(root))] = (
                value.st_ino, value.st_mode, value.st_uid, value.st_gid,
                value.st_size, value.st_mtime_ns, value.st_ctime_ns,
                value.st_atime_ns if stat.S_ISREG(value.st_mode) else None,
                data, os.readlink(path) if stat.S_ISLNK(value.st_mode) else None)
    return result


class ProxyChecker(unittest.TestCase):
    def run(self, result=None):
        completed = False
        outcome = result
        try:
            outcome = super().run(result)
            completed = True
            return outcome
        finally:
            if hasattr(self, 'workspace'):
                failed = not completed or any(
                    test is self or getattr(test, 'test_case', None) is self
                    for test, _ in outcome.failures + outcome.errors)
                if failed or os.environ.get('KEEP_WORKSPACE') == '1':
                    print('Retained workspace: ' + str(self.workspace), file=sys.stderr)
                else:
                    shutil.rmtree(self.workspace)

    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        self.workspace = Path(tempfile.mkdtemp(prefix='proxy-checker-'))
        self.root = self.workspace / 'root'
        self.source = self.workspace / 'proxy_contract.bash'
        self.source.write_bytes(SOURCE_BYTES)
        self.source.chmod(0o700)
        shutil.copytree(FIXTURE / 'etc', self.root / 'etc')
        self.root.chmod(0o700)
        for path in self.root.rglob('*'):
            path.chmod(0o755 if path.is_dir() else 0o644)

    def file(self, identity):
        return self.root / PATHS[identity]

    def execute(self, text=INPUT, source=None, extra=(), input_fd=None, pass_fds=(), env=None):
        owned = input_fd is None
        descriptor = memory_fd('proxy-check-input', text.encode()) if owned else input_fd
        try:
            before = snapshot(self.root)
            result = subprocess.run(
                ['/bin/bash', '-p', str(source or self.source), '--test-root', str(self.root),
                 'check', '--input-fd', str(descriptor), *extra],
                pass_fds=(descriptor, *pass_fds), capture_output=True, text=True, timeout=20, env=env)
            self.assertEqual(before, snapshot(self.root), 'checker changed target filesystem')
            self.assertNotIn('proxy.example.org', result.stdout + result.stderr)
            self.assertNotIn('Traceback', result.stderr)
            return result
        finally:
            if owned:
                os.close(descriptor)

    def expect(self, result, rc):
        self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
        self.assertEqual(result.stdout, READY if rc == 0 else NEEDS_CHANGE if rc == 2 else '')
        self.assertNotIn('reason=internal-error', result.stderr)

    def test_unmarked_ready_without_runtime_or_accounts(self):
        self.assertEqual(len(ROWS), 6)
        for row in ROWS:
            self.assertTrue((self.root / row[2].lstrip('/')).is_file())
        self.expect(self.execute(), 0)
        self.expect(self.execute(), 0)
        self.assertFalse((self.root / 'run').exists())
        self.assertFalse((self.root / 'etc/passwd').exists())

    def test_every_missing_or_different_artifact(self):
        for identity in PATHS:
            with self.subTest(identity=identity):
                path = self.file(identity)
                data = path.read_bytes()
                path.unlink()
                self.expect(self.execute(), 2)
                path.write_bytes(data.replace(b'proxy.example.org', b'other.example.org'))
                self.expect(self.execute(), 2)
                path.write_bytes(data)

    def test_partial_keys_and_missing_parent(self):
        path = self.file('environment')
        path.write_text('http_proxy="http://proxy.example.org:3128"\n')
        self.expect(self.execute(), 2)
        shutil.rmtree(self.file('dnf').parent)
        self.expect(self.execute(), 2)

    def test_duplicates_overrides_and_shell_code_refused(self):
        cases = (
            ('environment', '\nhttp_proxy=http://proxy.example.org:3128\n'),
            ('profile', '\nexport http_proxy="http://proxy.example.org:3128"\n'),
            ('dnf', '\n[main]\nproxy=http://proxy.example.org:3128\n'),
            ('pip', '\n[install]\nproxy=http://proxy.example.org:3128\n'),
            ('git', '\n[http "https://example.org"]\nproxy=http://proxy.example.org:3128\n'),
            ('git', '\n[include]\npath=/etc/other.gitconfig\n'),
            ('profile', '\nsource /etc/other-profile\n'),
            ('profile', '\nexport EVIL=$(touch /tmp/proxy-checker-must-not-execute)\n'),
            ('environment', '\nUNKNOWN_FIELD=$(printf private)\n'),
        )
        for identity, addition in cases:
            with self.subTest(identity=identity, addition=addition):
                path = self.file(identity)
                original = path.read_text()
                path.write_text(original + addition)
                self.expect(self.execute(), 1)
                path.write_text(original)

    def test_invalid_profile_assignment_is_not_ready(self):
        path = self.file('profile')
        original = path.read_text()
        for replacement in ('export http_proxy ="http://proxy.example.org:3128"',
                            'export http_proxy= "http://proxy.example.org:3128"',
                            'export http_proxy="http://proxy.example.org:3128"#suffix',
                            'export http_proxy="http://proxy.example.org:3128"\r'):
            with self.subTest(replacement=replacement):
                path.write_text(original.replace(
                    'export http_proxy="http://proxy.example.org:3128"', replacement))
                actual = subprocess.run(
                    ['/bin/bash', '-p', '-c', '. "$1"; printf "%s" "${http_proxy-}"',
                     'profile-probe', str(path)], env={'PATH': '/usr/bin:/bin'},
                    capture_output=True, text=True, timeout=20)
                self.assertNotEqual(actual.stdout, 'http://proxy.example.org:3128')
                self.expect(self.execute(), 1)
        path.write_text(original.replace('"http://proxy.example.org:3128"\n',
                                         '"http://proxy.example.org:3128" # Site comment.\n'))
        self.expect(self.execute(), 0)

    def test_profile_alias_comments_match_native_bash(self):
        path = self.file('profile')
        original = path.read_text()
        for alias in ('"$http_proxy"', '"${http_proxy}"'):
            for comment in (' # Site alias.', '\t# "$unknown" $(printf ignored)'):
                with self.subTest(alias=alias, comment=comment):
                    path.write_text(original.replace('export HTTP_PROXY="$http_proxy"',
                                                     'export HTTP_PROXY=' + alias + comment))
                    actual = subprocess.run(
                        ['/bin/bash', '-p', '-c', '. "$1"; printf "%s" "$HTTP_PROXY"',
                         'profile-probe', str(path)], env={'PATH': '/usr/bin:/bin'},
                        capture_output=True, text=True, timeout=20)
                    self.assertEqual(actual.returncode, 0, actual.stderr)
                    self.assertEqual(actual.stdout, 'http://proxy.example.org:3128')
                    self.expect(self.execute(), 0)
        for suffix in ('#suffix', ' # Comment.\r', 'suffix'):
            with self.subTest(suffix=suffix):
                path.write_text(original.replace('export HTTP_PROXY="$http_proxy"',
                                                 'export HTTP_PROXY="$http_proxy"' + suffix))
                self.expect(self.execute(), 1)

    def test_control_characters_refused_in_every_artifact(self):
        controls = [value for value in range(32) if value not in (9, 10)] + list(range(127, 160))
        for identity in PATHS:
            path = self.file(identity)
            original = path.read_bytes()
            for value in controls:
                with self.subTest(identity=identity, codepoint=value):
                    marker = chr(value).encode('utf-8')
                    comment = b'<!-- Control: ' + marker + b' -->\n' if identity == 'maven' \
                        else b'# Control: ' + marker + b'\n'
                    path.write_bytes(original + comment)
                    self.expect(self.execute(), 1)
            path.write_bytes(original)

    def test_git_literals_match_native_git(self):
        path = self.file('git')
        original = path.read_text()
        expected = 'http://proxy.example.org:3128'
        for replacement, actual_value, checker_rc in (
                ('"' + expected + '" # Site comment.', expected, 0),
                (expected + '#suffix', expected, 0),
                ("'" + expected + "'", "'" + expected + "'", 2)):
            with self.subTest(replacement=replacement):
                path.write_text(original.replace('"' + expected + '"', replacement)
                                .replace('    proxy = ' + expected + '\n',
                                         '    proxy = ' + replacement + '\n'))
                actual = subprocess.run(
                    ['git', 'config', '--file', str(path), '--get', 'http.proxy'],
                    env={'PATH': '/usr/bin:/bin', 'GIT_CONFIG_NOSYSTEM': '1'},
                    capture_output=True, text=True, timeout=20)
                self.assertEqual(actual.returncode, 0, actual.stderr)
                self.assertEqual(actual.stdout, actual_value + '\n')
                self.expect(self.execute(), checker_rc)
        path.write_text(original + '\n[core]\neditor="unterminated\n')
        actual = subprocess.run(
            ['git', 'config', '--file', str(path), '--list'],
            env={'PATH': '/usr/bin:/bin', 'GIT_CONFIG_NOSYSTEM': '1'},
            capture_output=True, text=True, timeout=20)
        self.assertNotEqual(actual.returncode, 0)
        self.expect(self.execute(), 1)
        path.write_text(original.replace('[http]', '[HTTP]').replace('proxy =', 'PROXY ='))
        self.expect(self.execute(), 0)

    def test_ini_section_and_key_case(self):
        for identity, section in (('dnf', 'main'), ('pip', 'global')):
            path = self.file(identity)
            original = path.read_text()
            with self.subTest(identity=identity):
                path.write_text(original.replace('[' + section + ']', '[' + section.upper() + ']'))
                self.expect(self.execute(), 1)
                path.write_text(original.replace('proxy=', 'PROXY=').replace('proxy =', 'PROXY ='))
                self.expect(self.execute(), 1)
                path.write_text(original)

    def test_ini_continuations_and_unrelated_duplicates(self):
        for identity in ('dnf', 'pip'):
            path = self.file(identity)
            original = path.read_text()
            section = 'main' if identity == 'dnf' else 'global'
            with self.subTest(identity=identity):
                path.write_text(original.replace('proxy', '    proxy', 1))
                self.expect(self.execute(), 1)
                path.write_text(original.replace('[' + section + ']',
                                                 '[' + section + ']\nother=1\nother=2'))
                self.expect(self.execute(), 1)
                path.write_text(original)

    @unittest.skipUnless(shutil.which('pip'), 'pip is unavailable')
    def test_pip_section_and_continuation_match_native_pip(self):
        path = self.file('pip')
        original = path.read_text()
        environment = {'PATH': '/usr/bin:/bin', 'HOME': str(self.workspace),
                       'PIP_CONFIG_FILE': str(path), 'PIP_DISABLE_PIP_VERSION_CHECK': '1'}
        for text, rc in ((original, 0),
                         (original.replace('[global]', '[GLOBAL]'), 1),
                         (original.replace('[global]\nproxy', '[global]\nother=1\n    proxy'), 1)):
            path.write_text(text)
            actual = subprocess.run([shutil.which('pip'), 'config', 'list'],
                                    env=environment, capture_output=True, text=True, timeout=20)
            self.assertEqual(actual.returncode, 0, actual.stderr)
            values = dict(line.split('=', 1) for line in actual.stdout.splitlines() if '=' in line)
            if rc == 0:
                self.assertEqual(values.get('global.proxy'), "'http://proxy.example.org:3128'")
            else:
                self.assertNotIn('global.proxy', values)
            self.expect(self.execute(), rc)

    def test_xml_structure_entities_duplicates_and_credentials(self):
        path = self.file('maven')
        original = path.read_text()
        variants = (
            original.replace('<port>3128</port>', '<port>3128</port><port>3128</port>'),
            original.replace('<protocol>https</protocol>', '<protocol>http</protocol>'),
            original.replace('<active>true</active>', '<active>true</active><password>private</password>'),
            original.replace('<active>true</active>', ''),
            original.replace('<?xml version="1.0" encoding="UTF-8"?>',
                             '<!DOCTYPE settings [<!ENTITY proxy "private">]>'),
            original.replace('</settings>', ''),
        )
        for variant in variants:
            with self.subTest(variant=variant[:60]):
                path.write_text(variant)
                self.expect(self.execute(), 1)
        path.write_text(original.replace('xmlns="http://maven.apache.org/SETTINGS/1.0.0"', ''))
        self.expect(self.execute(), 0)

    def test_unsafe_files_and_directories_refused(self):
        for identity in PATHS:
            with self.subTest(identity=identity):
                path = self.file(identity)
                data = path.read_bytes()
                path.chmod(0o666)
                self.expect(self.execute(), 1)
                path.chmod(0o644)
                os.link(path, self.workspace / 'hardlink')
                self.expect(self.execute(), 1)
                (self.workspace / 'hardlink').unlink()
                path.unlink()
                path.symlink_to(self.workspace / 'outside')
                self.expect(self.execute(), 1)
                path.unlink()
                os.mkfifo(path)
                self.expect(self.execute(), 1)
                path.unlink()
                path.write_bytes(data)
        parent = self.file('dnf').parent
        parent.chmod(0o777)
        self.expect(self.execute(), 1)
        parent.chmod(0o755)
        shutil.rmtree(parent)
        parent.symlink_to(self.workspace)
        self.expect(self.execute(), 1)

    def test_inputs_are_private_and_strict(self):
        variants = (
            INPUT + 'schema=3\n', INPUT + 'private_unknown=secret\n',
            INPUT.replace('schema=3', 'schema=2'), INPUT.replace('schema=3\n', ''),
            INPUT.replace(SOURCE_HASH, '0' * 64),
            INPUT.replace('http://proxy.example.org:3128', 'http://user:private@proxy.example.org:3128'),
            INPUT.replace('http://proxy.example.org:3128', 'http://proxy.example.org:65536'),
            INPUT.replace('localhost,127.0.0.1,.example.org', '$(private)'),
        )
        for text in variants:
            with self.subTest(text=text[:30]):
                self.expect(self.execute(text), 1)
        for mode in (0o644, 0o660):
            descriptor = memory_fd('public-input', INPUT.encode(), mode=mode)
            try:
                self.expect(self.execute(input_fd=descriptor), 1)
            finally:
                os.close(descriptor)

    def test_persistent_regular_fd_and_high_descriptor(self):
        path = self.workspace / 'private.input'
        path.write_text(INPUT)
        path.chmod(0o600)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOATIME)
        try:
            with self.subTest(descriptor='original'):
                before = path.stat()
                self.expect(self.execute(input_fd=descriptor), 0)
                after = path.stat()
                self.assertEqual((before.st_ino, before.st_atime_ns, before.st_mtime_ns,
                                  before.st_ctime_ns),
                                 (after.st_ino, after.st_atime_ns, after.st_mtime_ns,
                                  after.st_ctime_ns))
            high = fcntl.fcntl(descriptor, fcntl.F_DUPFD, 10)
            try:
                self.expect(self.execute(input_fd=high), 0)
            finally:
                os.close(high)
        finally:
            os.close(descriptor)
        writable = os.open(path, os.O_RDWR | os.O_NOATIME)
        try:
            result = self.execute(input_fd=writable)
            self.expect(result, 1)
            self.assertIn('reason=not-read-only', result.stderr)
        finally:
            os.close(writable)
        reader, writer = os.pipe()
        try:
            result = self.execute(input_fd=reader)
            self.expect(result, 1)
            self.assertIn('reason=unsupported-fd', result.stderr)
        finally:
            os.close(reader)
            os.close(writer)

    def test_sealed_source_fd_binds_executed_source(self):
        for sealed in (True, False):
            with self.subTest(sealed=sealed):
                source = memory_fd('proxy-source', SOURCE_BYTES, sealed=sealed, mode=0o700)
                try:
                    result = self.execute(source='/proc/self/fd/' + str(source), pass_fds=(source,))
                    self.expect(result, 0 if sealed else 1)
                finally:
                    os.close(source)
        copy = self.workspace / 'modified-source.bash'
        copy.write_bytes(SOURCE_BYTES + b'\n# Source checksum mismatch fixture.\n')
        copy.chmod(0o700)
        self.expect(self.execute(source=copy), 1)

    def test_relative_os_release_link_and_other_platforms(self):
        path = self.root / 'etc/os-release'
        target = self.root / 'usr/lib/os-release'
        target.parent.mkdir(parents=True)
        target.parent.chmod(0o755)
        target.parent.parent.chmod(0o755)
        shutil.copy2(path, target)
        path.unlink()
        path.symlink_to('../usr/lib/os-release')
        self.expect(self.execute(), 0)
        target.write_text('ID=debian\nVERSION_ID=13\n')
        self.expect(self.execute(), 1)
        target.write_text('ID=rocky\nVERSION_ID=8.10\n')
        path.unlink()
        path.symlink_to('../../../../usr/lib/os-release')
        result = self.execute()
        self.expect(result, 1)
        self.assertIn('reason=unsafe-path', result.stderr)

    def test_privileged_startup_ignores_inherited_code(self):
        marker = self.workspace / 'startup-executed'
        startup = self.workspace / 'startup.bash'
        startup.write_text('touch ' + shlex.quote(str(marker)) + '\n')
        python_path = self.workspace / 'python-path'
        python_path.mkdir()
        (python_path / 'hashlib.py').write_text('raise RuntimeError("inherited Python code")\n')
        environment = dict(os.environ, BASH_ENV=str(startup), ENV=str(startup),
                           PYTHONPATH=str(python_path), TMPDIR='/nonexistent-proxy-checker-temp')
        self.expect(self.execute(env=environment), 0)
        self.assertFalse(marker.exists())

    def test_read_only_filesystem_permissions(self):
        directories = [self.root] + [path for path in self.root.rglob('*') if path.is_dir()]
        for directory in directories:
            directory.chmod(0o555)
        for path in self.root.rglob('*'):
            if path.is_file():
                path.chmod(0o444)
        try:
            self.expect(self.execute(), 0)
        finally:
            for directory in directories:
                directory.chmod(0o755)

    def test_bash_does_not_create_heredoc_temporary_files(self):
        libc = ctypes.CDLL(None, use_errno=True)
        watch = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        self.assertGreaterEqual(watch, 0)
        try:
            self.assertGreaterEqual(libc.inotify_add_watch(watch, b'/tmp', 0x100 | 0x80), 0)
            self.expect(self.execute(), 0)
            try:
                events = os.read(watch, 65536)
            except BlockingIOError:
                events = b''
            offset = 0
            while offset < len(events):
                _, mask, _, size = struct.unpack_from('iIII', events, offset)
                self.assertFalse(mask & 0x4000, 'filesystem observer overflowed')
                name = events[offset + 16:offset + 16 + size].rstrip(b'\0')
                self.assertFalse(name.startswith(b'sh-thd.'), 'Bash created a temporary heredoc')
                offset += 16 + size
        finally:
            os.close(watch)

    def test_check_cli_refuses_invalid_descriptors_and_production_test_root(self):
        self.expect(self.execute(extra=('--input-fd', '10')), 1)
        result = self.execute(extra=('--test-root', '/'))
        self.expect(result, 1)
        self.assertIn('reason=unsafe-test-root', result.stderr)
        descriptor = memory_fd('production-input', INPUT.encode())
        try:
            for value in ('0', '2', '64', '-3', 'private-value'):
                result = subprocess.run(['/bin/bash', '-p', str(self.source),
                                         '--test-root', str(self.root), 'check', '--input-fd', value],
                                        capture_output=True, text=True, timeout=20)
                self.expect(result, 1)
                self.assertIn('reason=invalid-fd', result.stderr)
            if os.geteuid() != 0:
                result = subprocess.run(['/bin/bash', '-p', str(self.source), 'check',
                                         '--input-fd', str(descriptor)], pass_fds=(descriptor,),
                                        capture_output=True, text=True, timeout=20)
                self.expect(result, 1)
                self.assertIn('reason=privileged-root-required', result.stderr)
        finally:
            os.close(descriptor)

    def reconcile(self, proxy_url):
        for identity in PATHS:
            if identity == 'dnf':
                self.file(identity).write_text('[main]\ngpgcheck=1\n')
            else:
                self.file(identity).unlink()
        runtime = self.root / 'run/cloud-provision'
        runtime.mkdir(parents=True, mode=0o700)
        runtime.chmod(0o700)
        runtime.parent.chmod(0o755)
        staged = runtime / 'proxy_contract.bash'
        staged.write_bytes(SOURCE_BYTES)
        staged.chmod(0o700)
        input_path = runtime / 'proxy-contract.input'
        input_path.write_text('schema=2\nscope=general-server\n'
                              'proxy_url=' + proxy_url + '\nscript_sha256=' + SOURCE_HASH + '\n')
        input_path.chmod(0o600)
        applied = subprocess.run(['/bin/bash', '-p', str(staged), '--test-root',
                                  str(self.root), 'reconcile'], capture_output=True, text=True, timeout=30)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        return INPUT.replace('http://proxy.example.org:3128', proxy_url).replace(
            'localhost,127.0.0.1,.example.org', 'localhost,127.0.0.1,192.168.0.0/16').replace(
                'localhost|127.0.0.1|*.example.org', 'localhost|127.0.0.1|192.168.*')

    def test_actual_reconcile_artifacts_and_runtime_loss(self):
        desired = self.reconcile('http://proxy.example.org:3128')
        self.expect(self.execute(desired), 0)
        shutil.rmtree(self.root / 'run')
        self.expect(self.execute(desired), 0)

    def test_mixed_case_proxy_host_matches_reconcile_output(self):
        desired = self.reconcile('http://Proxy.Example.org:3128')
        self.expect(self.execute(desired), 0)

    def test_proxy_port_range_is_diagnosed(self):
        for port in ('0', '65536', '99999999999'):
            with self.subTest(port=port):
                result = self.execute(INPUT.replace(':3128', ':' + port))
                self.expect(result, 1)
                self.assertIn('reason=invalid-port', result.stderr)

    def test_input_lines_are_lf_separated(self):
        for separator in ('\r\n', '\r', '\x0b', '\x0c', '\x1c', '\x7f'):
            with self.subTest(separator=separator):
                result = self.execute(INPUT.replace('\n', separator))
                self.expect(result, 1)
                self.assertIn('reason=invalid-field', result.stderr)

    def test_leading_zero_port_is_unsupported(self):
        for port in ('03128', '00', '0080'):
            with self.subTest(port=port):
                result = self.execute(INPUT.replace(':3128', ':' + port))
                self.expect(result, 1)
                self.assertIn('reason=unsupported-url', result.stderr)

    def test_group_write_only_is_refused(self):
        for identity in PATHS:
            with self.subTest(identity=identity):
                path = self.file(identity)
                path.chmod(0o664)
                result = self.execute()
                self.expect(result, 1)
                self.assertIn('reason=unsafe-mode', result.stderr)
                path.chmod(0o644)

    def test_root_directory_metadata_is_refused(self):
        self.root.chmod(0o770)
        result = self.execute()
        self.expect(result, 1)
        self.assertIn('reason=unsafe-mode', result.stderr)

    def test_other_rocky_release_is_refused(self):
        path = self.root / 'etc/os-release'
        path.write_text('ID="rocky"\nVERSION_ID="9.4"\n')
        result = self.execute()
        self.expect(result, 1)
        self.assertIn('reason=unsupported-platform', result.stderr)

    def test_default_port_follows_the_proxy_scheme(self):
        for url, port in (('http://proxy.example.org', '80'), ('https://proxy.example.org', '443')):
            with self.subTest(url=url):
                for identity in PATHS:
                    text = (FIXTURE / PATHS[identity]).read_text().replace(
                        'http://proxy.example.org:3128', url)
                    self.file(identity).write_text(
                        text.replace('<port>3128</port>', '<port>' + port + '</port>'))
                self.expect(self.execute(INPUT.replace('http://proxy.example.org:3128', url)), 0)

    def test_maven_bypass_text_difference_needs_change(self):
        path = self.file('maven')
        path.write_text(path.read_text().replace(
            '<nonProxyHosts>localhost|127.0.0.1|*.example.org</nonProxyHosts>',
            '<nonProxyHosts>localhost</nonProxyHosts>'))
        result = self.execute()
        self.expect(result, 2)
        self.assertIn('identity=maven key=nonProxyHosts', result.stderr)

    @unittest.skipUnless(shutil.which('ansible-playbook'), 'ansible-playbook is unavailable')
    def test_actual_ansible_raw_private_fd(self):
        private = self.workspace / 'private.input'
        private.write_text(INPUT)
        private.chmod(0o600)
        command = 'exec 3<{}; /bin/bash -p {} --test-root {} check --input-fd 3'.format(
            shlex.quote(str(private)), shlex.quote(str(self.source)), shlex.quote(str(self.root)))
        import json
        play = [{'hosts': 'all', 'gather_facts': False, 'become': False,
                 'tasks': [{'name': 'Run shipped proxy checker through raw FD transport',
                            'ansible.builtin.raw': command, 'check_mode': False,
                            'register': 'checked', 'changed_when': False, 'no_log': True},
                           {'name': 'Require ready result', 'ansible.builtin.assert': {'that': [
                               'checked.rc == 0', 'checked.stdout | trim == ' + repr(READY.strip())]}}]}]
        play_path = self.workspace / 'probe.json'
        play_path.write_text(json.dumps(play))
        environment = dict(os.environ, ANSIBLE_LOCAL_TEMP=str(self.workspace / 'ansible-temp'))
        before = snapshot(self.root)
        result = subprocess.run(['ansible-playbook', '-i', 'localhost,', '-c', 'local',
                                 '--check', str(play_path)], env=environment,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, snapshot(self.root))
        self.assertNotIn('proxy.example.org', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
