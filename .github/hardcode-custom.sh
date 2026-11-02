#!/bin/bash
# Applies the custom-client changes to a fresh checkout, then verifies each one landed.
# Shared by the Windows and Linux build jobs so the two cannot drift apart.
set -e

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python

$PY - <<'PYEOF'
import pathlib, sys

id_server = "dj.wizrole.cn:8443"
relay_server = "dj.wizrole.cn:8444"
pub_key = "NkNCTItxvr6MysSjBs0tPRoqkzsWOrhOUkacYWCQl1o="


def patch(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    n = s.count(old)
    if n != 1:
        sys.exit(f"FAILED: expected exactly 1 match in {path}, found {n}: {old!r}")
    p.write_text(s.replace(old, new), encoding="utf-8")
    print(f"patched {path}")


cfg = "libs/hbb_common/src/config.rs"
patch(cfg,
      'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];',
      f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{id_server}"];')
patch(cfg,
      'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";',
      f'pub const RS_PUB_KEY: &str = "{pub_key}";')

patch("src/rendezvous_mediator.rs",
      'let mut relay_server = Config::get_option("relay-server");',
      'let mut relay_server = Config::get_option("relay-server");\n'
      '        if relay_server.is_empty() {\n'
      f'            relay_server = "{relay_server}".to_owned();\n'
      '        }')

# lejianwen/rustdesk-api#92: hbbs never answers the key exchange, so every connection
# waits READ_TIMEOUT (18s) and secure_tcp_required fails outright. Short-circuit both
# to keep the API account login usable.
patch("src/common.rs",
      'async fn secure_tcp_impl(conn: &mut Stream, key: &str, log_on_success: bool) -> ResultType<()> {',
      'async fn secure_tcp_impl(conn: &mut Stream, key: &str, log_on_success: bool) -> ResultType<()> {\n'
      '    return Ok(());')
patch("src/common.rs",
      'pub async fn secure_tcp_required(conn: &mut Stream, key: &str) -> ResultType<()> {',
      'pub async fn secure_tcp_required(conn: &mut Stream, key: &str) -> ResultType<()> {\n'
      '    return Ok(());')

# Branding: the About page title in the Chinese UI.
patch("src/lang/cn.rs",
      '("About RustDesk", "关于 RustDesk"),',
      '("About RustDesk", "关于 RustDesk 维思陆定制版"),')
PYEOF

grep -F 'pub const RENDEZVOUS_SERVERS: &[&str] = &["dj.wizrole.cn:8443"];' libs/hbb_common/src/config.rs
grep -F 'pub const RS_PUB_KEY: &str = "NkNCTItxvr6MysSjBs0tPRoqkzsWOrhOUkacYWCQl1o=";' libs/hbb_common/src/config.rs
grep -F 'relay_server = "dj.wizrole.cn:8444".to_owned();' src/rendezvous_mediator.rs
grep -F 'async fn secure_tcp_impl(conn: &mut Stream, key: &str, log_on_success: bool) -> ResultType<()> {' -A1 src/common.rs | grep -F 'return Ok(());'
grep -F 'pub async fn secure_tcp_required(conn: &mut Stream, key: &str) -> ResultType<()> {' -A1 src/common.rs | grep -F 'return Ok(());'
grep -F '("About RustDesk", "关于 RustDesk 维思陆定制版"),' src/lang/cn.rs
echo "custom client patches verified"
