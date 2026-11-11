#!/usr/bin/env python3
"""Client-flow smoke test for roles::matrix_server.

Sends what a Matrix client sends (login, rooms, messages, typing,
receipts, to-device, media) plus the federation and delegation probes,
so every request takes the routing path a real one would. Needs two
existing users, alice and bob, with the password in SMOKE_PASSWORD.

  On a lab VM, through nginx on plain HTTP (the defaults):
      python3 smoke.py
  Against a public lab, over TLS from anywhere:
      SMOKE_BASE=https://matrix.lab.example.org SMOKE_SERVER_NAME=lab.example.org \
      SMOKE_PASSWORD=... SMOKE_ADMIN_EXPECT=403 python3 smoke.py

Without SMOKE_BASE every request goes to 127.0.0.1 with the right Host
header. SMOKE_ADMIN_EXPECT is 403 from outside: nginx only lets private
addresses reach the admin API.
"""
import json
import os
import sys
import urllib.error
import urllib.request

SERVER_NAME = os.environ.get("SMOKE_SERVER_NAME", "voxpupuli.party")
BASE = os.environ.get("SMOKE_BASE", "")
HOST = os.environ.get("SMOKE_HOST", "matrix01.voxpupu.li")
PW = os.environ.get("SMOKE_PASSWORD", "lab-password-1234")
ADMIN_EXPECT = int(os.environ.get("SMOKE_ADMIN_EXPECT", "200"))
LOCAL = not BASE
results = []


def call(name, method, path, token=None, body=None, host=HOST, raw=None, ctype=None, expect=(200,)):
    data = None
    if LOCAL:
        url, headers = "http://127.0.0.1" + path, {"Host": host}
    else:
        url, headers = (BASE if host == HOST else "https://" + host) + path, {}
    if raw is not None:
        data = raw
        headers["Content-Type"] = ctype or "application/octet-stream"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            status, payload, hdrs = r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        status, payload, hdrs = e.code, e.read(), dict(e.headers)
    except Exception as e:  # noqa: BLE001
        status, payload, hdrs = 0, str(e).encode(), {}
    try:
        parsed = json.loads(payload)
    except Exception:  # noqa: BLE001
        parsed = {"_raw": payload[:200].decode("latin1")}
    ok = status in expect
    detail = "" if ok else json.dumps(parsed)[:160]
    results.append((ok, name, status, f"{method} {path.split('?')[0][:70]}", detail))
    return parsed, hdrs, status


def login(user):
    r, _, _ = call(f"login {user}", "POST", "/_matrix/client/v3/login",
                   body={"type": "m.login.password",
                         "identifier": {"type": "m.id.user", "user": user},
                         "password": PW})
    return r.get("access_token"), r.get("user_id")


C = "/_matrix/client"
call("versions", "GET", f"{C}/versions")
call("login flows", "GET", f"{C}/v3/login")
a_tok, a_id = login("alice")
b_tok, b_id = login("bob")
if not (a_tok and b_tok):
    for r in results:
        print(r)
    sys.exit("login failed; cannot continue")

call("whoami", "GET", f"{C}/v3/account/whoami", a_tok)
call("capabilities", "GET", f"{C}/v3/capabilities", a_tok)
call("devices", "GET", f"{C}/v3/devices", a_tok)
call("set displayname", "PUT", f"{C}/v3/profile/{a_id}/displayname", a_tok, {"displayname": "Alice"})
call("get profile", "GET", f"{C}/v3/profile/{a_id}", a_tok)
call("pushrules get", "GET", f"{C}/v3/pushrules/", a_tok)
call("pushrules put", "PUT", f"{C}/v3/pushrules/global/content/smoke", a_tok,
     {"pattern": "smoke", "actions": ["notify"]})
call("pushers get", "GET", f"{C}/v3/pushers", a_tok)
call("presence put", "PUT", f"{C}/v3/presence/{a_id}/status", a_tok, {"presence": "online"})
call("presence get", "GET", f"{C}/v3/presence/{a_id}/status", a_tok)
call("filter create", "POST", f"{C}/v3/user/{a_id}/filter", a_tok, {"room": {"timeline": {"limit": 5}}})
call("account_data put", "PUT", f"{C}/v3/user/{a_id}/account_data/org.lab.smoke", a_tok, {"x": 1})
call("account_data get", "GET", f"{C}/v3/user/{a_id}/account_data/org.lab.smoke", a_tok)
call("keys upload", "POST", f"{C}/v3/keys/upload", a_tok, {})
call("keys query", "POST", f"{C}/v3/keys/query", a_tok, {"device_keys": {b_id: []}})
call("room_keys version", "GET", f"{C}/v3/room_keys/version", a_tok, expect=(200, 404))
call("thirdparty protocols", "GET", f"{C}/v3/thirdparty/protocols", a_tok)
call("turnServer", "GET", f"{C}/v3/voip/turnServer", a_tok)
call("openid token", "POST", f"{C}/v3/user/{a_id}/openid/request_token", a_tok, {})
call("notifications", "GET", f"{C}/v3/notifications", a_tok)

