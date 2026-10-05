#!/usr/bin/env python3
"""Send a test mail to a Mailu server and check it arrived. Stdlib only.

  ./test-mail.py --to alice@getserviceflow.app --password 'alice-pw'
      Inbound test: delivers via SMTP :25 (no auth, like the outside world), then reads alice's INBOX via IMAP.
  ./test-mail.py --from bob@getserviceflow.app --from-password bob-pw --to alice@getserviceflow.app --password alice-pw
      Authenticated send as bob (SMTP :587), then check alice's INBOX.
"""
import argparse, imaplib, smtplib, sys, time, uuid
from email.message import EmailMessage

p = argparse.ArgumentParser()
p.add_argument("--host", default="localhost")
p.add_argument("--smtp-port", type=int, default=25, help="25 inbound / 587 submission (auto-set when --from given)")
p.add_argument("--imap-port", type=int, default=143)
p.add_argument("--from", dest="sender", default="outside-test@example.org")
p.add_argument("--from-password", help="authenticate as the sender (submission, port 587)")
p.add_argument("--to", required=True)
p.add_argument("--password", help="recipient password; if given, verify via IMAP")
a = p.parse_args()

tag = uuid.uuid4().hex[:8]
msg = EmailMessage()
msg["From"], msg["To"], msg["Subject"] = a.sender, a.to, f"mailu test {tag}"
msg.set_content(f"Hello from test-mail.py ({tag})")

port = 587 if a.from_password else a.smtp_port
with smtplib.SMTP(a.host, port, timeout=30) as s:
    if a.from_password:
        s.login(a.sender, a.from_password)
    s.send_message(msg)
print(f"sent '{msg['Subject']}' via {a.host}:{port}")

if not a.password:
    sys.exit(0)
for _ in range(15):
    m = imaplib.IMAP4(a.host, a.imap_port)
    m.login(a.to, a.password)
    m.select("INBOX")
    _, data = m.search(None, "SUBJECT", f'"{tag}"')
    m.logout()
    if data[0]:
        print("OK: message arrived in INBOX")
        sys.exit(0)
    time.sleep(2)
print("FAIL: message not found in INBOX after 30s (check: ./deploy.sh --local logs smtp imap)")
sys.exit(1)
