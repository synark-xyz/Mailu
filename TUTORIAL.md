# Mailu tutorial: accounts, aliases, extra mail domains, sending and receiving

Assumes `./deploy.sh --local` is running (from `deploy/`). Replace `--local` with `--prod` on the server.
Local admin: http://localhost/admin · webmail: http://localhost/webmail

Terms in Mailu: a **domain** is something you receive mail for (`getserviceflow.app`). A **user** is a real mailbox with a password. An **alias** forwards an address to one or more other addresses and has no mailbox of its own. These are your "sub-mail services" (see Part 3).

---

## Part 1: Create accounts

### In the web UI
1. Log in at `/admin` with `admin@getserviceflow.app` (the password is in `deploy/.local/admin-credentials.txt`; `deploy.sh` doesn't print it).
2. Sidebar: **Mail domains** → on the `getserviceflow.app` row, click the **✉ envelope** icon (tooltip "Users") → **Add user**.
3. Fill in: *Email* (`alice`), *Password*, *Quota* (e.g. 1 GB), leave *Enabled* on. **Save**.
4. Repeat for `bob`.

### From the command line
```bash
cd deploy
./deploy.sh --local cli user alice getserviceflow.app 'alice-pw'
./deploy.sh --local cli user bob   getserviceflow.app 'bob-pw'
# change a password / create-or-update:
./deploy.sh --local cli user alice getserviceflow.app 'new-pw' --mode update
./deploy.sh --local cli user-delete alice@getserviceflow.app --really
```

### Roles
- `admin@getserviceflow.app` can manage everything. Make another global admin: edit the user in the UI and tick **Global admin**.
- Each user can log in to `/admin` to change their own password, set a forwarding address, vacation auto-reply, spam threshold and **auth tokens**.

---

## Part 2: Send and receive (local test)

### A. Using webmail (easiest)
1. Open http://localhost/webmail in one browser window, log in as `alice@getserviceflow.app`.
2. Open a second private window, log in as `bob@getserviceflow.app`.
3. From alice, compose to `bob@getserviceflow.app` and send. It appears in bob's inbox within seconds.
4. Reply from bob and check alice receives it.

### B. Using the test script
```bash
cd deploy
# Simulate mail arriving from the outside world (SMTP :25) and verify with IMAP:
./test-mail.py --to alice@getserviceflow.app --password 'alice-pw'

# Authenticated send as bob (SMTP :587), verify it reached alice:
./test-mail.py --from bob@getserviceflow.app --from-password 'bob-pw' \
               --to alice@getserviceflow.app --password 'alice-pw'
```
It prints `OK: message arrived in INBOX`, or tells you which logs to check.

### C. Using a mail client (Thunderbird, Apple Mail, etc.)
Local (no TLS) settings, for testing only:

| | Value |
|---|---|
| Server | `localhost` |
| IMAP | port `143`, no encryption |
| SMTP | port `587`, no encryption, authentication: normal password |
| Username | full address, e.g. `alice@getserviceflow.app` |

Clients may refuse plaintext passwords. If so, use webmail locally. In production you use TLS: IMAP `993` (SSL/TLS), SMTP `465` (SSL/TLS) or `587` (STARTTLS).

### What does and doesn't work locally
- Works: local to local mail, webmail, IMAP/SMTP clients, aliases, spam filtering.
- Doesn't work: mail from/to Gmail and the internet. You have no public IP, MX record, PTR record or open port 25 on your Mac. Sending to Gmail locally will queue and bounce. This is expected. Real internet mail is tested after `--prod` (see `INSTRUCTIONS.md`).
- Look at the queue and logs: `./deploy.sh --local logs smtp front imap`

---

## Part 3: "Sub-mail services": aliases, shared inboxes, extra domains

### 3.1 Alias: `support@` forwards to people (no extra mailbox)
UI: **Mail domains** → on the `getserviceflow.app` row click the **@** icon (tooltip "Aliases"; there is no text button) → **Add alias**: *Email* `support`, *Destination* `alice@getserviceflow.app, bob@getserviceflow.app`.
CLI:
```bash
./deploy.sh --local cli alias support getserviceflow.app 'alice@getserviceflow.app,bob@getserviceflow.app'
./deploy.sh --local cli alias-delete support@getserviceflow.app
```
Mail to `support@` now reaches both. Good for `info@`, `sales@`, `billing@`, `abuse@`, `postmaster@`.

To **reply as** `support@`, use a real user instead (3.2).

### 3.2 Dedicated mailbox per service
Create a normal user for each function: `sales`, `billing`, `noreply`, `notifications`.
```bash
./deploy.sh --local cli user noreply getserviceflow.app 'long-random-secret'
```
Give a team member access by also forwarding it: set the **Forward** field on that user, or have them log in as that user.

### 3.3 Catch-all
Wildcard alias that receives anything not matching another address:
```bash
./deploy.sh --local cli alias '%' getserviceflow.app 'alice@getserviceflow.app' -w
```
Use sparingly. It attracts spam.

### 3.4 Plus-addressing (free sub-addresses)
`alice+newsletters@getserviceflow.app` is delivered to `alice@getserviceflow.app` automatically (delimiter `+`, set by `RECIPIENT_DELIMITER`). Handy for filtering by sender or service.

### 3.5 Another domain or subdomain as its own mail service
For example `app.getserviceflow.app` or a second brand domain:
1. UI: **Mail domains** → **New domain** → enter the name. Optionally set limits for users, aliases and quota. (CLI: `./deploy.sh --local cli domain app.getserviceflow.app`)
2. Add users and aliases under that domain as above.
3. Production: that domain needs its own DNS: MX `10 mail.getserviceflow.app.`, SPF `v=spf1 mx ~all`, DMARC, and its own **DKIM** key (domain's **Details/DNS** page shows the exact records).
4. **Alternative domain** (same mailboxes answer at a second name, e.g. `alice@getserviceflow.com` also reaches `alice@getserviceflow.app`): on the domain's page choose the **✱ asterisk** icon ("Alternatives", global admin only) → add it, with the same DNS records.

### 3.6 Let your apps send mail (transactional, "sub-service" for software)
Create a mailbox such as `noreply@getserviceflow.app` and use it as SMTP credentials in your application:

| Setting | Production value |
|---|---|
| Host | `mail.getserviceflow.app` |
| Port / security | `587` STARTTLS (or `465` SSL) |
| Username / password | `noreply@getserviceflow.app` / its password |
| From | `noreply@getserviceflow.app` |

Local testing against your dev app: host `localhost`, port `587`, no TLS.
Safer than the real password: in the user's page under **Authentication tokens**, create a token and use that as the SMTP password. It can be revoked without changing the account password.

### 3.7 Send an outbound-only service through another provider
If your hosting blocks port 25, put a relay (SES, Mailgun, SMTP2GO) in front: set `RELAYHOST=[smtp.provider.com]:587` in `mailu.env` and add credentials as your provider documents. Mailu docs: https://mailu.io/master/configuration.html (Relayhost). Then `./deploy.sh --prod down && ./deploy.sh --prod up`.

---

## Part 4: Day-to-day operations

```bash
./deploy.sh --local status          # container health
./deploy.sh --local logs smtp       # follow one service
./deploy.sh --local down            # stop (data kept)
./deploy.sh --local up              # start again
./deploy.sh --local reset -y        # wipe all local data and start fresh
```
Spam: messages above the user's spam threshold go to the Junk folder. Adjust it per user in the user's own settings.
Quota: edit the user in the admin UI.
Export your whole config (domains, users, aliases) as YAML: `./deploy.sh --local cli config-export --secrets` (treat the output as sensitive).

## Part 5: Troubleshooting

| Problem | What to check |
|---|---|
| Can't log in to webmail | Use the full address as username. Check the user is *Enabled*. |
| `test-mail.py` says message not found | `./deploy.sh --local logs smtp imap`. Look for `reject`, `Relay access denied` (domain not created) or `User unknown`. |
| "Relay access denied" | The recipient's domain isn't added under **Mail domains**. |
| Client refuses plaintext login locally | Use webmail locally, or test the TLS setup in production. |
| Mail sits in queue to Gmail locally | Expected: no internet-facing mail locally. |
| Port conflicts on startup | Add `PORT_HTTP=8080` (etc.) to `deploy/.local/.env`. The webmail/admin URL then includes `:8080`. |

## Part 6: Moving to production
Follow `INSTRUCTIONS.md`. After install, repeat Part 1 and Part 3 on the real server, and complete DNS, DKIM and the deliverability tests.
