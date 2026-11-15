import json,sys,sqlite3,time,urllib.request,urllib.error,threading,uuid
port=sys.argv[1]; db=sqlite3.connect(sys.argv[2]); B_='http://127.0.0.1:'+port
def q(s,*a): return db.execute(s,a).fetchall()
def req(m,p,tok=None,body=None,raw=None,ct='application/json'):
    d=raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    r=urllib.request.Request(B_+p,data=d,method=m,headers={'Content-Type':ct,**({'Authorization':tok} if tok else {})})
    try:
        with urllib.request.urlopen(r,timeout=20) as x: t=x.read(); return x.status,(json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t=e.read()
        try: return e.code,json.loads(t)
        except Exception: return e.code,{}
def lst(col,tok,flt=''):
    from urllib.parse import quote
    s,j=req('GET',f'/api/collections/{col}/records?perPage=500&filter={quote(flt)}',tok); return s,j.get('totalItems',-1),j.get('items',[])
# pick A (admin of g), B (member of g, shares DM d with A, sent in both), C (in neither)
pick=None
for g,a in q("select m.conversation_id,m.user_id from conversation_members m join conversations c on c.id=m.conversation_id where c.type='group' and m.role='admin'"):
    for (b,) in q("select user_id from conversation_members where conversation_id=? and user_id!=?",g,a):
        d=q("select c.id from conversations c where c.type='direct' and exists(select 1 from conversation_members where conversation_id=c.id and user_id=?) and exists(select 1 from conversation_members where conversation_id=c.id and user_id=?)",a,b)
        if d and q("select 1 from messages where conversation_id=? and sender_id=? limit 1",d[0][0],b) and q("select 1 from messages where conversation_id=? and sender_id=? limit 1",g,b):
            pick=(g,a,b,d[0][0]); break
    if pick: break
assert pick,'no A/B pair'
g,A,Bu,d=pick
cs=q("select u.id,(select count(*) from conversation_members where user_id=u.id),(select count(*) from messages where sender_id=u.id) from users u where u.id not in (select user_id from conversation_members where conversation_id in (?,?)) order by 3 desc,2 desc",g,d)
assert cs,'no C'; C=cs[0][0]
T={k:req('GET','/tok/'+v)[1]['token'] for k,v in (('A',A),('B',Bu),('C',C))}
Fg='conversation_id="%s"'%g; Fd='conversation_id="%s"'%d; FuB='user_id="%s"'%Bu; FdB=Fd+' && recipient_id!="%s"'%Bu
Fm4=lambda: 'message_id="%s"'%ms[4]
R={}; R['setup']=f'C memberships={cs[0][1]} C sent={cs[0][2]} total_convs={q("select count(*) from conversations")[0][0]}'
s,n,it=lst('conversations',T['C']); R['T1']=f'C lists conversations: {n} rows, sees group g: {any(i["id"]==g for i in it)}'
s,n,_=lst('conversations',T['A']); R['T2']=f'A lists {n} (member of {q("select count(distinct conversation_id) from conversation_members where user_id=?",A)[0][0]}); A getOne g: {req("GET","/api/collections/conversations/records/"+g,T["A"])[0]}'
nm=q("select name from conversations where id=?",g)[0][0]
R['T3']=f'C renames g: {req("PATCH","/api/collections/conversations/records/"+g,T["C"],{"name":nm})[0]}'
dd=q("select coalesce(disappearing_duration,0) from conversations where id=?",g)[0][0]
R['T4']=f'B sets timer: {req("PATCH","/api/collections/conversations/records/"+g,T["B"],{"disappearing_duration":dd})[0]}; B sets created_by: {req("PATCH","/api/collections/conversations/records/"+g,T["B"],{"created_by":Bu})[0]}'
R['T5']=f'C lists members of g: {lst("conversation_members",T["C"],Fg)[1]} (real {q("select count(*) from conversation_members where conversation_id=?",g)[0][0]})'
sh=q("select count(*) from conversation_members x where user_id=? and exists(select 1 from conversation_members where conversation_id=x.conversation_id and user_id=?)",Bu,A)[0][0]
R['T6']=f'A lists members user_id=B: {lst("conversation_members",T["A"],FuB)[1]} (B total {q("select count(*) from conversation_members where user_id=?",Bu)[0][0]}, shared with A {sh})'
R['T7']=f'C lists receipts of d: {lst("message_receipts",T["C"],Fd)[1]} (real {q("select count(*) from message_receipts where conversation_id=?",d)[0][0]})'
s,n,it=lst('message_receipts',T['B'],f'conversation_id="{d}" && recipient_id!="{Bu}"')
snd=dict(q("select id,sender_id from messages where conversation_id=?",d)); R['T8']=f'B lists receipts (not own) of d: {n}; on messages B did not send: {sum(1 for i in it if snd.get(i["message_id"]) not in (Bu,None))}; message row gone: {sum(1 for i in it if i["message_id"] not in snd)}'
ms=[]
for i in range(5):
    s,j=req('POST','/api/collections/messages/records',T['B'],{'conversation_id':d,'sender_id':Bu,'type':'text','encrypted_body':'dryrun','iv':'dryrun'}); ms.append(j.get('id')); 
R['msgs']=f'B creates 5 test messages: {s}'
now='2026-11-15 12:00:00.000Z'
rc=lambda tok,m,r,**k: req('POST','/api/collections/message_receipts/records',tok,{'message_id':m,'conversation_id':d,'recipient_id':r,**k})
R['T9']=f'C forges read receipt as A: {rc(T["C"],ms[0],A,delivered_at=now,read_at=now)[0]}'
R['T10']=f'B (sender) empty receipt for A: {rc(T["B"],ms[1],A)[0]}; B pre-read receipt for A: {rc(T["B"],ms[2],A,read_at=now)[0]}'
s,j=rc(T['A'],ms[3],A,delivered_at=now); rid=j.get('id','x')
R['T11']=f'A own delivered receipt: {s}; A sets read_at: {req("PATCH","/api/collections/message_receipts/records/"+rid,T["A"],{"read_at":now})[0]}; A re-points message_id: {req("PATCH","/api/collections/message_receipts/records/"+rid,T["A"],{"message_id":"aaaaaaaaaaaaaaa"})[0]}'
s2,j2=rc(T['B'],ms[4],A); R['T11b']=f'A updates the placeholder B made: {req("PATCH","/api/collections/message_receipts/records/"+j2.get("id","x"),T["A"],{"delivered_at":now,"read_at":now})[0]}; B then lists it: {lst("message_receipts",T["B"],Fm4())[1]}'
def media(tok,m):
    b=uuid.uuid4().hex; parts=[]
    for k,v in (('message_id',m),('conversation_id',d),('media_type','image'),('file_name','x.bin'),('expires_at','2027-01-01 00:00:00.000Z')): parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="x.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()+b'abc'+f'\r\n--{b}--\r\n'.encode())
    return req('POST','/api/collections/message_media/records',tok,raw=b''.join(parts),ct='multipart/form-data; boundary='+b)[0]
R['T12']=f'C attaches media to B message: {media(T["C"],ms[0])}; B to own: {media(T["B"],ms[1])}'
um=lambda col,tok,u,m: req('POST',f'/api/collections/{col}/records',tok,{'user_id':u,'message_id':m,'conversation_id':d})[0]
R['T13']=f'C delete-for-me as A: {um("deleted_messages_for_me",T["C"],A,ms[0])}; C star as A: {um("starred_messages",T["C"],A,ms[0])}; A own delete-for-me: {um("deleted_messages_for_me",T["A"],A,ms[1])}; A own star: {um("starred_messages",T["A"],A,ms[1])}'
s,j=req('POST','/api/collections/conversations/records',T['A'],{'type':'group','name':'dryrun','created_by':A}); ng=j.get('id','x')
s1=req('GET','/api/collections/conversations/records/'+ng,T['A'])[0]
s2=req('POST','/api/collections/conversation_members/records',T['A'],{'conversation_id':ng,'user_id':A,'role':'admin'})[0]
s3=req('POST','/api/collections/conversation_members/records',T['A'],{'conversation_id':ng,'user_id':Bu,'role':'member'})[0]
R['T14']=f'A creates group: {s}; reads it before members exist: {s1}; adds self: {s2}; adds B: {s3}; B reads it: {req("GET","/api/collections/conversations/records/"+ng,T["B"])[0]}; C reads it: {req("GET","/api/collections/conversations/records/"+ng,T["C"])[0]}'
s,j=req('POST','/api/collections/group_invites/records',T['A'],{'conversation_id':ng,'invited_user_id':C,'invited_by':A,'status':'pending'}); iv=j.get('id','x')
s1=req('GET','/api/collections/conversations/records/'+ng,T['C'])[0]; s2=req('PATCH','/api/collections/group_invites/records/'+iv,T['C'],{'status':'declined'})[0]
R['T15']=f'A invites C: {s}; C reads group while pending: {s1}; C declines: {s2}; C reads group after: {req("GET","/api/collections/conversations/records/"+ng,T["C"])[0]}'
# realtime
ev={'A':[],'B':[],'C':[]}
def sse(k):
    r=urllib.request.urlopen(urllib.request.Request(B_+'/api/realtime'),timeout=12); cur={}
    try:
        for line in r:
            line=line.decode().strip()
            if line.startswith('event:'): cur['e']=line[6:].strip()
            elif line.startswith('data:'):
                dj=json.loads(line[5:])
                if cur.get('e')=='PB_CONNECT': req('POST','/api/realtime',T[k],{'clientId':dj['clientId'],'subscriptions':['conversations/*','conversation_members/*','message_receipts/*']})
                else: ev[k].append(cur.get('e'))
    except Exception: pass
th=[threading.Thread(target=sse,args=(k,),daemon=True) for k in ev]; [t.start() for t in th]; time.sleep(2.5)
req('PATCH','/api/collections/conversations/records/'+g,T['A'],{'name':nm})
req('PATCH','/api/collections/message_receipts/records/'+rid,T['A'],{'delivered_at':'2026-11-15 12:00:01.000Z'})
req('POST','/api/collections/conversation_members/records',T['A'],{'conversation_id':ng,'user_id':C,'role':'member'}) if False else None
time.sleep(3)
R['T16']='realtime events after A renames g and A updates own receipt on B message: '+', '.join(f'{k}: {sorted(set(v))}' for k,v in ev.items())
def tm(f):
    xs=[]
    for _ in range(7): t=time.time(); f(); xs.append((time.time()-t)*1000)
    return round(sorted(xs)[3])
R['time']=f'members of g as A: {tm(lambda: lst("conversation_members",T["A"],Fg))} ms; receipts of d as B: {tm(lambda: lst("message_receipts",T["B"],FdB))} ms; conversations as A: {tm(lambda: lst("conversations",T["A"]))} ms; messages page as A: {tm(lambda: lst("messages",T["A"],Fd))} ms'
for k,v in R.items(): print(f'{k:6} {v}')
