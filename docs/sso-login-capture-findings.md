# School login capture source findings

Inspected 2026-09-29 using read-only public GETs (no credentials or login requests).

## Public sources

- `https://ccsys1.niu.edu.tw/SSO/login` is an Angular shell with `<app-root>`.
- `https://ccsys1.niu.edu.tw/SSO/main.d2bd6ea9933e00bf.js` maps the login route to lazy `LoginComponent`, module 3460, chunk 460.
- `https://ccsys1.niu.edu.tw/SSO/runtime.c6e6cb0e13fc936c.js` maps chunk 460 to `9af1b342e1d754d8`.
- `https://ccsys1.niu.edu.tw/SSO/460.9af1b342e1d754d8.js`
  SHA-256: `9524520b90a2651176c842edaf115610fcfe3836f41d8dcea8bab92ba0361aa8`.

Relevant compiled source excerpts:

```js
c.j41(0,"form",29),c.bIt("ngSubmit",function(){ ... return i.Njj(a.onLocalLogin()) })
["type","text","id","username","formControlName","username", ...]
c.Y8G("type",l.showPassword()?"text":"password")
["type","submit",1,"btn","btn-primary","btn-login","w-100",3,"disabled"]
c.Y8G("disabled",l.isLoading()||l.loginForm.invalid||!l.turnstileToken())
```

`onLocalLogin()` validates username, Turnstile token, and form validity before calling
`authService.login(username,password,turnstileToken)`. The main bundle's service
POSTs `{ACNT, Password, TurnstileToken}` to its `/Login` API and stores the resulting
`niu_sso_token`. Password login therefore does use native form submission through
Angular `ngSubmit`; FIDO2 separately uses `keydown.enter` and a click handler.

## iOS comparison

`Features/Authentication/Services/SSOLoginWebView.swift`, `fillModernLoginForm`,
uses `#username`, `#password`, `form.login-form`, and
`form.login-form button[type="submit"]` (approximately lines 507–510).
Its disabled-button check also waits for the school's verification. Flutter now
uses those exact field identities, including when password visibility is enabled.

## Sign-in behavior (matches iOS)

The app no longer captures credentials typed on the school page. The native
login form supplies them, and `schoolLoginFillScript`
(`mobile/lib/features/authentication/school_login_scripts.dart`) mirrors iOS
`fillModernLoginForm`: it sets `#username` and `#password` through the native value
setter with input/change events, then returns `waiting_verification` while the
school keeps the 登入 button disabled (`!turnstileToken()`), and presses it once when
enabled. It never touches Turnstile. `schoolLoginStateScript` mirrors iOS
`checkModernLoginState`: it reports `niu_sso_token` or a visible SweetAlert
error/warning (loading and success popups are ignored).

`mobile/test/fixtures/sso_login.html` reconstructs the relevant public template
with synthetic values, without loading school code or submitting requests.

This validates template compatibility, not a real authenticated SSO. Live device
verification remains required.

## Reproduce DOM checks without an app build

```sh
npm install --prefix /tmp/opencode/sso-dom-check --no-audit --no-fund jsdom
cd mobile
dart test/fixtures/emit_login_fill_script.dart | NODE_PATH=/tmp/opencode/sso-dom-check/node_modules node test/sso_login_fill_dom.cjs
```

The harness checks field filling and events, waiting on the disabled button, a
single press once enabled, a hostile password value, and the origin restriction.
