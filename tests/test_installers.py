"""离线检查安装逻辑；只执行提取的函数，所有网络/服务命令均模拟。"""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("install-docker.sh", "install-nginx-official.sh", "install-zsh.sh", "InstallNET.sh")
BASH = str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe") if os.name == "nt" else shutil.which("bash")


def quote(path):
    value = str(path).replace("\\", "/")
    if os.name == "nt" and len(value) > 2 and value[1] == ":":
        value = "/" + value[0].lower() + value[2:]
    return shlex.quote(value)


def functions(script, *names):
    text = (ROOT / script).read_text(encoding="utf-8")
    result = []
    for name in names:
        match = re.search(r"^(?:function )?" + name + r"\(\)\s*\{.*?^\}", text, re.M | re.S)
        if not match:
            raise AssertionError(f"Missing function {script}:{name}")
        result.append(match.group())
    return "\n".join(result) + "\n"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "tests")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def bash(self, code, success=True):
        env = dict(os.environ)
        for name in ("INSTALL_REGION", "FORCE_GH_PROXY", "DOCKER_REGISTRY_MIRRORS", "DOCKER_REPO_URL", "DOCKER_GPG_URL", "DOCKER_EXPECTED_FINGERPRINT", "NGINX_KEY_URL", "NGINX_REPO_URL", "NGINX_EXPECTED_FINGERPRINT", "GH_PROXY_URL"):
            env.pop(name, None)
        env["HOME"] = str(self.work).replace("\\", "/")
        env["PYTHONUTF8"] = "1"
        result = subprocess.run([BASH, "-s"], input="set -eo pipefail\n" + code, cwd=ROOT, env=env, capture_output=True, encoding="utf-8")
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_syntax(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = subprocess.run([BASH, "-n", str(ROOT / script)], capture_output=True, encoding="utf-8")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_country_detection_for_every_script(self):
        for script in SCRIPTS:
            for country, expected in (("CN", "cn"), ("US", "global"), ("HK", "global")):
                with self.subTest(script=script, country=country):
                    self.bash(functions(script, "region_get", "detect_region") + f"curl() {{ printf '{country}\\r\\n'; }}\ndetect_region\n[[ $INSTALL_REGION = {expected} ]]\n")

    def test_country_fallback_failure_and_override(self):
        for script in SCRIPTS:
            code = functions(script, "region_get", "detect_region")
            with self.subTest(script=script):
                self.bash(code + "curl() { case ${!#} in *country*) echo '<html>limited</html>' ;; *) printf 'ip=192.0.2.1\\nloc=CN\\n' ;; esac; }\ndetect_region\n[[ $INSTALL_REGION = cn ]]\n")
                self.bash(code + "curl() { return 28; }\ndetect_region\n[[ $INSTALL_REGION = global ]]\n")
                self.bash(code + "curl() { echo 'unexpected network call' >&2; exit 99; }\nINSTALL_REGION=cn\ndetect_region\n[[ $INSTALL_REGION = cn ]]\n")
                self.bash(code + "INSTALL_REGION=invalid\ndetect_region\n", success=False)

    def docker_setup(self):
        return f"TMP_DIR={quote(self.work)}\nOS_ID=debian\nOS_CODENAME=bookworm\nDOCKER_GPG_KEY=/keys/docker.gpg\nDOCKER_APT_LIST=/sources/docker.list\nSOURCE_TYPE=auto\nINSTALL_REGION=cn\n" + r"""
dpkg() { echo amd64; }
gpg() {
  if [[ " $* " = *' --show-keys '* ]]; then
    printf '%s\n' 'pub:::::::::' 'fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:'
  else
    while [ "$1" != -o ]; do shift; done
    printf key > "$2"
  fi
}
"""

    def test_docker_auto_fallback_and_mirror_key(self):
        self.bash(functions(SCRIPTS[0], "prepare_repository") + self.docker_setup() + r"""
fetch() {
  echo "$1" >> "$TMP_DIR/requests"
  [[ "$1" != *tuna* ]] || return 28
  printf valid > "$2"
}
prepare_repository
grep -q 'mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg' "$TMP_DIR/requests"
grep -q 'mirrors.ustc.edu.cn' "$TMP_DIR/docker.list"
""")

    def test_docker_explicit_official_does_not_switch(self):
        self.bash(functions(SCRIPTS[0], "prepare_repository") + self.docker_setup() + r"""
SOURCE_TYPE=official
fetch() { echo "$1" >> "$TMP_DIR/requests"; return 28; }
if prepare_repository; then exit 1; fi
[[ $(wc -l < "$TMP_DIR/requests") = 1 ]]
grep -q download.docker.com "$TMP_DIR/requests"
""")

    def test_docker_bad_key_is_rejected(self):
        self.bash(functions(SCRIPTS[0], "prepare_repository") + self.docker_setup() + r"""
fetch() { printf data > "$2"; }
gpg() { echo 'fpr:::::::::BADKEY:'; }
if prepare_repository; then exit 1; fi
[[ ! -f "$TMP_DIR/docker.list" ]]
""")

    def test_docker_rejects_extra_untrusted_primary_key(self):
        self.bash(functions(SCRIPTS[0], "prepare_repository") + self.docker_setup() + r"""
fetch() { printf data > "$2"; }
gpg() { printf '%s\n' 'pub:::::::::' 'fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:' 'pub:::::::::' 'fpr:::::::::UNTRUSTED:'; }
if prepare_repository; then exit 1; fi
[[ ! -f "$TMP_DIR/docker.list" ]]
""")

    def test_legacy_unknown_source_still_means_official(self):
        source = (ROOT / SCRIPTS[0]).read_text(encoding="utf-8")
        preflight = source[source.index('if [ "$(id -u)" -ne 0 ]; then'):source.index('if [ ! -f /etc/os-release ]; then')]
        self.bash("id() { echo 0; }\nSOURCE_TYPE=legacy-value\n" + preflight + "[[ $SOURCE_TYPE = official ]]\n")

    def merge_setup(self):
        return functions(SCRIPTS[0], "merge_daemon_config") + f"python3() {{ {quote(sys.executable)} \"$@\"; }}\nTMP_DIR={quote(self.work)}\nDOCKER_DAEMON_JSON={quote(self.work / 'existing.json')}\n"

    def test_docker_preserves_config_and_applies_explicit_mirrors(self):
        existing = {"registry-mirrors": ["https://old.example"], "proxies": {"https-proxy": "http://127.0.0.1:7890"}, "ipv6": False, "log-driver": "local", "data-root": "/data/docker"}
        (self.work / "existing.json").write_text(json.dumps(existing))
        self.bash(self.merge_setup() + "merge_daemon_config\n")
        merged = json.loads((self.work / "daemon.json").read_text())
        for key, value in existing.items():
            self.assertEqual(merged[key], value)
        self.assertNotIn("log-opts", merged)
        self.assertNotIn("fixed-cidr-v6", merged)
        self.bash(self.merge_setup() + "DOCKER_REGISTRY_MIRRORS='https://new.example/,https://new.example https://other.example'\nmerge_daemon_config\n")
        self.assertEqual(json.loads((self.work / "daemon.json").read_text())["registry-mirrors"], ["https://new.example", "https://other.example"])

    def test_docker_invalid_json_and_mirror_do_not_overwrite(self):
        path = self.work / "existing.json"
        path.write_text("{broken")
        self.bash(self.merge_setup() + "merge_daemon_config\n", success=False)
        self.assertEqual(path.read_text(), "{broken")
        path.write_text("{}")
        self.bash(self.merge_setup() + "DOCKER_REGISTRY_MIRRORS=http://insecure.example\nmerge_daemon_config\n", success=False)
        self.assertEqual(path.read_text(), "{}")

    def test_repository_failure_restores_previous_files(self):
        cases = ((SCRIPTS[0], "install_docker_packages", ("docker.gpg", "docker.list"), ("DOCKER_GPG_KEY", "DOCKER_APT_LIST")),
                 (SCRIPTS[1], "install_nginx_packages", ("nginx.gpg", "nginx.list", "99nginx"), ("KEYRING", "SOURCE_LIST", "PREFERENCES_FILE")))
        for script, function, staged, variables in cases:
            with self.subTest(script=script):
                setup = f"TMP_DIR={quote(self.work)}\n"
                for name, variable in zip(staged, variables):
                    (self.work / name).write_text("new")
                    target = self.work / (name + ".existing")
                    target.write_text("previous")
                    setup += f"{variable}={quote(target)}\n"
                self.bash(functions(script, function) + setup + "apt-get() { return 1; }\nif " + function + "; then exit 1; fi\n")
                for name in staged:
                    self.assertEqual((self.work / (name + ".existing")).read_text(), "previous")

    def test_partial_install_failure_removes_new_source_files(self):
        code = functions(SCRIPTS[0], "install_docker_packages")
        for name in ("docker.gpg", "docker.list"):
            (self.work / name).write_text("new")
        self.bash(code + f"TMP_DIR={quote(self.work)}\nDOCKER_GPG_KEY={quote(self.work/'new-key')}\nDOCKER_APT_LIST={quote(self.work/'new-list')}\n" + r"""
apt-get() { [[ " $* " != *' install '* ]]; }
if install_docker_packages; then exit 1; fi
[[ ! -e $DOCKER_GPG_KEY && ! -e $DOCKER_APT_LIST ]]
""")

    def test_wget_only_country_detection(self):
        self.bash(functions(SCRIPTS[3], "region_get", "detect_region") + r"""
command() {
  if [[ "$1" = -v && "$2" = curl ]]; then return 1; fi
  builtin command "$@"
}
wget() { echo CN; }
detect_region
[[ $INSTALL_REGION = cn ]]
""")

    def test_docker_restart_failure_restores_previous_config(self):
        path = self.work / "existing.json"
        path.write_text('{"registry-mirrors":["https://keep.example"]}')
        previous = path.read_text()
        self.bash(self.merge_setup() + functions(SCRIPTS[0], "configure_daemon") + r"""
mkdir() { if [[ "$*" != '-p /etc/docker' ]]; then command mkdir "$@"; fi; }
dockerd() { return 0; }
restarts=0
systemctl() { restarts=$((restarts+1)); [[ $restarts -gt 1 ]]; }
if configure_daemon; then exit 1; fi
[[ $restarts = 2 ]]
""")
        self.assertEqual(path.read_text(), previous)

    def zsh_setup(self):
        return functions(SCRIPTS[2], "git_clone_github") + f"GH_PROXY=https://proxy.example/\nTARGET={quote(self.work / 'plugins' / 'sample')}\nLOG={quote(self.work / 'git.log')}\n" + r"""
# Disable the optional external timeout so tests exercise the command directly.
command_exists() { return 1; }
git() {
  local url="${@: -2:1}" target="${@: -1}"
  echo "$url" >> "$LOG"
  mkdir -p "$target"
  [[ "$url" != https://proxy.example/* ]] || { echo partial > "$target/partial"; return 1; }
  echo ready > "$target/installed"
}
"""

    def test_zsh_clone_fallback_cleans_partial_target(self):
        self.bash(self.zsh_setup() + "USE_GH_PROXY=1\ngit_clone_github https://github.com/example/repo.git \"$TARGET\"\n[[ -f $TARGET/installed && ! -f $TARGET/partial ]]\n[[ $(wc -l < \"$LOG\") = 2 ]]\n")
        self.assertEqual(list((self.work / "plugins").glob("*.clone.*")), [])

    def test_zsh_forced_proxy_has_no_direct_fallback(self):
        self.bash(self.zsh_setup() + "USE_GH_PROXY=1\nFORCE_GH_PROXY=1\nif git_clone_github https://github.com/example/repo.git \"$TARGET\"; then exit 1; fi\n[[ ! -d $TARGET ]]\n[[ $(wc -l < \"$LOG\") = 1 ]]\n")

    def test_zsh_route_selection(self):
        code = functions(SCRIPTS[2], "detect_github_proxy") + "GH_PROXY=https://proxy.example/\ndetect_region() { INSTALL_REGION=cn; }\n"
        self.bash(code + "detect_github_proxy\n[[ $USE_GH_PROXY = 1 ]]\nFORCE_GH_PROXY=0\ndetect_github_proxy\n[[ $USE_GH_PROXY = 0 ]]\n")
        self.bash(code + "FORCE_GH_PROXY=bad\ndetect_github_proxy\n", success=False)

    def test_installnet_mirror_order_and_architecture(self):
        code = functions(SCRIPTS[3], "mirror_candidates")
        self.bash(code + "INSTALL_REGION=cn\n[[ $(mirror_candidates debian amd64 | head -1) = *tuna* ]]\nINSTALL_REGION=global\n[[ $(mirror_candidates debian amd64 | head -1) = https://deb.debian.org/debian ]]\n[[ $(mirror_candidates ubuntu arm64 | head -1) = https://ports.ubuntu.com ]]\n[[ $(mirror_candidates debian amd64 https://custom.example/debian | head -1) = https://custom.example/debian ]]\n")

    def test_installnet_pair_fallback_keeps_files_from_one_mirror(self):
        code = functions(SCRIPTS[3], "installer_prefix", "download_installer_pair")
        self.bash(code + f"OUTPUT={quote(self.work)}\n" + r"""
linux_relese=debian
VER=amd64
DIST=bookworm
tmpMirror=''
mirror_candidates() { printf '%s\n' https://first.example https://second.example; }
wget_download() {
  if [[ "$2" = https://first.example/*/linux ]]; then return 1; fi
  echo "$2" > "$1"
}
download_installer_pair "$OUTPUT" https://first.example
[[ $LinuxMirror = https://second.example ]]
grep -q '^https://second.example/' "$OUTPUT/initrd.img"
grep -q '^https://second.example/' "$OUTPUT/vmlinuz"
[[ ! -e $OUTPUT/initrd.candidate && ! -e $OUTPUT/kernel.candidate ]]
""")

    def test_installnet_failed_download_preserves_existing_file(self):
        self.bash(functions(SCRIPTS[3], "wget_download") + f"TARGET={quote(self.work/'old.img')}\n" + r"""
echo original > "$TARGET"
wget() { while [ "$1" != -qO ]; do shift; done; echo partial > "$2"; return 1; }
if wget_download "$TARGET" https://fail.example/image; then exit 1; fi
[[ $(cat "$TARGET") = original ]]
[[ ! -e $TARGET.part.$$ ]]
""")

    def test_firmware_download_fallback(self):
        self.bash(functions(SCRIPTS[3], "download_debian_firmware") + f"TARGET={quote(self.work/'firmware')}\n" + r"""
INSTALL_REGION=cn
wget_download() { [[ "$2" != *tuna* ]] || return 1; echo "$2" > "$1"; }
download_debian_firmware bookworm "$TARGET"
grep -q mirrors.ustc.edu.cn "$TARGET"
""")

    def test_nginx_keeps_official_packages_and_requires_custom_key_fingerprint(self):
        source = (ROOT / SCRIPTS[1]).read_text(encoding="utf-8")
        # Run the real preflight only; no package manager or filesystem writes.
        preflight = source.split('TMP_DIR="$(mktemp -d)"')[0]
        preflight = preflight.replace('. /etc/os-release', 'ID=debian').replace('if [ ! -f /etc/os-release ]; then', 'if false; then')
        for branch in ("stable", "mainline"):
            with self.subTest(branch=branch):
                self.bash(f"set -- {branch}\nid() {{ echo 0; }}\n" + preflight + "[[ $REPO_URL = https://nginx.org/packages/*debian ]]\n")
        self.bash("id() { echo 0; }\nNGINX_KEY_URL=https://custom.example/key\n" + preflight, success=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
