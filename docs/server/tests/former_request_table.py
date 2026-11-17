# former-member-history.md §6 request table F1-F18. Runs against a TEST COPY only
# (needs tok.pb.js, mk.pb.js, fm.pb.js in the copy's hooks). Every user and chat it
# touches is a throwaway it makes itself; no real account or chat is used.
# Usage: python3 former_request_table.py <port>
import json, sys, time, threading, urllib.request, urllib.error
from urllib.parse import quote
B_ = 'http://127.0.0.1:' + sys.argv[1]

def req(m, p, tok=None, body=None, raw=None, ct='application/json'):
    d = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=d, method=m, headers={'Content-Type': ct, **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=30) as x:
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
def view(c, id, tok): return req('GET', f'{col(c)}/{id}', tok)[0]
tick = lambda: time.sleep(1.1)  # keeps created / history_until apart by more than a ms

U = {k: v for k, v in zip('ABCD', req('POST', '/mk/4')[1])}
T = {k: req('GET', '/tok/' + v['id'])[1]['token'] for k, v in U.items()}
I = {k: v['id'] for k, v in U.items()}
SU = req('GET', '/sutok')[1]['token']
L = {}  # message id -> label
def chat(owner, typ='group'):
    s, c = new('conversations', T[owner], {'type': typ, 'name': 'dryrun', 'created_by': I[owner]})
    new('conversation_members', T[owner], {'conversation_id': c, 'user_id': I[owner], 'role': 'admin'})
    return c
def add(c, who, by='A'): return new('conversation_members', T[by], {'conversation_id': c, 'user_id': I[who], 'role': 'member'})[1]
def post(c, who, label):
    s, m = new('messages', T[who], {'conversation_id': c, 'sender_id': I[who], 'type': 'text', 'encrypted_body': 'ZHJ5cnVu', 'iv': 'aXY='})
    L[m] = label; return m
def key(c, who, v): return new('group_keys', T['A'], {'conversation_id': c, 'user_id': I[who], 'encrypted_key': 'aXY=:a2V5', 'encrypted_by_user_id': I['A'], 'key_version': v})[0]
labels = lambda items: sorted(L.get(i['id'], '?') for i in items)
def former(flt): return lst('former_members', SU, flt)[1]
R = {}

# ---- setup (§6 steps 1-9)
G = chat('A'); Gb = add(G, 'B'); Gc = add(G, 'C')
[key(G, w, 1) for w in 'ABC']
m1 = post(G, 'B', 'm1')
bd = 'xXdryrunXx'
parts = [('message_id', m1), ('conversation_id', G), ('media_type', 'image'), ('file_name', 'm1.png'), ('file_size', '67'), ('expires_at', '2027-12-01 00:00:00.000Z')]
mp = ''.join(f'--{bd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n' for k, v in parts).encode()
png = bytes.fromhex('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c63000100000500010d0a2db40000000049454e44ae426082')
mp += f'--{bd}\r\nContent-Disposition: form-data; name="file"; filename="m1.png"\r\nContent-Type: image/png\r\n\r\n'.encode() + png + f'\r\n--{bd}--\r\n'.encode()
s, j = req('POST', col('message_media'), T['B'], raw=mp, ct='multipart/form-data; boundary=' + bd)
m1media = j.get('id', 'x'); R['setup'] = f'm1 media create: {s} {"" if s == 200 else json.dumps(j)[:200]}'
m2 = post(G, 'C', 'm2')
K = chat('A'); Kb = add(K, 'B'); [key(K, w, 1) for w in 'AB']
tick(); R['setup'] += f'; A removes B from G: {delete("conversation_members", Gb, T["A"])}'
tick(); m3 = post(G, 'A', 'm3')
s, it = lst('conversation_members', T['A'], f'conversation_id="{G}"')
R['F17'] = f'A lists G members after removing B (rotation targets): {sorted(k for k, v in I.items() if any(r["user_id"] == v for r in it))}'
[key(G, w, 2) for w in 'AC']
tick(); R['setup'] += f'; A removes B from K: {delete("conversation_members", Kb, T["A"])}'
post(G, 'C', 'C left'); tick()
R['setup'] += f'; C deletes own G row: {delete("conversation_members", Gc, T["C"])}'
tick(); m4 = post(G, 'A', 'm4')
FG = f'conversation_id="{G}"'

# ---- table
s, it = lst('messages', T['B'], FG); R['F3'] = f'B lists G: m3 shown: {"m3" in labels(it)}'
R['F1'] = f'B lists messages in G: {s} {labels(it)}'
s, it = lst('messages', T['C'], FG); R['F2'] = f'C lists messages in G: {s} {labels(it)}'
s, it = lst('messages', T['D'], FG); R['F4'] = f'D lists G: {s} {labels(it)}; D views m1: {view("messages", m1, T["D"])}'
R['F5'] = f'B views m3: {view("messages", m3, T["B"])}'
s, it = lst('message_media', T['B'], FG); R['F6'] = f'B lists media in G: {s} {len(it)} rows (m1 media: {any(i["id"] == m1media for i in it)}); views m1 media: {view("message_media", m1media, T["B"])}'
s, it = lst('conversations', T['B']); R['F7'] = f'B lists conversations: {s}; G: {any(i["id"] == G for i in it)}, K: {any(i["id"] == K for i in it)}, total {len(it)}'
s, it = lst('conversation_members', T['B'], FG); s2, it2 = lst('group_keys', T['B'], FG)
R['F8'] = f'B lists G members: {s} {len(it)}; B lists G keys: {s2} versions {sorted(i["key_version"] for i in it2)}, all own: {all(i["user_id"] == I["B"] for i in it2)}'
s, it = lst('former_members', T['B']); s2, it2 = lst('former_members', T['D']); s3, it3 = lst('former_members', T['D'], f'user_id="{I["B"]}"')
cr = former(f'conversation_id="{G}" && user_id="{I["C"]}"')
R['F9'] = (f'B lists former_members: {s} {sorted(("G" if i["conversation_id"] == G else "K" if i["conversation_id"] == K else "?", i["reason"]) for i in it)}; '
           f'C G row reason: {[i["reason"] for i in cr]}; D lists: {s2} {len(it2)}; D filters user_id=B: {s3} {len(it3)}')
