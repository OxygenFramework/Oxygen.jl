import React from "react";
import ReactDOM from "react-dom";
import { HashRouter, Route, Switch, Redirect } from "react-router-dom";

import AdminLayout from "layouts/Admin.js";
import AuthLayout from "layouts/Auth.js";

ReactDOM.render(
  <HashRouter>
    <Switch>
      <Route path={`/admin`} component={AdminLayout} />
      {/* <Route path={`/auth`} component={AuthLayout} /> */}
      <Redirect from={`/`} to="/admin/dashboard" />
    </Switch>
  </HashRouter>,
  document.getElementById("root")
);
