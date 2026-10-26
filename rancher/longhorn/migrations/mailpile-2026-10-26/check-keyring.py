# Compatible with the application's Python 2 and GnuPG 1.4.
from __future__ import print_function
import os
import shutil
import subprocess
import tempfile

scratch = tempfile.mkdtemp(prefix='mailpile-keyring-check-')
try:
    home = os.path.join(scratch, 'gnupg')
    shutil.copytree('/target/keys', home, symlinks=True)
    os.chmod(home, 0o700)
    counts = {}
    for option, record in [('--list-keys', b'pub:'), ('--list-secret-keys', b'sec:')]:
        process = subprocess.Popen(['gpg', '--no-options', '--homedir', home,
                                    '--batch', '--with-colons', option],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = process.communicate()
        if process.returncode:
            raise RuntimeError('Copied GnuPG keyring could not be parsed; private diagnostics withheld')
        counts[option] = sum(line.startswith(record) for line in out.splitlines())
    print('GnuPG keyring parsed in disposable clone: public=%d secret=%d' %
          (counts['--list-keys'], counts['--list-secret-keys']))
    print('Original/target key files unchanged; no keys or messages decrypted/sent')
finally:
    shutil.rmtree(scratch)