s, _ = new('messages', T['B'], {'conversation_id': G, 'sender_id': I['B'], 'type': 'text', 'encrypted_body': 'eA==', 'iv': 'aXY='}); R['F10'] = f'B creates a message in G: {s}'
s, _ = new('conversation_members', T['B'], {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
R['F11'] = f'B creates own member row in G: {s}; B renames G: {patch("conversations", G, T["B"], {"name": "pwned"})}'
own = [i for i in lst('former_members', T['B'])[1] if i['conversation_id'] == G]
fid = own[0]['id'] if own else 'none'
R['F12'] = (f'B creates own row: {new("former_members", T["B"], {"conversation_id": K, "user_id": I["B"], "history_until": "2030-01-01 00:00:00.000Z"})[0]}; '
            f'for D in G: {new("former_members", T["B"], {"conversation_id": G, "user_id": I["D"], "history_until": "2030-01-01 00:00:00.000Z"})[0]}; '
            f'updates own G row: {patch("former_members", fid, T["B"], {"history_until": "2030-01-01 00:00:00.000Z"})}; deletes it: {delete("former_members", fid, T["B"])}')
# F13 realtime: B (former) and A (member control) subscribe to all messages; A posts m5
ev = {'A': [], 'B': []}
def sse(k):
    try:
        r = urllib.request.urlopen(urllib.request.Request(B_ + '/api/realtime'), timeout=12); cur = None
        for line in r:
            line = line.decode().strip()
            if line.startswith('event:'): cur = line[6:].strip()
            elif line.startswith('data:'):
                dj = json.loads(line[5:])
                if cur == 'PB_CONNECT': req('POST', '/api/realtime', T[k], {'clientId': dj['clientId'], 'subscriptions': ['messages']})
                else: ev[k].append(dj.get('record', {}).get('id'))
    except Exception: pass
th = [threading.Thread(target=sse, args=(k,), daemon=True) for k in ev]; [t.start() for t in th]; time.sleep(2.5)
m5 = post(G, 'A', 'm5'); time.sleep(2.5)
R['F13'] = f'A posts m5: B got m5 event: {m5 in ev["B"]} ({len(ev["B"])} events); A (control) got it: {m5 in ev["A"]}'
# F14 re-add then remove again
before = former(f'conversation_id="{G}" && user_id="{I["B"]}"')
s1, inv = new('group_invites', T['A'], {'conversation_id': G, 'invited_user_id': I['B'], 'invited_by': I['A'], 'status': 'pending'})
s2, Gb2 = new('conversation_members', T['B'], {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
s3 = patch('group_invites', inv, T['B'], {'status': 'accepted'})
s, it = lst('messages', T['B'], FG)
R['F14'] = f'invite {s1}, join {s2}, accept {s3}; B lists G as member: {labels(it)}'
tick(); s = delete('conversation_members', Gb2, T['A']); after = former(f'conversation_id="{G}" && user_id="{I["B"]}"')
h0 = before[0]['history_until'] if before else '-'; h1 = after[0]['history_until'] if after else '-'
R['F14'] += f'; removed again: {s}; former rows (G,B): {len(before)} -> {len(after)}; history_until moved later: {h1 > h0} ({h0} -> {h1}); joined_at kept: {bool(before) and bool(after) and before[0]["joined_at"] == after[0]["joined_at"]}'
s, it = lst('messages', T['B'], FG); R['F14'] += f'; B lists G after: {labels(it)}'
# F15 cascade
n0 = len(former(f'conversation_id="{K}"'))
FK = 'conversation_id="%s"' % K
R['F15'] = f'K former rows before: {n0}; A deletes K: {delete("conversations", K, T["A"])}; after: {len(former(FK))}'
# F16 DM
Dm = chat('A', 'direct'); Dmb = add(Dm, 'B')
FD = 'conversation_id="%s"' % Dm
R['F16'] = f'superuser deletes B DM row: {delete("conversation_members", Dmb, SU)}; DM former rows: {len(former(FD))}'
# F18 timing: G2 with 2,000 rows, B removed after them
G2 = chat('A'); G2b = add(G2, 'B')
req('POST', f'/bulk/{G2}/{I["A"]}/2000'); tick(); delete('conversation_members', G2b, T['A']); tick()
F2q = quote('conversation_id="%s"' % G2)
def tm(tok):
    xs = []; n = 0
    for _ in range(5):
        t = time.time(); n = 0
        for p in range(1, 5):
            s, j = req('GET', f'{col("messages")}?perPage=500&page={p}&skipTotal=1&sort=created&filter={F2q}', tok)
            n += len(j.get('items', []))
        xs.append((time.time() - t) * 1000)
    return f'{round(sorted(xs)[2])} ms ({n} rows)'
R['F18'] = f'2,000 rows in 4 pages of 500, median of 5: member A {tm(T["A"])}; former B {tm(T["B"])}'
for k in ['setup', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12', 'F13', 'F14', 'F15', 'F16', 'F17', 'F18']:
    print(f'{k:5} {R.get(k)}')
