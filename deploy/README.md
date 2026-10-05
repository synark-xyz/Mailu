# Mailu deployment for getserviceflow.app

Mail host: `mail.getserviceflow.app` · Webmail (Roundcube): `/webmail` · Admin: `/admin`

## Requirements
- A VPS/server with a **public static IPv4**, Debian/Ubuntu, 2 GB+ RAM, root access.
- **Outbound port 25 open** (many hosts block it by default; ask your provider).
- Ports 25, 80, 143, 443, 465, 587, 993, 995, 110, 4190 free and not firewalled.
- Reverse DNS (PTR) for your IP set to `mail.getserviceflow.app` (set in your hosting panel).

## 1. DNS (do this first so Let's Encrypt works)
Replace `SERVER_IP` with your server's IPv4.

| Type | Name | Value |
|---|---|---|
| A | `mail` | `SERVER_IP` |
| MX | `@` | `10 mail.getserviceflow.app.` |
| TXT | `@` | `v=spf1 mx ~all` |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; adkim=s; aspf=s; rua=mailto:admin@getserviceflow.app` |
| CNAME | `autoconfig` | `mail.getserviceflow.app.` |
| CNAME | `autodiscover` | `mail.getserviceflow.app.` |
| TXT | `dkim._domainkey` | *(generated after install – see step 3)* |
| PTR | `SERVER_IP` | `mail.getserviceflow.app` (at your host) |

## 2. Install
```bash
git clone <this repo> && cd Mailu/deploy
sudo ./install.sh
```
Everything lives in `/mailu` (config: `/mailu/mailu.env`, data: `/mailu/mail`). The script generates a random `SECRET_KEY` and admin password and prints the password at the end.

## 3. DKIM
Log in at `https://mail.getserviceflow.app/admin` as `admin@getserviceflow.app` →
**Mail domains → getserviceflow.app → Details (DNS)**. Copy the DKIM TXT record into DNS.
(If the domain isn't listed yet, it is created on first install; click *Regenerate keys* if no DKIM shows.)

## 4. Users
Admin UI → *Mail domains → getserviceflow.app → Users → Add user*. Clients: IMAP `mail.getserviceflow.app:993` (SSL), SMTP `:465` (SSL) or `:587` (STARTTLS), username = full address.

## Operations
```bash
cd /mailu
docker compose ps
docker compose logs -f front smtp
docker compose pull && docker compose up -d     # update (same MAILU_VERSION)
```
Back up `/mailu` (at minimum `data`, `dkim`, `mail`, `mailu.env`). Check deliverability at mail-tester.com.
