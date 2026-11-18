routerAdd("POST","/api/hooks/google-auth",function(c){
  function fc6(){var c="";for(var i=0;i<6;i++)c+="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[Math.floor(Math.random()*36)];return c;}
  // OAuth client ids from android/app/google-services.json (type 3 = web client = the idToken aud)
  var AUDS=["704442380980-34iv6mgvuuc70v9gld5ekvs31jii9tvb.apps.googleusercontent.com","704442380980-gm27v8qsprtvfnd0ab0880qarespiltc.apps.googleusercontent.com"];
  try{
    var raw=toString(c.request.body);
    if(!raw||raw.length<2) return c.json(400,{code:400,message:"no body"});
    var p=JSON.parse(raw),tok=p.idToken,action=p.action||"signin";
    if(!tok||tok.length<20) return c.json(400,{code:400,message:"idToken short"});
    if(tok.split(".").length!==3) return c.json(401,{code:401,message:"malformed JWT"});
    // Google checks the signature; we never trust a payload we decoded ourselves.
    var res;
    try{
      res=$http.send({url:"https://oauth2.googleapis.com/tokeninfo?id_token="+encodeURIComponent(tok),method:"GET",timeout:10});
    }catch(eh){console.log("[GAuth] tokeninfo unreachable:",String(eh));return c.json(503,{code:503,message:"Google verification unavailable"});}
    if(res.statusCode!==200) return c.json(401,{code:401,message:"invalid token"});
    var pay=res.json||{};
    if(AUDS.indexOf(String(pay.aud))<0) return c.json(401,{code:401,message:"aud mismatch"});
    if(pay.iss!=="accounts.google.com"&&pay.iss!=="https://accounts.google.com") return c.json(401,{code:401,message:"iss mismatch"});
    if(String(pay.email_verified)!=="true") return c.json(401,{code:401,message:"email not verified"});
    if(!pay.exp||Number(pay.exp)*1000<Date.now()) return c.json(401,{code:401,message:"expired"});
    var em=String(pay.email||"");if(!em||em.indexOf("@")<0) return c.json(400,{code:400,message:"email required"});
    var sub=String(pay.sub||"");
    var rec=null,isNew=false;
    try{rec=$app.findAuthRecordByEmail("users",em);}catch(e){}
    if(action==="register"){
      // Registration: fail if user already exists
      if(rec) return c.json(409,{code:409,message:"User already exists"});
      // Create new user with provided display_name and username
      var dn=String(p.display_name||pay.name||pay.email||"User");
      var un=String(p.username||em.split("@")[0]).replace(/[^a-zA-Z0-9_]/g,"_").toLowerCase();
      if(un.length<3) un=un.padEnd(3,"0");
      var taken=false;
      try{$app.findFirstRecordByFilter("users","username={:u}",{u:un});taken=true;}catch(e2){}
      if(taken) return c.json(400,{code:400,message:"Username is taken.",data:{username:{code:"validation_not_unique",message:"Username is taken."}}});
      var fc="";
      for(var a=0;a<50;a++){var fc=fc6();try{$app.findFirstRecordByFilter("users",'friend_code="'+fc+'"');}catch(e2){break;}}
      if(!fc||fc.length!==6) fc="G"+(sub||"OOO").slice(0,5).toUpperCase();
      var cl=$app.findCollectionByNameOrId("users");
      rec=new Record(cl,{email:em,emailVisibility:false,username:un,display_name:dn,friend_code:fc,verified:true});
      rec.set("password",fc6()+fc6()+fc6()+fc6());
      rec.set("passwordConfirm",rec.get("password"));
      $app.save(rec);
      isNew=true;
    }else{
      // signin: must already exist
      if(!rec) return c.json(404,{code:404,message:"User not found"});
      // F23 (google-link-and-push.md D-1): Google proves this email. An unverified account may have
      // been pre-claimed by a stranger, so drop their password and every other session.
      if(!rec.verified()){
        rec.setVerified(true);
        rec.setRandomPassword();
        rec.refreshTokenKey();
        console.log("[GAuth] unverified account taken over by Google owner:",rec.id);
      }
    }
    // Generate token from the record's own method
    var token=rec.newAuthToken();
    var cl=$app.findCollectionByNameOrId("users");
    var rd={id:rec.id,created:rec.created,updated:rec.updated,collectionId:cl.id,collectionName:"users"};
    ["email","username","display_name","friend_code","avatar","about","is_online","last_seen","typing_in","current_chat","public_key","private_key_encrypted","private_key_salt","verified","emailVisibility"].forEach(function(f){try{rd[f]=rec.get(f);}catch(e){}});
    console.log("[GAuth] OK:",em,isNew?"(new)":"(existing)");
    $app.save(rec);
    return c.json(200,{token:token,record:rd,isNew:isNew});
  }catch(e){console.log("[GAuth] error:",String(e));
    return c.json(500,{code:500,message:"GAuth: "+String(e)});
  }
});