room, _, _ = call("createRoom", "POST", f"{C}/v3/createRoom", a_tok,
                  {"name": "smoke", "preset": "private_chat", "invite": [b_id]})
rid = room.get("room_id", f"!missing:{SERVER_NAME}")
call("join", "POST", f"{C}/v3/rooms/{rid}/join", b_tok, {})
ev, _, _ = call("send message", "PUT", f"{C}/v3/rooms/{rid}/send/m.room.message/txn1", a_tok,
                {"msgtype": "m.text", "body": "hello from the lab"})
eid = ev.get("event_id", "$missing")
call("state put", "PUT", f"{C}/v3/rooms/{rid}/state/m.room.topic", a_tok, {"topic": "smoke"})
call("typing", "PUT", f"{C}/v3/rooms/{rid}/typing/{a_id}", a_tok, {"typing": True, "timeout": 5000})
call("receipt", "POST", f"{C}/v3/rooms/{rid}/receipt/m.read/{eid}", b_tok, {})
call("read_markers", "POST", f"{C}/v3/rooms/{rid}/read_markers", b_tok,
     {"m.fully_read": eid, "m.read": eid})
call("room tag put", "PUT", f"{C}/v3/user/{a_id}/rooms/{rid}/tags/u.smoke", a_tok, {"order": 0.5})
call("room tags get", "GET", f"{C}/v3/user/{a_id}/rooms/{rid}/tags", a_tok)
call("room account_data put", "PUT", f"{C}/v3/user/{a_id}/rooms/{rid}/account_data/org.lab.smoke", a_tok, {"y": 2})
call("sendToDevice", "PUT", f"{C}/v3/sendToDevice/org.lab.smoke/txn1", a_tok,
     {"messages": {b_id: {"*": {"hello": "device"}}}})
call("messages", "GET", f"{C}/v3/rooms/{rid}/messages?dir=b&limit=5", a_tok)
call("members", "GET", f"{C}/v3/rooms/{rid}/members", a_tok)
call("event", "GET", f"{C}/v3/rooms/{rid}/event/{eid}", a_tok)
call("report event", "POST", f"{C}/v3/rooms/{rid}/report/{eid}", b_tok, {"reason": "smoke"})
call("redact", "PUT", f"{C}/v3/rooms/{rid}/redact/{eid}/txn2", a_tok, {})
call("alias put", "PUT", f"{C}/v3/directory/room/%23smoke-{rid[1:9]}:{SERVER_NAME}", a_tok, {"room_id": rid})
call("publicRooms", "GET", f"{C}/v3/publicRooms", a_tok)
call("user_directory", "POST", f"{C}/v3/user_directory/search", a_tok, {"search_term": "bob"})
call("search", "POST", f"{C}/v3/search", a_tok,
     {"search_categories": {"room_events": {"search_term": "hello"}}})

sync, _, _ = call("sync alice", "GET", f"{C}/v3/sync?timeout=0", a_tok)
bsync, _, _ = call("sync bob", "GET", f"{C}/v3/sync?timeout=0", b_tok)
got_td = any(e.get("type") == "org.lab.smoke" for e in bsync.get("to_device", {}).get("events", []))
results.append((got_td, "to-device delivered to bob via sync", 0, "", "" if got_td else "not in bob's sync"))
joined = rid in sync.get("rooms", {}).get("join", {})
results.append((joined, "room visible in alice's sync", 0, "", "" if joined else "room missing"))

# Media: upload (legacy path is still the upload endpoint), authenticated download
up, _, _ = call("media upload", "POST", "/_matrix/media/v3/upload?filename=smoke.txt", a_tok,
                raw=b"lab media payload", ctype="text/plain")
mxc = up.get("content_uri", f"mxc://{SERVER_NAME}/missing").split("/")[-1]
call("media config", "GET", f"{C}/v1/media/config", a_tok)
call("media download (authenticated)", "GET", f"{C}/v1/media/download/{SERVER_NAME}/{mxc}", a_tok)

# Federation-facing and delegation
call("federation version", "GET", "/_matrix/federation/v1/version")
call("server keys", "GET", "/_matrix/key/v2/server")
call("well-known server", "GET", "/.well-known/matrix/server", host=SERVER_NAME)
call("well-known client", "GET", "/.well-known/matrix/client", host=SERVER_NAME)
call("admin API", "GET", "/_synapse/admin/v1/server_version", a_tok, expect=(ADMIN_EXPECT,))

call("leave", "POST", f"{C}/v3/rooms/{rid}/leave", b_tok, {})
call("forget", "POST", f"{C}/v3/rooms/{rid}/forget", b_tok, {})
call("logout", "POST", f"{C}/v3/logout", b_tok, {})

bad = [r for r in results if not r[0]]
for ok, name, status, what, detail in results:
    print(f"{'ok  ' if ok else 'FAIL'} {status or '':>3} {name:<36} {what} {detail}")
print(f"\n{len(results) - len(bad)} passed, {len(bad)} failed")
sys.exit(1 if bad else 0)
