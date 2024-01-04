import React from "react";
import ReactDOM from "react-dom";
import { HashRouter, Route, Switch, Redirect } from "react-router-dom";

import AuthLayout from "layouts/Auth.js";
import AdminLayout from "layouts/Admin.js";
import RTLLayout from "layouts/RTL.js";

ReactDOM.render(
  <HashRouter>
    <Switch>
      <Route path={`/admin`} component={AdminLayout} />
      {/* <Route path={`/auth`} component={AuthLayout} /> */}
      {/* <Route path={`/rtl`} component={RTLLayout} /> */}
      <Redirect from={`/`} to="/admin/dashboard" />
    </Switch>
  </HashRouter>,
  document.getElementById("root")
);
