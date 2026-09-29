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

## Capture behavior and fixture

`mobile/test/fixtures/sso_login.html` reconstructs the relevant public template
with synthetic values, without loading school code or submitting requests.
The production script observes trusted submit, login-button click (including
nested icon/text), and non-composing Enter on the two credential fields. The
click-only button variant is also supported. It ignores disabled login buttons,
password visibility toggles, certificate PIN/FIDO2 controls, synthetic events,
foreign origins, frames, and other SSO routes. It never enables controls, changes
Turnstile, calls submit/click, or prevents the school's event handling.

Click plus submit may both deliver the same credentials; the native handler only
replaces transient data, while verified SSO and the single-flight Moodle service
gate actual authentication. No credentials are retained in a JS deduplication cache.

This validates public template/event compatibility, not a real authenticated SSO,
Moodle session, or attendance result. Live device verification remains required.

## Reproduce DOM checks without an app build

The standalone Node harness uses jsdom installed outside the repository (no
pubspec or app dependency changes):

```sh
npm install --prefix /tmp/opencode/sso-dom-check --no-audit --no-fund jsdom
cd mobile
dart test/fixtures/emit_capture_script.dart | NODE_PATH=/tmp/opencode/sso-dom-check/node_modules node test/sso_login_capture_dom.cjs
```

The emitter runs the actual Dart script generator. The harness executes that JS
against the HTML fixture and verifies disabled-button handling, nested login
clicks, submit, Enter, password visibility, click-only buttons, exact payload,
unrelated controls, origin/path restrictions, and synthetic-event rejection.
jsdom cannot produce browser-trusted events, so positive cases invoke the
registered handler with simulated trusted metadata and real DOM elements.
This limitation is explicit; no real-user browser-event test is claimed.
