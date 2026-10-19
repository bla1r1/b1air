# Signing in to Google and Microsoft calendars

Settings → Notifications → During meetings adds calendars the way a mail app
adds an account. iCloud and CalDAV take an app-specific password; Google and
Microsoft can be signed in to on their own page, in the browser — once the
suite is registered with them as an app. Without that, their tiles add a
calendar by its private link instead, step by step, and everything else
works the same.

Registering gives three values. They are not secrets: a desktop app cannot
keep one, and every copy carries them. Build with them:

```sh
cmake -S src -B build \
  -DB1AIR_GOOGLE_CLIENT_ID=…apps.googleusercontent.com \
  -DB1AIR_GOOGLE_CLIENT_SECRET=GOCSPX-… \
  -DB1AIR_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
```

or put the same names in the session's environment, where they override
what the build has. `b1air-daemon calendar-account providers` says which of
the two sign-ins a build has.

Only reading calendars is asked for. What a sign-in leaves behind is a
refresh token in the secret store (`calendar-<md5 of the account>`), never a
password; removing the account in Settings deletes it.

## Google

1. [Google Cloud Console](https://console.cloud.google.com/) → a new project.
2. APIs & Services → Library → **Google Calendar API** → Enable.
3. APIs & Services → OAuth consent screen (Google Auth Platform):
   - User type **External**; app name `b1air`, a support address.
   - Data access → add the scopes `openid`, `email` and
     `https://www.googleapis.com/auth/calendar.readonly`.
   - Audience → while the app is in **Testing**, add the Google accounts
     that may sign in (up to 100).
4. Clients → Create client → Application type **Desktop app**. Its client
   ID and client secret are the two values above.

In Testing, Google shows "Google hasn't verified this app" on the way in
(Continue goes on) and a sign-in lasts seven days before it has to be
done again. `calendar.readonly` is a sensitive scope: for anyone to sign in,
without the warning and without the seven days, the app has to be published
and go through Google's verification (a privacy policy, a home page, a
short video of the sign-in), which takes some weeks.

Loopback redirects (`http://127.0.0.1:<port>`) need no setting for a
desktop client.

## Microsoft (Outlook.com, Microsoft 365)

1. [Microsoft Entra admin center](https://entra.microsoft.com/) → App
   registrations → New registration.
   - Name `b1air`.
   - Supported account types: **Accounts in any organizational directory
     and personal Microsoft accounts**.
   - Redirect URI: platform **Public client/native (mobile & desktop)**,
     `http://localhost`.
2. Authentication → Advanced settings → **Allow public client flows: Yes**.
3. API permissions → Microsoft Graph → Delegated → `Calendars.Read`,
   `User.Read`, `offline_access`. No admin consent is needed for these.
4. The Application (client) ID on the Overview page is the value above.
   Microsoft public clients have no secret.

Until the publisher is verified (Microsoft Partner Network), the consent page
says the app is unverified; signing in still works. A work or school tenant
may require its admin to approve the app.

## How it works

`b1air-daemon calendar-account signin google|microsoft` opens the provider's
sign-in page with a PKCE challenge, waits up to five minutes for the browser
to come back to a port on 127.0.0.1 with a code, exchanges the code for a
refresh token and lists the account's calendars. Reading them afterwards
(`b1air-daemon calendar google:<address>…`) trades the refresh token for a
short-lived access token each time, at most every fifteen minutes. Google's
and Microsoft's servers expand recurring events themselves; a declined
meeting and one shown as free do not count as busy.
