# Go-live checklist: mail.getserviceflow.app

## Step 0: Try it locally first (OrbStack)

Needs OrbStack running (Docker + Compose). Ports 80, 443, 25, 587, 993 etc. must be free on your Mac.

```bash
git clone -b claude/gifted-sagan-mcbjao https://github.com/synark-xyz/mailu.git
cd mailu/deploy
./deploy.sh --local                  # start; prints admin login
./deploy.sh --local -v --log run.log # verbose + log to file
./deploy.sh --local status | logs [svc] | down | pull
./deploy.sh --local reset -y         # wipe all local data
```
Then open http://localhost/admin and http://localhost/webmail. Create two users and send mail between them.
Local limits: plain HTTP, and no real internet mail (no public DNS, MX or PTR). That is expected.
If a port is taken, add e.g. `PORT_HTTP=8080` to `deploy/.local/.env` and re-run.

Go to the production steps below once the local run works.

Work through these in order. Files referenced live in `deploy/`.

## A. Before you touch the server (about 15 min)

- [ ] **1. Confirm the server can send mail.** You need a VPS or dedicated server with a public static IPv4, Debian/Ubuntu, 2 GB RAM or more, and root/SSH access. Ask your host: *"Is outbound port 25 open on this server?"* If not, request it be unblocked. Without it you can receive mail but not send.
- [ ] **2. Note your server's public IPv4** (call it `SERVER_IP`).
- [ ] **3. Open firewall ports** (host panel firewall and/or `ufw`): 25, 80, 110, 143, 443, 465, 587, 993, 995, 4190.
- [ ] **4. Free those ports.** Stop or remove anything already using them (Apache, nginx, an existing Postfix or Exim). `deploy.sh` aborts if 25, 80, 443, 587 or 993 are taken.

## B. DNS at your domain registrar or DNS host for getserviceflow.app

Add these now. The A record must resolve before install, or the Let's Encrypt certificate will fail.

| Type | Name | Value |
|---|---|---|
| A | `mail` | `SERVER_IP` |
| MX | `@` | `10 mail.getserviceflow.app.` |
| TXT | `@` | `v=spf1 mx ~all` |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; adkim=s; aspf=s; rua=mailto:admin@getserviceflow.app` |
| CNAME | `autoconfig` | `mail.getserviceflow.app.` |
| CNAME | `autodiscover` | `mail.getserviceflow.app.` |

- [ ] **5. Add the records above.**
- [ ] **6. Verify the A record**: `dig +short mail.getserviceflow.app` returns `SERVER_IP`.
- [ ] **7. Set reverse DNS (PTR)** for `SERVER_IP` to `mail.getserviceflow.app`. This is done in your *hosting* panel, not at the registrar. Missing or wrong PTR is the top cause of mail going to spam.

## C. Install on the server (about 10 min)

- [ ] **8. SSH in as root and run:**
  ```bash
  git clone -b claude/gifted-sagan-mcbjao https://github.com/synark-xyz/mailu.git
  cd mailu/deploy
  sudo ./deploy.sh --prod
  ```
- [ ] **9. Save the admin password** the script prints at the end. The login is `admin@getserviceflow.app`.
- [ ] **10. Check it's healthy:** `cd /mailu && docker compose ps` shows all services `Up`. The first start can take 1 to 2 minutes while the certificate is issued.
- [ ] **11. Open `https://mail.getserviceflow.app/admin`**, which should load over valid HTTPS. Log in and change the admin password.

## D. DKIM (required for deliverability)

- [ ] **12. Get the DKIM record:** Admin UI → *Mail domains* → `getserviceflow.app` → **Details** (DNS). Copy the `dkim._domainkey` TXT value. If none is shown, click *Regenerate keys*.
- [ ] **13. Add it to DNS** as a TXT record named `dkim._domainkey`.

## E. Create mailboxes

- [ ] **14. Admin UI → Mail domains → getserviceflow.app → Users → Add user.** Create `you@getserviceflow.app` and any others you want.
- [ ] **15. Log in to webmail** at `https://mail.getserviceflow.app/webmail`.

## F. Test

- [ ] **16. Receive:** send an email to your new address from Gmail and confirm it arrives.
- [ ] **17. Send:** send to a Gmail address and check it lands in the inbox (not spam). In Gmail, open the message → *Show original* and confirm SPF, DKIM and DMARC all say **PASS**.
- [ ] **18. Score it:** send a message to the address shown at https://www.mail-tester.com and aim for 9/10 or higher.
- [ ] **19. Check your IP isn't blacklisted:** https://mxtoolbox.com/blacklists.aspx

## G. Afterwards

- [ ] **20. Back up `/mailu`** on a schedule (at minimum `data`, `dkim`, `mail`, `mailu.env`).
- [ ] **21. Once mail passes everywhere for a week**, you can tighten DMARC to `p=reject`.
- [ ] **22. Mail clients** use IMAP `mail.getserviceflow.app:993` (SSL) and SMTP `:465` (SSL) or `:587` (STARTTLS). The username is the full address.

## If something goes wrong

| Symptom | Likely cause |
|---|---|
| Certificate error or site won't load | `mail` A record not propagated yet, or port 80/443 blocked. Check `docker compose logs front`. |
| Can receive but not send | Outbound port 25 blocked by host. |
| Mail lands in spam | PTR not set, DKIM missing, or new IP reputation. Re-run step 17. |
| `deploy.sh` says a port is in use | Another service is bound to it. Stop that service and re-run. |
| Need logs | `cd /mailu && docker compose logs -f front smtp imap` |

**Note:** the repo is at `synark-xyz/mailu` on branch `claude/gifted-sagan-mcbjao`. If it's private, clone with a token or deploy key, or copy `deploy/` to the server with `scp`.
