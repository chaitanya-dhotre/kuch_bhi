# server-rules-wave2.md request table Q1-Q19. Runs against a TEST COPY only (needs tok.pb.js +
# mk.pb.js in the copy's hooks). Every user, chat and row it touches is a throwaway it makes itself.
# Usage: python3 wave2_request_table.py <port>
import base64, json, sys, time, threading, urllib.request, urllib.error
B_ = 'http://127.0.0.1:' + sys.argv[1]
JPEG = base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCeiiivkD6o/9k=')

def send(m, p, tok=None, data=None, ctype='application/json'):
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=data, method=m, headers={'Content-Type': ctype, **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=30) as x:
                t = x.read(); return x.status, (json.loads(t) if t else {})
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(1.5); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}
def req(m, p, tok=None, body=None): return send(m, p, tok, json.dumps(body).encode() if body is not None else None)
def multipart(p, tok, fields, files):
    bd = 'xXwave2Xx'; out = b''
    for k, v in fields.items(): out += f'--{bd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, (fn, ct, data) in files.items():
        out += f'--{bd}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: {ct}\r\n\r\n'.encode() + data + b'\r\n'
    return send('POST', p, tok, out + f'--{bd}--\r\n'.encode(), 'multipart/form-data; boundary=' + bd)

col = lambda c: f'/api/collections/{c}/records'
def new(c, who, body): s, j = req('POST', col(c), T[who], body); return s, j.get('id', 'x')
def patch(c, id, who, body): return req('PATCH', f'{col(c)}/{id}', T[who], body)[0]
def delete(c, id, who): return req('DELETE', f'{col(c)}/{id}', T[who])[0]

NAMES = ['A', 'B', 'C', 'D', 'E2', 'D2', 'X1']
U = dict(zip(NAMES, req('POST', f'/mk/{len(NAMES)}')[1]))
T = {k: req('GET', '/tok/' + v['id'])[1]['token'] for k, v in U.items()}
I = {k: v['id'] for k, v in U.items()}
R = {}

def befriend(frm, to):  # the app's flow: frm sends, to accepts, to creates the friendship (user_a = to)
    s1, r = new('friend_requests', frm, {'from_user': I[frm], 'to_user': I[to], 'status': 'pending'})
    s2 = patch('friend_requests', r, to, {'status': 'accepted'})
    s3, _ = new('friendships', to, {'user_a': I[to], 'user_b': I[frm]})
    return s1, s2, s3
def own_chat(who, typ='group', name='dryrun'):
    s, c = new('conversations', who, {'type': typ, 'name': name, 'created_by': I[who]})
    s2, m = new('conversation_members', who, {'conversation_id': c, 'user_id': I[who], 'role': 'admin'})
    return c, m, s, s2
def msg(c, who, typ='text'):
    return new('messages', who, {'conversation_id': c, 'sender_id': I[who], 'type': typ, 'encrypted_body': 'eA==', 'iv': 'aXY='})

R['setup'] = f'B->A friends {befriend("B", "A")}; D->A friends {befriend("D", "A")}'

# Q1-Q4: a stranger (C, friends with nobody)
R['Q1'] = f'C creates a chat with created_by=A: {req("POST", col("conversations"), T["C"], {"type": "group", "name": "dryrun", "created_by": I["A"]})[0]}'
X, Xm, s1, s2 = own_chat('C'); R['Q2'] = f'C creates own group X: {s1}; own admin row: {s2}'
s1, m1 = new('conversation_members', 'C', {'conversation_id': X, 'user_id': I['A'], 'role': 'member'})
if s1 == 200: delete('conversation_members', m1, 'C')
s2, _ = new('conversation_members', 'C', {'conversation_id': X, 'user_id': I['A'], 'role': 'admin'})
R['Q3'] = f'C adds A to X as member: {s1}; as admin: {s2}'
CD, _, s1, s2 = own_chat('C', 'direct'); s3, _ = new('conversation_members', 'C', {'conversation_id': CD, 'user_id': I['A'], 'role': 'member'})
R['Q4'] = f'C creates a DM: {s1}; own admin row: {s2}; A\'s member row: {s3}'

