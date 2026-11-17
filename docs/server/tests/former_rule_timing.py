# former-member-history F18 follow-up: time messages list-rule shapes on a TEST COPY
# (after migration + hook; needs tok/mk/fm.pb.js). Each variant is checked for F3 too.
# Usage: python3 former_rule_timing.py <port>
import json, sys, time, urllib.request, urllib.error
from urllib.parse import quote
B_ = 'http://127.0.0.1:' + sys.argv[1]
def req(m, p, tok=None, body=None):
    d = json.dumps(body).encode() if body is not None else None
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=d, method=m, headers={'Content-Type': 'application/json', **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=60) as x: t = x.read(); return x.status, (json.loads(t) if t else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(1.5); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}
col = lambda c: f'/api/collections/{c}/records'
U = {k: v for k, v in zip('ABCX', req('POST', '/mk/4')[1])}
T = {k: req('GET', '/tok/' + v['id'])[1]['token'] for k, v in U.items()}
I = {k: v['id'] for k, v in U.items()}
SU = req('GET', '/sutok')[1]['token']
def chat():
    c = req('POST', col('conversations'), T['A'], {'type': 'group', 'name': 'dryrun', 'created_by': I['A']})[1]['id']
    req('POST', col('conversation_members'), T['A'], {'conversation_id': c, 'user_id': I['A'], 'role': 'admin'}); return c
def add(c, w): return req('POST', col('conversation_members'), T['A'], {'conversation_id': c, 'user_id': I[w], 'role': 'member'})[1]['id']
def post(c, w): return req('POST', col('messages'), T[w], {'conversation_id': c, 'sender_id': I[w], 'type': 'text', 'encrypted_body': 'eA==', 'iv': 'aXY='})[1]['id']
# F3 setup: G (B removed before m3, C removed after), K (B removed after m3)
G = chat(); Gb = add(G, 'B'); Gc = add(G, 'C'); K = chat(); Kb = add(K, 'B')
m1 = post(G, 'B'); time.sleep(1.1); req('DELETE', f'{col("conversation_members")}/{Gb}', T['A'])
time.sleep(1.1); m3 = post(G, 'A'); time.sleep(1.1)
req('DELETE', f'{col("conversation_members")}/{Kb}', T['A']); req('DELETE', f'{col("conversation_members")}/{Gc}', T['A'])
# timing chat: 2,000 rows, X removed after them; plus noise: X is former in 30 more chats
G2 = chat(); G2x = add(G2, 'X'); req('POST', f'/bulk/{G2}/{I["A"]}/2000'); time.sleep(1.1)
req('DELETE', f'{col("conversation_members")}/{G2x}', T['A'])
for _ in range(30):
    c = chat(); x = add(c, 'X'); req('POST', f'/bulk/{c}/{I["A"]}/50'); req('DELETE', f'{col("conversation_members")}/{x}', T['A'])
MEMBER = '(@collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.conversation_id ?= conversation_id)'
EXP = '(expires_at = "" || expires_at > @now)'
FM = '(@collection.former_members.conversation_id ?= conversation_id && @collection.former_members.user_id ?= @request.auth.id && @collection.former_members.history_until ?>= created)'
FMA = '(@collection.former_members:fm.conversation_id ?= conversation_id && @collection.former_members:fm.user_id ?= @request.auth.id && @collection.former_members:fm.history_until ?>= created)'
VIA = '(conversation_id.former_members_via_conversation_id.user_id ?= @request.auth.id && conversation_id.former_members_via_conversation_id.history_until ?>= created)'
MVIA = '(conversation_id.conversation_members_via_conversation_id.user_id ?= @request.auth.id)'
V = {
    'old (member only)': f'{MEMBER} && {EXP}',
    'v2 FM via back-relation': f'({MEMBER} || {VIA}) && {EXP}',
    'v4 member via alone': f'{MVIA} && {EXP}',
    'v5 member via || FM via': f'({MVIA} || {VIA}) && {EXP}',
}
q2 = quote('conversation_id="%s"' % G2); qg = quote('conversation_id="%s"' % G)
def page(tok):
    n = 0
    for p in range(1, 5):
        n += len(req('GET', f'{col("messages")}?perPage=500&page={p}&skipTotal=1&sort=created&filter={q2}', tok)[1].get('items', []))
    return n
res = {k: {'A': [], 'X': []} for k in V}
for rnd in range(3):
    for k, rule in V.items():
        s, j = req('PATCH', '/api/collections/messages', SU, {'listRule': rule, 'viewRule': rule})
        if s != 200: res[k]['err'] = f'{s} {json.dumps(j)[:200]}'; continue
        for who in 'AX':
            for _ in range(3):
                t = time.time(); n = page(T[who]); res[k][who].append(((time.time() - t) * 1000, n))
        if rnd == 0:
            it = req('GET', f'{col("messages")}?perPage=500&filter={qg}', T['B'])[1].get('items', [])
            ids = {i['id'] for i in it}
            res[k]['F3'] = f'B sees m1: {m1 in ids}, m3: {m3 in ids}; B views m3: {req("GET", col("messages") + "/" + m3, T["B"])[0]}'
for k, r in res.items():
    if 'err' in r: print(f'{k:30} ERROR {r["err"]}'); continue
    med = lambda xs: f'{round(sorted(x[0] for x in xs)[len(xs) // 2])} ms ({xs[0][1]} rows)'
    print(f'{k:30} member A {med(r["A"])}; former X {med(r["X"])}; F3 {r["F3"]}')
