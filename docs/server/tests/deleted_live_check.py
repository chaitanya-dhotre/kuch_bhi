# delete-everyone-leftovers.md §5 live re-check D1-D10 (run on the VM against 127.0.0.1:8090).
# Signs up two throwaway accounts (A admin, B the sender), makes one throwaway group, deletes all of it
# at the end. Never reads another user's data. Passwords stay in memory.
# Usage: python3 deleted_live_check.py [port]
import base64, json, secrets, sys, time, urllib.request, urllib.error
B_ = 'http://127.0.0.1:' + (sys.argv[1] if len(sys.argv) > 1 else '8090')
JPEG = base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCeiiivkD6o/9k=')

def send(m, p, tok=None, data=None, ctype='application/json', raw=False):
    for _ in range(10):
        r = urllib.request.Request(B_ + p, data=data, method=m, headers={'Content-Type': ctype, **({'Authorization': tok} if tok else {})})
        try:
            with urllib.request.urlopen(r, timeout=30) as x:
                t = x.read()
                return x.status, (t if raw else (json.loads(t) if t else {}))
        except urllib.error.HTTPError as e:
            t = e.read()
            if e.code == 429: time.sleep(1.5); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, {}
    return 429, {}
def req(m, p, tok=None, body=None): return send(m, p, tok, json.dumps(body).encode() if body is not None else None)
def multipart(p, tok, fields, files):
    bd = 'xXdelXx'; out = b''
    for k, v in fields.items(): out += f'--{bd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, (fn, ct, data) in files.items():
        out += f'--{bd}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: {ct}\r\n\r\n'.encode() + data + b'\r\n'
    return send('POST', p, tok, out + f'--{bd}--\r\n'.encode(), 'multipart/form-data; boundary=' + bd)

col = lambda c: f'/api/collections/{c}/records'
def new(c, who, body): s, j = req('POST', col(c), T[who], body); return s, j.get('id', 'x')
def patch(c, id, who, body): s, j = req('PATCH', f'{col(c)}/{id}', T[who], body); return s if s == 200 else f'{s} {json.dumps(j.get("data", {}))}'
def get(c, id, who): return req('GET', f'{col(c)}/{id}', T[who])
def count(c, who, flt): return req('GET', col(c) + '?perPage=1&filter=' + urllib.request.quote(flt), T[who])[1].get('totalItems')
def mcount(m, who='A'): return count('message_media', who, 'message_id = "' + m + '"')
def file_status(url): return send('GET', url, raw=True)[0]
def media(m, who='B'):
    s, j = multipart(col('message_media'), T[who],
        {'message_id': m, 'conversation_id': G, 'media_type': 'image', 'file_name': 'x.jpg', 'file_size': str(len(JPEG)), 'expires_at': '2027-01-01 00:00:00.000Z', 'quality': 'normal'},
        {'file': ('x.jpg', 'image/jpeg', JPEG), 'thumbnail': ('t.jpg', 'image/jpeg', JPEG)})
    return s, j.get('id', 'x'), f'/api/files/message_media/{j.get("id")}/{j.get("file")}', f'/api/files/message_media/{j.get("id")}/{j.get("thumbnail")}'

