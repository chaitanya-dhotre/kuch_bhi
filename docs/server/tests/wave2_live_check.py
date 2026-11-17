# server-rules-wave2.md live re-check Q1, Q3, Q5, Q7, Q9, Q11, Q12, Q14 (run on the VM against 127.0.0.1:8090).
# Signs up three throwaway accounts, makes throwaway chats, and deletes all of it at the end.
# Prints statuses and the ids it made; never another user's data. Passwords stay in memory.
import json, secrets, sys, time, urllib.request, urllib.error
B_ = 'http://127.0.0.1:' + (sys.argv[1] if len(sys.argv) > 1 else '8090')

def send(m, p, tok=None, data=None, ctype='application/json'):
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=data, method=m, headers={'Content-Type': ctype, **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=20) as x:
                t = x.read(); return x.status, (json.loads(t) if t else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(2); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}
def req(m, p, tok=None, body=None): return send(m, p, tok, json.dumps(body).encode() if body is not None else None)
col = lambda c: f'/api/collections/{c}/records'
def new(c, who, body): s, j = req('POST', col(c), T[who], body); return s, j.get('id', 'x')
def patch(c, id, who, body): return req('PATCH', f'{col(c)}/{id}', T[who], body)[0]

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
    def own_chat(who, typ='group'):
        s, c = new('conversations', who, {'type': typ, 'name': 'dryrun', 'created_by': I[who]})
        if s == 200: chats.append((who, c))
        s2, m = new('conversation_members', who, {'conversation_id': c, 'user_id': I[who], 'role': 'admin'})
        return c, m, s, s2
    s, c = new('conversations', 'C', {'type': 'group', 'name': 'dryrun', 'created_by': I['A']})
    if s == 200: chats.append(('A', c))
    R['Q1'] = f'C creates a chat with created_by=A: {s} (want 400)'
    s1, r = new('friend_requests', 'B', {'from_user': I['B'], 'to_user': I['A'], 'status': 'pending'})
    s2 = patch('friend_requests', r, 'A', {'status': 'accepted'})
    s3, _ = new('friendships', 'A', {'user_a': I['A'], 'user_b': I['B']})
    R['accept'] = f'B requests A {s1}; A accepts {s2}; friendship {s3} (want 200s)'
    G, Ga, s1, s2 = own_chat('A'); s3, Gb = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
    R['Q5'] = f'A creates group G {s1}; own row {s2}; adds friend B {s3} (want 200s)'
    AB, _, s1, s2 = own_chat('A', 'direct'); s3, _ = new('conversation_members', 'A', {'conversation_id': AB, 'user_id': I['B'], 'role': 'member'})
    R['DM'] = f'A creates DM with B {s1}, {s2}, {s3} (want 200s)'
    X, _, s1, s2 = own_chat('C'); s3, _ = new('conversation_members', 'C', {'conversation_id': X, 'user_id': I['A'], 'role': 'member'})
    R['Q3'] = f'C creates X {s1}, own row {s2}; adds A {s3} (want 200, 200, 400)'
    R['Q9'] = f'C sends A an accepted request: {new("friend_requests", "C", {"from_user": I["C"], "to_user": I["A"], "status": "accepted"})[0]} (want 400)'
    R['Q11'] = f'C makes self A\'s friend: {new("friendships", "C", {"user_a": I["C"], "user_b": I["A"]})[0]} (want 400)'
    s, mG = new('messages', 'B', {'conversation_id': G, 'sender_id': I['B'], 'type': 'text', 'encrypted_body': 'eA==', 'iv': 'aXY='})
    s2, _ = new('reactions', 'B', {'message_id': mG, 'conversation_id': G, 'user_id': I['B'], 'emoji': 'a'})
    R['Q12'] = f'B posts mG {s}, reacts {s2}; C reacts on mG: {new("reactions", "C", {"message_id": mG, "conversation_id": G, "user_id": I["C"], "emoji": "x"})[0]} (want 200, 200, 400)'
    bd = 'xXwave2Xx'
    def media(c):
        f = {'message_id': mG, 'conversation_id': c, 'media_type': 'document', 'file_name': 'x.bin', 'file_size': '3', 'expires_at': '2027-01-01 00:00:00.000Z', 'quality': 'normal'}
        body = b''.join(f'--{bd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in f.items())
        body += f'--{bd}\r\nContent-Disposition: form-data; name="file"; filename="x.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode() + b'abc\r\n' + f'--{bd}--\r\n'.encode()
        return send('POST', col('message_media'), T['B'], body, 'multipart/form-data; boundary=' + bd)[0]
    R['Q14'] = f'B media on mG naming AB: {media(AB)}; naming G: {media(G)} (want 400, 200)'
    s1 = patch('conversation_members', Gb, 'A', {'role': 'admin'}); s2 = req('DELETE', f'{col("conversation_members")}/{Ga}', T['B'])[0]
    s3, _ = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'admin'})
    R['Q7'] = f'A promotes B {s1}; B removes A {s2}; A re-adds self as admin {s3} (want 200, 204, 400)'
finally:
    # message_media.conversation_id is required with no cascade, so a chat holding media can't be
    # deleted. Delete B (the sender) first: that cascades B's messages and their media.
    if 'B' in I: R[f'del user B {I["B"]}'] = req('DELETE', f'{col("users")}/{I["B"]}', T.get('B'))[0]
    for owner, c in chats: R[f'del chat {c}'] = req('DELETE', f'{col("conversations")}/{c}', T[owner])[0]  # creator may delete, member or not
    for k in I:
        if k != 'B': R[f'del user {k} {I[k]}'] = req('DELETE', f'{col("users")}/{I[k]}', T.get(k))[0]
    for k, v in R.items(): print(f'{k:6} {v}')
