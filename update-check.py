import re
import subprocess
import sys
import urllib.request

# Track our own proton-bridge fork instead of upstream Proton releases.
# The fork publishes no GitHub releases/tags, so the canonical version is
# the Makefile's BRIDGE_APP_VERSION on the branch the build image clones
# (keep BRANCH in sync with BRIDGE_REF in build/Dockerfile).
FORK = "bolausson/proton-bridge"
BRANCH = "master"
MAKEFILE_URL = f"https://raw.githubusercontent.com/{FORK}/{BRANCH}/Makefile"


def git(*args):
    return subprocess.run(["git", *args]).returncode


with urllib.request.urlopen(MAKEFILE_URL, timeout=30) as resp:
    makefile = resp.read().decode("utf-8")

match = re.search(r"^BRIDGE_APP_VERSION\s*\?=\s*(.+)$", makefile, re.MULTILINE)
if not match:
    print(f"Could not find BRIDGE_APP_VERSION in {MAKEFILE_URL}")
    sys.exit(1)

# e.g. "3.24.2+git" -> base "3.24.2"; keep this repo's leading-v convention.
base = match.group(1).strip().split("+")[0].lstrip("v")
version = f"v{base}"

# The fork ships no .deb. The legacy `deb` image still tracks the official
# Proton release of the same upstream base version (deterministic URL,
# matching the historical "-1" Debian revision).
deb = (
    f"https://github.com/ProtonMail/proton-bridge/releases/download/"
    f"v{base}/protonmail-bridge_{base}-1_amd64.deb"
)

print(f"Fork {FORK}@{BRANCH} is at version: {version}")

with open("VERSION", "w") as f:
    f.write(version)

with open("deb/PACKAGE", "w") as f:
    f.write(deb)

git("config", "--local", "user.name", "GitHub Actions")
git("config", "--local", "user.email", "actions@github.com")
git("add", "-A")

if git("diff", "--cached", "--quiet") == 0:  # 0 == nothing staged
    print("Version didn't change")
    sys.exit(0)

git("commit", "-m", f"Bump version to {version}")

is_pull_request = len(sys.argv) > 1 and sys.argv[1] == "true"
if is_pull_request:
    print("This is a pull request, skipping push step.")
    sys.exit(0)

if git("push") != 0:
    print("Git push failed!")
    sys.exit(1)