# Q5: the app's group create (multipart with an icon), then friends B and D
s, j = multipart(col('conversations'), T['A'], {'type': 'group', 'name': 'dryrun', 'created_by': I['A'], 'only_admins_can_message': 'false'}, {'icon': ('icon.jpg', 'image/jpeg', JPEG)})
G = j.get('id', 'x')
s2, Ga = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'admin'})
s3, Gb = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
s4, Gd = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['D'], 'role': 'member'})
R['Q5'] = f'A creates group G with icon: {s} (icon set: {bool(j.get("icon"))}); own admin row {s2}; adds B {s3}; adds D {s4}'
AB, _, s1, s2 = own_chat('A', 'direct'); s3, _ = new('conversation_members', 'A', {'conversation_id': AB, 'user_id': I['B'], 'role': 'member'})
R['setup2'] = f'DM AB: {s1}, {s2}, {s3}'

# Q18 realtime: A subscribes before Q6 and Q13
ev = []
def sse():
    try:
        r = urllib.request.urlopen(urllib.request.Request(B_ + '/api/realtime'), timeout=40); cur = None
        for line in r:
            line = line.decode().strip()
            if line.startswith('event:'): cur = line[6:].strip()
            elif line.startswith('data:'):
                dj = json.loads(line[5:])
                if cur == 'PB_CONNECT': req('POST', '/api/realtime', T['A'], {'clientId': dj['clientId'], 'subscriptions': ['friendships', 'friend_requests', 'reactions', 'conversation_members']})
                else: ev.append(cur)
    except Exception: pass
threading.Thread(target=sse, daemon=True).start(); time.sleep(2.5)

# Q6: a full accept, then the DM
s1, r = new('friend_requests', 'E2', {'from_user': I['E2'], 'to_user': I['A'], 'status': 'pending'})
s2 = patch('friend_requests', r, 'A', {'status': 'accepted'})
s3, _ = new('friendships', 'A', {'user_a': I['A'], 'user_b': I['E2']})
DE, _, s4, s5 = own_chat('A', 'direct'); s6, _ = new('conversation_members', 'A', {'conversation_id': DE, 'user_id': I['E2'], 'role': 'member'})
R['Q6'] = f'E2 requests A {s1}; A accepts {s2}; friendship {s3}; DM {s4}, own row {s5}, E2 row {s6}'

sG, mG = msg(G, 'B'); sD, mD = msg(AB, 'A'); R['setup3'] = f'mG by B: {sG}; mD by A: {sD}'

# Q12-Q16: reactions, media, unused collections, system notices
R['Q12'] = f'C reacts on mG in G: {new("reactions", "C", {"message_id": mG, "conversation_id": G, "user_id": I["C"], "emoji": "x"})[0]}'
s1, rx = new('reactions', 'B', {'message_id': mG, 'conversation_id': G, 'user_id': I['B'], 'emoji': 'a'})
s2 = delete('reactions', rx, 'B')
s3, _ = new('reactions', 'B', {'message_id': mG, 'conversation_id': AB, 'user_id': I['B'], 'emoji': 'b'})
s4, ry = new('reactions', 'B', {'message_id': mG, 'conversation_id': G, 'user_id': I['B'], 'emoji': 'c'})
s5 = patch('reactions', ry, 'B', {'emoji': 'd'})
R['Q13'] = f'B reacts on mG {s1}, deletes it {s2}; reacts on mG naming AB {s3}; reacts again {s4}, edits the emoji {s5}'
MF = lambda c: {'message_id': mG, 'conversation_id': c, 'media_type': 'document', 'file_name': 'x.bin', 'file_size': '3', 'expires_at': '2027-01-01 00:00:00.000Z', 'quality': 'normal'}
s1, _ = multipart(col('message_media'), T['B'], MF(AB), {'file': ('x.bin', 'application/octet-stream', b'abc')})
s2, _ = multipart(col('message_media'), T['B'], MF(G), {'file': ('x.bin', 'application/octet-stream', b'abc')})
R['Q14'] = f'B media on mG naming AB: {s1}; naming G: {s2}'
s1, _ = new('polls', 'C', {'message_id': mG, 'conversation_id': G, 'question': 'q', 'options': [{'id': '1', 'text': 'a'}], 'votes': {}, 'created_by': I['C']})
s2, _ = new('scheduled_messages', 'C', {'sender_id': I['C'], 'conversation_id': G, 'encrypted_body': 'eA==', 'iv': 'aXY=', 'send_at': '2027-01-01 00:00:00.000Z'})
R['Q15'] = f'C creates a poll in G: {s1}; a scheduled message for G: {s2}'
R['Q16'] = f'B posts a system notice in G: {msg(G, "B", "system")[0]}; C does: {msg(G, "C", "system")[0]}'

