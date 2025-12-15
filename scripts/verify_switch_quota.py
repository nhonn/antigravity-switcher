#!/usr/bin/env python3

import json
import os
import re
import sqlite3
import subprocess
import time
from typing import Dict, List, Optional, Tuple

DB_PATH = os.path.expanduser(
    "~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
)
ACCOUNTS_PATH = os.path.expanduser("~/.antigravity-agent/antigravity_accounts.json")

# Keep in sync with AppConfiguration.keysToBackup
KEYS_TO_SWAP = [
    "antigravityAuthStatus",
    "jetskiStateSync.agentManagerInitState",
    "antigravityUserSettings.allUserSettings",
    "antigravity_allowed_command_model_configs",
    "antigravityOnboarding",
    "antigravity.profileUrl",
    "antigravityChangelog/lastVersion",
    "antigravityAnalytics.lastUploadTime",
    "antigravity.agentViewContainerId.state.hidden",
]


def db_get_values(keys: List[str]) -> Dict[str, str]:
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    out: Dict[str, str] = {}
    for k in keys:
        cur.execute("select value from ItemTable where key=?", (k,))
        row = cur.fetchone()
        if row and row[0] is not None:
            out[k] = row[0]
    con.close()
    return out


def db_set_values(d: Dict[str, str]) -> None:
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    for k, v in d.items():
        cur.execute(
            "insert or replace into ItemTable(key,value) values (?,?)",
            (k, v),
        )
    con.commit()
    con.close()


def extract_email_from_authstatus(s: str) -> Optional[str]:
    try:
        obj = json.loads(s)
        return obj.get("email")
    except Exception:
        return None


def quit_antigravity() -> None:
    subprocess.run(
        ["/usr/bin/osascript", "-e", 'tell application "Antigravity" to quit'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def start_antigravity() -> None:
    subprocess.run(
        ["/usr/bin/open", "-a", "Antigravity"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def kill_language_servers() -> None:
    # Best-effort; keep it narrowly scoped.
    subprocess.run(
        ["/usr/bin/pkill", "-f", "/extensions/antigravity/bin/language_server"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["/usr/bin/pkill", "-f", "language_server_macos"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def wait_for_language_server(timeout: float = 25.0) -> Optional[str]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        ps = subprocess.check_output(["/bin/ps", "-ax", "-o", "pid=,command="], text=True)
        for line in ps.splitlines():
            if "/extensions/antigravity/bin/language_server" in line and "--csrf_token" in line:
                return line.strip()
        time.sleep(0.3)
    return None


def parse_token_and_ports(ps_line: str) -> Tuple[int, str, List[int]]:
    m = re.match(r"\s*(\d+)\s+(.*)$", ps_line)
    if not m:
        raise RuntimeError(f"Unexpected ps line: {ps_line}")

    pid = int(m.group(1))
    cmd = m.group(2)

    m2 = re.search(r"--csrf_token(?:=|\s+)([^\s]+)", cmd)
    if not m2:
        raise RuntimeError("Could not parse --csrf_token")
    token = m2.group(1)

    try:
        lsof = subprocess.check_output(
            ["/usr/sbin/lsof", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN", "-n", "-P"],
            text=True,
        )
    except subprocess.CalledProcessError:
        # lsof exits 1 when no matches (e.g., server not listening yet).
        lsof = ""
    ports = sorted({int(x) for x in re.findall(r"TCP\s+[^:]+:(\d+)\s+\(LISTEN\)", lsof)})
    return pid, token, ports


def probe_port(token: str, port: int, scheme: str) -> bool:
    url = f"{scheme}://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUnleashData"
    args = ["/usr/bin/curl", "-s", "-o", "/dev/null", "-w", "%{http_code}"]
    if scheme == "https":
        args.append("-k")
    args += [
        "-X",
        "POST",
        url,
        "-H",
        "Content-Type: application/json",
        "-H",
        "Connect-Protocol-Version: 1",
        "-H",
        f"X-Codeium-Csrf-Token: {token}",
        "--data",
        '{"wrapper_data":{}}',
    ]
    r = subprocess.run(args, capture_output=True, text=True)
    return r.stdout.strip() == "200"


def find_working_endpoint(token: str, ports: List[int]) -> Optional[Tuple[str, int]]:
    for p in ports:
        if probe_port(token, p, "https"):
            return "https", p
        if probe_port(token, p, "http"):
            return "http", p
    return None


def get_user_status_email(scheme: str, port: int, token: str) -> Optional[str]:
    url = f"{scheme}://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUserStatus"
    args = ["/usr/bin/curl", "-s"]
    if scheme == "https":
        args.append("-k")
    args += [
        "-X",
        "POST",
        url,
        "-H",
        "Content-Type: application/json",
        "-H",
        "Connect-Protocol-Version: 1",
        "-H",
        f"X-Codeium-Csrf-Token: {token}",
        "--data",
        '{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}',
    ]
    raw = subprocess.check_output(args, text=True)
    obj = json.loads(raw)
    return (obj.get("userStatus") or {}).get("email")


def main() -> int:
    if not os.path.exists(DB_PATH):
        print("DB not found:", DB_PATH)
        return 2
    if not os.path.exists(ACCOUNTS_PATH):
        print("Accounts file not found:", ACCOUNTS_PATH)
        return 2

    original = db_get_values(KEYS_TO_SWAP)
    original_email = extract_email_from_authstatus(original.get("antigravityAuthStatus", ""))
    print("original_email:", original_email)

    with open(ACCOUNTS_PATH, "r") as f:
        accounts = list(json.load(f).values())

    candidate = None
    for a in accounts:
        email = a.get("email")
        backup_file = a.get("backup_file")
        if email and email != original_email and backup_file and os.path.exists(backup_file):
            candidate = a
            break

    if not candidate:
        print("No alternate account backup found to verify.")
        return 3

    expected_email = candidate.get("email")
    backup_file = candidate.get("backup_file")
    print("switch_to_email:", expected_email)
    print("backup_file:", backup_file)

    with open(backup_file, "r") as f:
        target = json.load(f)

    swap = {k: target[k] for k in KEYS_TO_SWAP if k in target}
    missing = [k for k in KEYS_TO_SWAP if k not in swap]
    if missing:
        print("warning: target backup missing keys:", missing)

    # Switch
    quit_antigravity()
    time.sleep(1.0)
    kill_language_servers()
    time.sleep(0.5)

    db_set_values(swap)

    start_antigravity()
    time.sleep(1.0)

    ps_line = wait_for_language_server(25.0)
    if not ps_line:
        print("language server not found after restart")
        return 4

    pid, token, ports = parse_token_and_ports(ps_line)
    endpoint = find_working_endpoint(token, ports)
    if not endpoint:
        print("no working endpoint found; pid=", pid, "ports=", ports)
        return 5

    scheme, port = endpoint
    actual_email = get_user_status_email(scheme, port, token)

    print("quota_email_after_switch:", actual_email)
    print("endpoint:", f"{scheme}://127.0.0.1:{port}", "pid:", pid)
    print("match_expected:", actual_email == expected_email)

    # Restore original
    quit_antigravity()
    time.sleep(1.0)
    kill_language_servers()
    time.sleep(0.5)

    db_set_values(original)

    start_antigravity()
    time.sleep(1.0)

    print("restored_original_keys: ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
