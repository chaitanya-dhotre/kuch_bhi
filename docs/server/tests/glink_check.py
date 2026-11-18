"""google-link-and-push.md dry-run checks, against a DB copy on 127.0.0.1:<port>. Throwaway users only.
Prints PASS/FAIL per check; never prints a token, password or tokenKey."""
import json, secrets, sqlite3, sys, time, urllib.request, urllib.error

PORT, DB = sys.argv[1], sys.argv[2]
B = f'http://127.0.0.1:{PORT}'


def req(m, path, body=None, tok=None):
    for _ in range(4):  # PocketBase's default auth rate limit answers 429 to quick sign-ins
        st, j = _req(m, path, body, tok)
        if st != 429:
            return st, j
        time.sleep(3)
    return st, j


def _req(m, path, body=None, tok=None):
    r = urllib.request.Request(B + path, method=m, data=json.dumps(body).encode() if body is not None else None,
                               headers={'Content-Type': 'application/json', **({'Authorization': tok} if tok else {})})
    try:
        with urllib.request.urlopen(r, timeout=20) as f:
            return f.status, json.loads(f.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')


def q(sql, *a):
    return sqlite3.connect(f'file:{DB}?mode=ro', uri=True).execute(sql, a).fetchone()


def signup(verified=False):
    s = secrets.token_hex(5)
    em, pw = f'dryrun_{s}@example.test', secrets.token_urlsafe(16)
    st, j = req('POST', '/api/collections/users/records', {'email': em, 'password': pw, 'passwordConfirm': pw,
                'username': f'dryrun_{s}', 'display_name': 'dryrun', 'friend_code': s[:6].upper()})
    assert st == 200, (st, j)
    _, a = req('POST', '/api/collections/users/auth-with-password', {'identity': em, 'password': pw})
    return j['id'], em, pw, a.get('token')


def gauth(em, action='signin', **kw):
    return req('POST', '/api/hooks/google-auth', {'idToken': f'h.{em.encode().hex()}.s', 'action': action, **kw})


R = {}
# F23: unverified password account, then Google sign-in for the same email
uid, em, pw, old = signup()
R['setup: sign-up is unverified'] = q('select verified from users where id=?', uid)[0] == 0
st, j = gauth(em)
R['F23 google sign-in 200'] = st == 200
R['F23 verified now 1'] = q('select verified from users where id=?', uid)[0] == 1
R['F23 old session refused'] = req('POST', '/api/collections/users/auth-refresh', {}, old)[0] == 401
R['F23 new session works'] = req('POST', '/api/collections/users/auth-refresh', {}, j.get('token'))[0] == 200
R['F23 old password fails'] = req('POST', '/api/collections/users/auth-with-password', {'identity': em, 'password': pw})[0] == 400
# verified account: Google sign-in changes nothing
_, j2 = gauth(em)
k1 = q('select tokenKey, password from users where id=?', uid)
_, j3 = gauth(em)
R['verified: tokenKey+password unchanged'] = q('select tokenKey, password from users where id=?', uid) == k1
R['verified: earlier session still works'] = req('POST', '/api/collections/users/auth-refresh', {}, j2.get('token'))[0] == 200
# F24: Google register gives a private email
s = secrets.token_hex(5)
st, j = gauth(f'dryrun_{s}@example.test', 'register', username=f'dryrun_{s}', display_name='dryrun')
R['F24 register 200'] = st == 200
R['F24 emailVisibility 0'] = q('select emailVisibility from users where id=?', j.get('record', {}).get('id'))[0] == 0
_, _, _, other = signup()
_, v = req('GET', f'/api/collections/users/records/{j["record"]["id"]}', tok=other)
R['F24 other user sees no email'] = not v.get('email')
# F25: B saves A's push token
a, _, _, ta = signup()
b, _, _, tb = signup()
T = 'dryrun-push-' + secrets.token_hex(8)
print('F25 sessions present:', bool(ta), bool(tb))
print('F25 A patch status:', req('PATCH', f'/api/collections/users/records/{a}', {'fcm_token': T}, ta)[0])
R['F25 A holds token'] = q('select fcm_token from users where id=?', a)[0] == T
req('PATCH', f'/api/collections/users/records/{b}', {'fcm_token': T}, tb)
R['F25 A cleared'] = q('select fcm_token from users where id=?', a)[0] == ''
R['F25 B holds token'] = q('select fcm_token from users where id=?', b)[0] == T
req('PATCH', f'/api/collections/users/records/{b}', {'display_name': 'dryrun2'}, tb)
R['F25 B keeps token on other updates'] = q('select fcm_token from users where id=?', b)[0] == T
for k, ok in R.items():
    print(('PASS ' if ok else 'FAIL ') + k)
print('ALL PASS' if all(R.values()) else 'SOME FAIL')
