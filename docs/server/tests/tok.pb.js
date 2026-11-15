routerAdd("GET", "/tok/{id}", (e) => {
  const r = $app.findRecordById("users", e.request.pathValue("id"));
  return e.json(200, { token: r.newAuthToken() });
});