# Q9-Q11: friend requests and friendships
s1, _ = new('friend_requests', 'C', {'from_user': I['C'], 'to_user': I['A'], 'status': 'accepted'})
s2, Cr = new('friend_requests', 'C', {'from_user': I['C'], 'to_user': I['A'], 'status': 'pending'})
R['Q9'] = f'C sends A a request as accepted: {s1}; as pending: {s2}'
R['Q10'] = (f'A edits C\'s pending request: from_user=B {patch("friend_requests", Cr, "A", {"from_user": I["B"]})}; '
            f'to_user=D {patch("friend_requests", Cr, "A", {"to_user": I["D"]})}; status=pending {patch("friend_requests", Cr, "A", {"status": "pending"})}; '
            f'status=declined {patch("friend_requests", Cr, "A", {"status": "declined"})}')
s1, _ = new('friendships', 'C', {'user_a': I['C'], 'user_b': I['A']})
new('friend_requests', 'D2', {'from_user': I['D2'], 'to_user': I['A'], 'status': 'pending'})
s2, _ = new('friendships', 'A', {'user_a': I['A'], 'user_b': I['D2']})
s3, _ = new('friendships', 'A', {'user_a': I['A'], 'user_b': I['C']})
R['Q11'] = f'C makes self A\'s friend: {s1}; A befriends D2 (request pending): {s2}; A befriends C (C\'s request declined): {s3}; after an accept: see Q6'

# Q8: a new chat's first own row
R['Q8'] = f'A creates a chat and its own first admin row: {own_chat("A")[3]}'

# Q19: an invite to a non-friend still works
s1, inv = new('group_invites', 'A', {'conversation_id': G, 'invited_user_id': I['C'], 'invited_by': I['A'], 'status': 'pending'})
s2, Gc = new('conversation_members', 'C', {'conversation_id': G, 'user_id': I['C'], 'role': 'member'})
s3 = patch('group_invites', inv, 'C', {'status': 'accepted'})
R['Q19'] = f'A invites C to G {s1}; C joins as member {s2}; invite accepted {s3}'

# Q7: a removed creator re-adds themselves; Q7b: re-added by invite
s1 = patch('conversation_members', Gb, 'A', {'role': 'admin'})
s2 = delete('conversation_members', Ga, 'B')
s3, m3 = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'admin'})
if s3 == 200: delete('conversation_members', m3, 'A')
s4, m4 = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'member'})
if s4 == 200: delete('conversation_members', m4, 'A')
R['Q7'] = f'A promotes B {s1}; B removes A {s2}; A re-adds self as admin {s3}; as member {s4}'
s1, inv = new('group_invites', 'B', {'conversation_id': G, 'invited_user_id': I['A'], 'invited_by': I['B'], 'status': 'pending'})
s2, _ = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'member'})
R['Q7b'] = f'B invites A back {s1}; A joins as member {s2}; accepts {patch("group_invites", inv, "A", {"status": "accepted"})}'

# Q17 timing (median of 7)
def med(xs): return round(sorted(xs)[len(xs) // 2])
t1, t2, t3 = [], [], []
for i in range(7):
    s, c = new('conversations', 'A', {'type': 'group', 'name': 'dryrun', 'created_by': I['A']})
    t = time.time(); new('conversation_members', 'A', {'conversation_id': c, 'user_id': I['A'], 'role': 'admin'}); t1.append((time.time() - t) * 1000)
    t = time.time(); new('conversation_members', 'A', {'conversation_id': c, 'user_id': I['B'], 'role': 'member'}); t2.append((time.time() - t) * 1000)
    t = time.time(); new('reactions', 'B', {'message_id': mG, 'conversation_id': G, 'user_id': I['B'], 'emoji': f't{i}'}); t3.append((time.time() - t) * 1000)
R['Q17'] = f'own first row {med(t1)} ms; add friend {med(t2)} ms; reaction create {med(t3)} ms'

time.sleep(1.5)
R['Q18'] = 'A realtime events: ' + ', '.join(f'{k}={ev.count(k)}' for k in ('friendships', 'friend_requests', 'reactions', 'conversation_members'))
for k, v in R.items(): print(f'{k:6} {v}')
