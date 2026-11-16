# membership-rules.md live re-check U1, U6, U8, V1, V2, V5 (run on the VM against 127.0.0.1:8090).
# Signs up three throwaway accounts, makes throwaway chats, and deletes all of it at the end.
# Prints statuses and the ids it made; never another user's data. Passwords stay in memory.
import json, secrets, sys, time, threading, urllib.request, urllib.error
from urllib.parse import quote
B_ = 'http://127.0.0.1:' + (sys.argv[1] if len(sys.argv) > 1 else '8090')

def req(m, p, tok=None, body=None):
    d = json.dumps(body).encode() if body is not None else None
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=d, method=m, headers={'Content-Type': 'application/json', **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=20) as x:
                t = x.read(); return x.status, (json.loads(t) if t else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(2); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}
col = lambda c: f'/api/collections/{c}/records'
def lst(c, tok, flt=''): s, j = req('GET', f'{col(c)}?perPage=500&filter={quote(flt)}', tok); return s, j.get('items', [])
def new(c, tok, body): s, j = req('POST', col(c), tok, body); return s, j.get('id', 'x')
def patch(c, id, tok, body): return req('PATCH', f'{col(c)}/{id}', tok, body)[0]
FIELDS = ('current_chat', 'typing_in', 'fcm_token', 'private_key_encrypted', 'private_key_salt')
shown = lambda r: ','.join(f for f in FIELDS if f in r) or 'none'

I, T, chats, R = {}, {}, [], {}
try:
    for k in 'ABC':
        s = secrets.token_hex(5); pw = secrets.token_urlsafe(18)
        st, j = req('POST', col('users'), None, {'email': f'dryrun_{s}@example.test', 'username': f'dryrun_{s}', 'display_name': 'dryrun', 'friend_code': secrets.token_hex(3).upper(), 'password': pw, 'passwordConfirm': pw})
        assert st == 200, ('sign-up', st, j)
        I[k] = j['id']
        st, j = req('POST', '/api/collections/users/auth-with-password', None, {'identity': f'dryrun_{s}', 'password': pw})
        assert st == 200, ('sign-in', st)
        T[k] = j['token']
    def chat(owner):
        _, c = new('conversations', T[owner], {'type': 'group', 'name': 'dryrun', 'created_by': I[owner]}); chats.append((owner, c))
        _, m = new('conversation_members', T[owner], {'conversation_id': c, 'user_id': I[owner], 'role': 'admin'})
        return c, m
    G, _ = chat('A'); AX, _ = chat('A'); X, Xm = chat('C')
    R['setup'] = f'users {I}; chats {chats}; B joins G: {new("conversation_members", T["A"], {"conversation_id": G, "user_id": I["B"], "role": "member"})[0]}'
    R['V6'] = 'A writes own presence/fcm: ' + str(patch('users', I['A'], T['A'], {'current_chat': G, 'typing_in': G, 'fcm_token': 'dryrun-fcm'}))
    s, j = req('GET', f'{col("users")}/{I["A"]}', T['A']); R['V4'] = f'A reads back: {j.get("current_chat") == G and j.get("fcm_token") == "dryrun-fcm"}'
    s, it = lst('users', T['C'], f'id="{I["A"]}"'); s2, every = lst('users', T['C'])
    R['V1'] = f'C lists users: {s}; fields on A: {shown(it[0]) if it else "A missing"}; rows carrying a hidden field: {sum(1 for r in every if any(f in r for f in FIELDS))} of {len(every)}'
    s, it = lst('users', T['C'], f'current_chat="{G}"'); s2, it2 = lst('users', T['C'], f'id="{I["A"]}" && private_key_encrypted~"v"')
    R['V2'] = f'C filters current_chat=G: {s} {len(it)} rows; C filters A backup~"v": {s2} {len(it2)} rows'
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
    threading.Thread(target=sse, daemon=True).start(); time.sleep(2.5)
    patch('users', I['A'], T['A'], {'typing_in': G}); time.sleep(1)
    patch('users', I['A'], T['A'], {'typing_in': AX}); time.sleep(2)
    R['V5'] = f'B realtime on A, {len(ev)} events: ' + '; '.join(f'typing_in={"G" if e.get("typing_in") == G else e.get("typing_in", "HIDDEN")} fcm={"fcm_token" in e}' for e in ev)
    R['U1'] = f'C moves own X row into G: {patch("conversation_members", Xm, T["C"], {"conversation_id": G})}'
    s, ci = new('group_invites', T['C'], {'conversation_id': X, 'invited_user_id': I['C'], 'invited_by': I['C'], 'status': 'pending'})
    R['U6'] = f'C invites self to X: {s}; re-points it to G: {patch("group_invites", ci, T["C"], {"conversation_id": G})}'
    s, inv = new('group_invites', T['A'], {'conversation_id': G, 'invited_user_id': I['C'], 'invited_by': I['A'], 'status': 'pending'})
    R['U8'] = f'A invites C to G: {s}; C self-joins G as admin: {new("conversation_members", T["C"], {"conversation_id": G, "user_id": I["C"], "role": "admin"})[0]}'
    s, it = lst('conversation_members', T['A'], f'conversation_id="{G}"'); R['U14'] = f'G members: {sorted(k for k, v in I.items() if any(r["user_id"] == v for r in it))}'
finally:
    for owner, c in chats: R[f'del chat {c}'] = req('DELETE', f'{col("conversations")}/{c}', T[owner])[0]
    for k in I: R[f'del user {k} {I[k]}'] = req('DELETE', f'{col("users")}/{I[k]}', T.get(k))[0]
    for k, v in R.items(): print(f'{k:5} {v}')
