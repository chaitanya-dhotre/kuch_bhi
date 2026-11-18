// TEST COPIES ONLY, never the live hooks folder. Stands in for Google's tokeninfo in the
// google-link-and-push.md dry run: the "idToken" is h.<hex email>.s, and the answer says that
// email is verified. The dry-run copy of google_auth.pb.js is pointed here by sed.
routerAdd("GET", "/stub-tokeninfo", (e) => {
  const h = String(e.request.url.query().get("id_token")).split(".")[1];
  let em = "";
  for (let i = 0; i < h.length; i += 2) em += String.fromCharCode(parseInt(h.substr(i, 2), 16));
  return e.json(200, {
    aud: "704442380980-34iv6mgvuuc70v9gld5ekvs31jii9tvb.apps.googleusercontent.com",
    iss: "accounts.google.com", email_verified: "true", email: em, sub: "dryrun",
    exp: String(Math.floor(Date.now() / 1000) + 600),
  });
});
