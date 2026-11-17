# server-rules-wave2.md: run FIRST on a TEST COPY (needs tok/mk/fm.pb.js). Tries each shape of the
# N11 members create rule (the "no member rows yet" check and @collection vs back-relation forms),
# checks Q7/Q8-style cases and times them, then puts the migration's rule back.
# Usage: python3 wave2_probe.py <port>
import json, sys, time, urllib.request, urllib.error
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
U = {k: v for k, v in zip('PQRS', req('POST', '/mk/4')[1])}
T = {k: req('GET', '/tok/' + v['id'])[1]['token'] for k, v in U.items()}
I = {k: v['id'] for k, v in U.items()}
SU = req('GET', '/sutok')[1]['token']
req('POST', col('friendships'), SU, {'user_a': I['Q'], 'user_b': I['P']})  # P and Q are friends (Q is user_a: tests the reverse branch)

AUTH = '@request.auth.id'
COLL_ADMIN = f'@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= {AUTH} && @collection.conversation_members.role ?= "admin"'
VIA = 'conversation_id.conversation_members_via_conversation_id'
VIA_ADMIN = f'{VIA}.user_id ?= {AUTH} && {VIA}.role ?= "admin"'
COLL_F = f'((@collection.friendships:fa.user_a ?= {AUTH} && @collection.friendships:fa.user_b ?= user_id) || (@collection.friendships:fb.user_a ?= user_id && @collection.friendships:fb.user_b ?= {AUTH}))'
VIA_F = f'(user_id.friendships_via_user_a.user_b ?= {AUTH} || user_id.friendships_via_user_b.user_a ?= {AUTH})'
COLL_INV = f'@collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= {AUTH} && @collection.group_invites.status ?= "pending"'
VIA_INV = f'conversation_id.group_invites_via_conversation_id.invited_user_id ?= {AUTH} && conversation_id.group_invites_via_conversation_id.status ?= "pending"'
E = {
    'coll!=': '@collection.conversation_members:existing.conversation_id != conversation_id',
    'len=0': f'{VIA}:length = 0',
    'id=""': f'{VIA}.id = ""',
}
def n11(e, admin, fr, inv):
    return (f'{AUTH} != "" && (({AUTH} = conversation_id.created_by && {AUTH} = user_id && @request.body.role = "admin" && {e})'
            f' || ({admin} && @request.body.role = "member" && {fr})'
            f' || ({AUTH} = user_id && {inv} && @request.body.role = "member"))')
OLD = (f'{AUTH} != "" && ({AUTH} = conversation_id.created_by || ({COLL_ADMIN}) || ({AUTH} = user_id && {COLL_INV} && @request.body.role = "member"))')
V = {'today (old rule)': OLD}
for k, e in E.items():
    V[f'spec @collection, E {k}'] = n11(e, COLL_ADMIN, COLL_F, COLL_INV)
    V[f'back-relation, E {k}'] = n11(e, VIA_ADMIN, VIA_F, VIA_INV)

s, mig = req('GET', '/api/collections/conversation_members', SU); MIG = mig.get('createRule')
def mem(c, u, role, who): return req('POST', col('conversation_members'), T[who], {'conversation_id': c, 'user_id': I[u], 'role': role})
def chat(): return req('POST', col('conversations'), T['P'], {'type': 'group', 'name': 'dryrun', 'created_by': I['P']})[1]['id']
def tm(f):
    xs = []
    for _ in range(7): t = time.time(); f(); xs.append((time.time() - t) * 1000)
    return round(sorted(xs)[3])
for name, rule in V.items():
    s, j = req('PATCH', '/api/collections/conversation_members', SU, {'createRule': rule})
    if s != 200: print(f'{name:32} RULE REJECTED {s} {json.dumps(j)[:200]}'); continue
    c = chat(); first = mem(c, 'P', 'admin', 'P')
    fr = mem(c, 'Q', 'member', 'P'); st = mem(c, 'R', 'member', 'P'); again = mem(c, 'R', 'admin', 'P')
    req('PATCH', f'{col("conversation_members")}/{fr[1].get("id")}', T['P'], {'role': 'admin'})
    req('DELETE', f'{col("conversation_members")}/{first[1].get("id")}', T['Q'])
    ra = mem(c, 'P', 'admin', 'P'); rm = mem(c, 'P', 'member', 'P')
    inv = req('POST', col('group_invites'), T['Q'], {'conversation_id': c, 'invited_user_id': I['S'], 'invited_by': I['Q'], 'status': 'pending'})
    ij = mem(c, 'S', 'member', 'S')
    other = chat(); notcr = mem(other, 'R', 'admin', 'R')
    def t1():
        mem(chat(), 'P', 'admin', 'P')
    x1 = tm(t1)
    xs = []
    for _ in range(7):
        c2 = chat(); mem(c2, 'P', 'admin', 'P'); t = time.time(); mem(c2, 'Q', 'member', 'P'); xs.append((time.time() - t) * 1000)
    x2 = round(sorted(xs)[3])
    print(f'{name:32} first-own-row {first[0]} | add friend {fr[0]} | add stranger {st[0]} / as admin {again[0]} | '
          f'removed creator re-adds admin {ra[0]} / member {rm[0]} | invitee joins {inv[0]},{ij[0]} | non-creator own admin row {notcr[0]} | '
          f'time chat+own row {x1} ms (incl. chat create), add friend {x2} ms')
req('PATCH', '/api/collections/conversation_members', SU, {'createRule': MIG})
print('restored migration rule:', req('GET', '/api/collections/conversation_members', SU)[1].get('createRule') == MIG)
print('want: 200 | 200 | 400 / 400 | 400 / 400 | 200,200 | 400 (today: re-add 200 / 200, stranger 200)')
