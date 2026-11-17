# former-member-history.md live re-check F1, F3, F9, F10, F13 (run on the VM against 127.0.0.1:8090).
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
L = {}
lab = lambda items: sorted(L.get(i['id'], '?') for i in items)
try:
    for k in 'ABC':
        s = secrets.token_hex(5); pw = secrets.token_urlsafe(18)
        st, j = req('POST', col('users'), None, {'email': f'dryrun_{s}@example.test', 'username': f'dryrun_{s}', 'display_name': 'dryrun', 'friend_code': secrets.token_hex(3).upper(), 'password': pw, 'passwordConfirm': pw})
        assert st == 200, ('sign-up', st, j)
        I[k] = j['id']
        st, j = req('POST', '/api/collections/users/auth-with-password', None, {'identity': f'dryrun_{s}', 'password': pw})
        assert st == 200, ('sign-in', st)
        T[k] = j['token']
    def post(c, w, label):
        s, m = new('messages', T[w], {'conversation_id': c, 'sender_id': I[w], 'type': 'text', 'encrypted_body': 'ZHJ5cnVu', 'iv': 'aXY='}); L[m] = label; return m
    _, G = new('conversations', T['A'], {'type': 'group', 'name': 'dryrun', 'created_by': I['A']}); chats.append(('A', G))
    new('conversation_members', T['A'], {'conversation_id': G, 'user_id': I['A'], 'role': 'admin'})
    _, Gb = new('conversation_members', T['A'], {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
    _, Gc = new('conversation_members', T['A'], {'conversation_id': G, 'user_id': I['C'], 'role': 'member'})
    post(G, 'B', 'm1'); post(G, 'C', 'm2'); time.sleep(1.1)
    R['setup'] = f'users {I}; chat {G}; A removes B: {req("DELETE", col("conversation_members") + "/" + Gb, T["A"])[0]}'
    time.sleep(1.1); m3 = post(G, 'A', 'm3'); time.sleep(1.1)
    R['setup'] += f'; C leaves: {req("DELETE", col("conversation_members") + "/" + Gc, T["C"])[0]}'
    FG = f'conversation_id="{G}"'
    s, it = lst('messages', T['B'], FG); R['F3'] = f'B lists G: m3 shown: {"m3" in lab(it)}; B views m3: {req("GET", col("messages") + "/" + m3, T["B"])[0]}'
    R['F1'] = f'B lists G: {s} {lab(it)}'
    s, it = lst('messages', T['C'], FG); R['F2'] = f'C lists G: {s} {lab(it)}'
    s, it = lst('former_members', T['B']); s2, it2 = lst('former_members', T['C'])
    R['F9'] = f'B former rows: {s} {[i["reason"] for i in it]}; C: {s2} {[i["reason"] for i in it2]}; A lists B rows: {len(lst("former_members", T["A"], "user_id=" + chr(34) + I["B"] + chr(34))[1])}'
    R['F10'] = f'B creates a message in G: {new("messages", T["B"], {"conversation_id": G, "sender_id": I["B"], "type": "text", "encrypted_body": "eA==", "iv": "aXY="})[0]}'
    ev = {'A': [], 'B': []}
    def sse(k):
        try:
            r = urllib.request.urlopen(urllib.request.Request(B_ + '/api/realtime'), timeout=10); cur = None
            for line in r:
                line = line.decode().strip()
                if line.startswith('event:'): cur = line[6:].strip()
                elif line.startswith('data:'):
                    dj = json.loads(line[5:])
                    if cur == 'PB_CONNECT': req('POST', '/api/realtime', T[k], {'clientId': dj['clientId'], 'subscriptions': ['messages']})
                    else: ev[k].append(dj.get('record', {}).get('id'))
        except Exception: pass
    for k in ev: threading.Thread(target=sse, args=(k,), daemon=True).start()
    time.sleep(2.5); m4 = post(G, 'A', 'm4'); time.sleep(2.5)
    R['F13'] = f'A posts m4: B got event: {m4 in ev["B"]}; A (control): {m4 in ev["A"]}'
finally:
    for owner, c in chats: R[f'del chat {c}'] = req('DELETE', f'{col("conversations")}/{c}', T[owner])[0]
    for k in I: R[f'del user {k} {I[k]}'] = req('DELETE', f'{col("users")}/{I[k]}', T.get(k))[0]
    for k, v in R.items(): print(f'{k:5} {v}')
