# membership-rules.md request tables U1-U14, V1-V9. Runs against a TEST COPY only
# (needs tok.pb.js + mk.pb.js in the copy's hooks). Every user and chat it touches
# is a throwaway it makes itself; no real account is used.
import json, sys, time, threading, urllib.request, urllib.error
from urllib.parse import quote
B_ = 'http://127.0.0.1:' + sys.argv[1]

def req(m, p, tok=None, body=None):
    d = json.dumps(body).encode() if body is not None else None
    for _ in range(8):
        r = urllib.request.Request(B_ + p, data=d, method=m, headers={'Content-Type': 'application/json', **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=20) as x:
                t = x.read(); return x.status, (json.loads(t) if t else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(1.5); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}

col = lambda c: f'/api/collections/{c}/records'
def lst(c, tok, flt=''): s, j = req('GET', f'{col(c)}?perPage=500&filter={quote(flt)}', tok); return s, j.get('items', [])
def new(c, tok, body): s, j = req('POST', col(c), tok, body); return s, j.get('id', 'x')
def patch(c, id, tok, body): return req('PATCH', f'{col(c)}/{id}', tok, body)[0]
def delete(c, id, tok): return req('DELETE', f'{col(c)}/{id}', tok)[0]

U = {k: v for k, v in zip('ABCDEF', req('POST', '/mk/6')[1])}
T = {k: req('GET', '/tok/' + v['id'])[1]['token'] for k, v in U.items()}
I = {k: v['id'] for k, v in U.items()}
def chat(owner, typ='group'):
    s, c = new('conversations', T[owner], {'type': typ, 'name': 'dryrun', 'created_by': I[owner]})
    s2, m = new('conversation_members', T[owner], {'conversation_id': c, 'user_id': I[owner], 'role': 'admin'})
    return c, m
R = {}
G, Ga = chat('A')
_, Gb = new('conversation_members', T['A'], {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
AX, _ = chat('A')  # a chat only A is in
F = lambda r, k: (k in r) and r[k] != ''
FIELDS = ('current_chat', 'typing_in', 'fcm_token', 'private_key_encrypted', 'private_key_salt')
shown = lambda r: ','.join(f for f in FIELDS if f in r) or 'none'

# ---- Part 2 first (C must still share nothing with A)
R['V6'] = 'A writes own hidden fields: ' + str(patch('users', I['A'], T['A'], {'current_chat': G, 'typing_in': G, 'fcm_token': 'dryrun-fcm', 'private_key_encrypted': 'v2:dryrun', 'private_key_salt': 'dryrun'}))
s, it = lst('users', T['C'], f'id="{I["A"]}"')
s2, every = lst('users', T['C'])
R['V1'] = f'C lists users: {s}; fields on A: {shown(it[0]) if it else "A missing"}; any of {len(every)} rows carrying a hidden field: {sum(1 for r in every if any(f in r for f in FIELDS))}'
s, it = lst('users', T['C'], f'current_chat="{G}"'); s2, it2 = lst('users', T['C'], f'id="{I["A"]}" && private_key_encrypted~"v"')
R['V2'] = f'C filters current_chat=G: {s} {len(it)} rows; C filters A backup~"v": {s2} {len(it2)} rows'
s, j = req('GET', f'{col("users")}/{I["A"]}', T['B']); R['V3'] = f'B gets A: {s}; fields: {shown(j)}; current_chat=G: {j.get("current_chat") == G}'
W = {'current_chat': G, 'typing_in': G, 'fcm_token': 'dryrun-fcm', 'private_key_encrypted': 'v2:dryrun', 'private_key_salt': 'dryrun'}
s, j = req('GET', f'{col("users")}/{I["A"]}', T['A']); R['V4'] = f'A gets A: {s}; fields: {shown(j)}; values equal what V6 wrote: {all(j.get(k) == v for k, v in W.items())}'
s, j = req('GET', f'{col("users")}/{I["A"]}', T['C']); R['V4b'] = f'C gets A: {s}; fields: {shown(j)}'
s, it = lst('users', T['C'], f'friend_code="{U["A"]["code"]}"'); R['V7'] = f'C finds A by friend code: {s} {len(it)} rows'
s, j = req('POST', '/api/collections/users/auth-with-password', None, {'identity': U['A']['email'], 'password': U['A']['pw']})
R['V8'] = f'A password sign-in: {s}; fields in auth response: {shown(j.get("record", {}))}'
s, j = req('POST', '/api/collections/users/auth-refresh', T['A']); R['V8b'] = f'A auth-refresh: {s}; fields: {shown(j.get("record", {}))}'
# V5 realtime: B subscribes to users/A
ev = []
def sse():
    try:
        r = urllib.request.urlopen(urllib.request.Request(B_ + '/api/realtime'), timeout=10); cur = None
        for line in r:
            line = line.decode().strip()
            if line.startswith('event:'): cur = line[6:].strip()
            elif line.startswith('data:'):
                dj = json.loads(line[5:])
                if cur == 'PB_CONNECT': req('POST', '/api/realtime', T['B'], {'clientId': dj['clientId'], 'subscriptions': ['users/' + I['A']]})
                else: ev.append(dj.get('record', {}))
    except Exception: pass
th = threading.Thread(target=sse, daemon=True); th.start(); time.sleep(2.5)
patch('users', I['A'], T['A'], {'typing_in': G}); time.sleep(1)
patch('users', I['A'], T['A'], {'typing_in': AX}); time.sleep(2)
R['V5'] = f'B realtime on A, {len(ev)} events: ' + '; '.join(f'typing_in={e.get("typing_in", "HIDDEN")!s:.15} current_chat={e.get("current_chat", "HIDDEN")!s:.15} fcm={"fcm_token" in e}' for e in ev)
patch('users', I['A'], T['A'], {'typing_in': ''})
s, j = req('GET', f'{col("users")}/{I["A"]}', T['A']); R['V6b'] = f'A clears typing_in: reads back {j.get("typing_in")!r}'
s = patch('users', I['A'], T['B'], {'current_chat': 'zzz'}); R['V6c'] = f'B writes A presence: {s}'
s, j = patch('users', I['A'], T['A'], {'is_online': True}), req('GET', f'{col("users")}/{I["A"]}', T['A'])[1]; R['V6d'] = f'A updates only is_online: {s}; is_online={j.get("is_online")}; fcm/backup untouched: {j.get("fcm_token") == "dryrun-fcm" and j.get("private_key_encrypted") == "v2:dryrun"}'
bd = 'xXdryrunXx'; mp = ''.join(f'--{bd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n' for k, v in (('about', 'mp-about'), ('fcm_token', 'mp-fcm'))) + f'--{bd}--\r\n'
r = urllib.request.Request(B_ + f'{col("users")}/{I["A"]}', data=mp.encode(), method='PATCH', headers={'Content-Type': 'multipart/form-data; boundary=' + bd, 'Authorization': T['A']})
try: s = urllib.request.urlopen(r, timeout=20).status
except urllib.error.HTTPError as e: s = e.code
j = req('GET', f'{col("users")}/{I["A"]}', T['A'])[1]; R['V6e'] = f'A multipart update (about + fcm_token): {s}; about={j.get("about")!r} fcm={j.get("fcm_token")!r}'

# ---- Part 1. C is admin of their own chats; D and E hold pending invites to G
_, Dinv = new('group_invites', T['A'], {'conversation_id': G, 'invited_user_id': I['D'], 'invited_by': I['A'], 'status': 'pending'})
_, Einv = new('group_invites', T['A'], {'conversation_id': G, 'invited_user_id': I['E'], 'invited_by': I['A'], 'status': 'pending'})
X1, X1m = chat('C'); R['U1'] = f'C moves own X row into G: {patch("conversation_members", X1m, T["C"], {"conversation_id": G})}'
X2, X2m = chat('C'); R['U2'] = f'C sets own X row user_id=B: {patch("conversation_members", X2m, T["C"], {"user_id": I["B"]})}'
R['U3'] = f'B makes self admin: {patch("conversation_members", Gb, T["B"], {"role": "admin"})}'
R['U4'] = f'B sets own muted_until: {patch("conversation_members", Gb, T["B"], {"muted_until": "2026-12-01 00:00:00.000Z"})}'
R['U5'] = f'A promotes B: {patch("conversation_members", Gb, T["A"], {"role": "admin"})}; demotes: {patch("conversation_members", Gb, T["A"], {"role": "member"})}'
X3, _ = chat('C'); s, ci = new('group_invites', T['C'], {'conversation_id': X3, 'invited_user_id': I['C'], 'invited_by': I['C'], 'status': 'pending'})
R['U6'] = f'C invites self to X: {s}; re-points it to G: {patch("group_invites", ci, T["C"], {"conversation_id": G})}'
R['U7'] = f'A re-invites D (status pending): {patch("group_invites", Dinv, T["A"], {"status": "pending"})}'
s, dm = new('conversation_members', T['D'], {'conversation_id': G, 'user_id': I['D'], 'role': 'admin'})
R['U8'] = f'D self-joins G as admin: {s}'
if s == 200: delete('conversation_members', dm, T['D'])  # undo so U9 can run
s, dm = new('conversation_members', T['D'], {'conversation_id': G, 'user_id': I['D'], 'role': 'member'})
R['U9'] = f'D joins G as member: {s}; marks invite accepted: {patch("group_invites", Dinv, T["D"], {"status": "accepted"})}'
R['U10'] = f'E declines: {patch("group_invites", Einv, T["E"], {"status": "declined"})}; flips back to pending: {patch("group_invites", Einv, T["E"], {"status": "pending"})}'
N, _ = chat('A'); s1, _ = new('conversation_members', T['A'], {'conversation_id': N, 'user_id': I['B'], 'role': 'member'}); s2, _ = new('conversation_members', T['A'], {'conversation_id': N, 'user_id': I['D'], 'role': 'member'})
R['U11'] = f'A new group, adds B: {s1}, adds D: {s2}; B reads it: {req("GET", col("conversations") + "/" + N, T["B"])[0]}'
s, Dc = new('conversations', T['A'], {'type': 'direct', 'created_by': I['A']}); s1, _ = new('conversation_members', T['A'], {'conversation_id': Dc, 'user_id': I['A'], 'role': 'admin'}); s2, _ = new('conversation_members', T['A'], {'conversation_id': Dc, 'user_id': I['B'], 'role': 'member'})
R['U12'] = f'A new DM with B: {s}, {s1}, {s2}'
R['U13'] = f'A removes B from G: {delete("conversation_members", Gb, T["A"])}; D leaves G: {delete("conversation_members", dm, T["D"])}'
s, it = lst('conversation_members', T['A'], f'conversation_id="{G}"')
R['U14'] = f'A lists G members (what a resync wraps keys for): {s}; users: {sorted(k for k, v in I.items() if any(r["user_id"] == v for r in it))}'

# ---- V9 timing: C lists 200 users, presence on half (set to G, which C is not in)
req('POST', f'/mk/200?p={G}')
def tm(f):
    xs = []
    for _ in range(7): t = time.time(); f(); xs.append((time.time() - t) * 1000)
    return round(sorted(xs)[3])
p200 = col('users') + '?perPage=200&filter=' + quote('username~"dryrun_"')
R['V9'] = f'C lists 200 users (median of 7): {tm(lambda: req("GET", p200, T["C"]))} ms'
for k, v in R.items(): print(f'{k:5} {v}')