I, T, R, G = {}, {}, {}, None
try:
    for k in 'AB':
        s = secrets.token_hex(5); pw = secrets.token_urlsafe(18)
        st, j = req('POST', col('users'), None, {'email': f'dryrun_{s}@example.test', 'username': f'dryrun_{s}', 'display_name': 'dryrun', 'friend_code': secrets.token_hex(3).upper(), 'password': pw, 'passwordConfirm': pw})
        assert st == 200, ('sign-up', st, j)
        I[k] = j['id']
        st, j = req('POST', '/api/collections/users/auth-with-password', None, {'identity': f'dryrun_{s}', 'password': pw})
        assert st == 200, ('sign-in', st)
        T[k] = j['token']
    s, r = new('friend_requests', 'B', {'from_user': I['B'], 'to_user': I['A'], 'status': 'pending'})
    patch('friend_requests', r, 'A', {'status': 'accepted'}); new('friendships', 'A', {'user_a': I['A'], 'user_b': I['B']})
    s, G = new('conversations', 'A', {'type': 'group', 'name': 'dryrun', 'created_by': I['A']})
    new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['A'], 'role': 'admin'})
    s2, _ = new('conversation_members', 'A', {'conversation_id': G, 'user_id': I['B'], 'role': 'member'})
    def msg(who, typ='text', **kw): return new('messages', who, {'conversation_id': G, 'sender_id': I[who], 'type': typ, 'encrypted_body': 'eA==', 'iv': 'aXY=', **kw})[1]
    mTxt, mImg, mLive = msg('B'), msg('B', 'image'), msg('B', 'image')
    mRep = msg('B', reply_to_id=mTxt, reply_preview='cHJldg==')
    _, xImg, fImg, tImg = media(mImg)
    _, xLive, fLive, tLive = media(mLive)
    R['setup'] = f'B joins group {s2}; A lists mImg media {mcount(mImg)}; mImg file {file_status(fImg)} thumb {file_status(tImg)} (want 200, 1, 200, 200)'
    R['D1'] = f'B deletes the photo mImg for everyone: {patch("messages", mImg, "B", {"is_deleted_for_everyone": True})} (want 200)'
    R['D2'] = f'B deletes the text mTxt for everyone: {patch("messages", mTxt, "B", {"is_deleted_for_everyone": True})} (want 200)'
    time.sleep(0.5)
    R['D3'] = f'A lists mImg media: {mcount(mImg)}; views it: {get("message_media", xImg, "A")[0]} (want 0, 404)'
    R['D4'] = f'mImg file by URL: {file_status(fImg)}; thumb: {file_status(tImg)} (want 404, 404)'
    j1, j2, j3 = get('messages', mImg, 'A')[1], get('messages', mTxt, 'A')[1], get('messages', mRep, 'A')[1]
    R['D5'] = f'A reads mImg body={j1.get("encrypted_body")!r} iv={j1.get("iv")!r} flag={j1.get("is_deleted_for_everyone")}; mTxt body={j2.get("encrypted_body")!r}; reply preview={j3.get("reply_preview")!r} body={j3.get("encrypted_body")!r} (want blanks, reply body kept)'
    R['D6'] = f'live mLive: A lists {mcount(mLive)}, views {get("message_media", xLive, "A")[0]}, file {file_status(fLive)}, thumb {file_status(tLive)}, body={get("messages", mLive, "A")[1].get("encrypted_body")!r} (want 1, 200, 200, 200, kept)'
    R['D7'] = f'B retries the delete on mImg: {patch("messages", mImg, "B", {"is_deleted_for_everyone": True})} (want 400)'
    R['D8'] = f'A pins live mLive: {patch("messages", mLive, "A", {"is_pinned": True})}; body after={get("messages", mLive, "A")[1].get("encrypted_body")!r} (want 200, kept)'
    s, xLate, fLate, _ = media(mImg)
    R['D10'] = f'B uploads media to deleted mImg afterwards: {s}; A lists {mcount(mImg)} (want 400, 0)'
finally:
    # Delete B (the sender) first: that cascades B's messages and their media, so the chat can go.
    if 'B' in I: R[f'del user B {I["B"]}'] = req('DELETE', f'{col("users")}/{I["B"]}', T.get('B'))[0]
    if G: R[f'del chat {G}'] = req('DELETE', f'{col("conversations")}/{G}', T['A'])[0]
    if 'A' in I: R[f'del user A {I["A"]}'] = req('DELETE', f'{col("users")}/{I["A"]}', T.get('A'))[0]
    for k, v in R.items(): print(f'{k:6} {v}')
