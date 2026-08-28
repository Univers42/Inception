# Why the browser says the site is not secure, and what to do about it

You will meet one of these after building the project:

```
Firefox   Warning: Potential Security Risk Ahead
          "Someone pretending to be the site could try to steal..."
Chrome    Your connection is not private
          net::ERR_CERT_AUTHORITY_INVALID
```

**Nothing is broken and nobody is attacking you.** Both messages mean one thing:

> *I do not recognise whoever signed this certificate.*

Not "this certificate is invalid", not "the domain is wrong". Only: **unknown
issuer**. Chrome's error code says it outright — `CERT_AUTHORITY_INVALID`.

---

## 1. Why this project has its own certificate authority

`dlesieur.42.fr` is not a real domain. No public authority — Let's Encrypt,
DigiCert — will ever issue a certificate for it, because you cannot prove you own
a name that does not exist outside this machine. But the subject requires HTTPS.

So `make setup` builds a miniature version of the public certificate system,
inside the VM, in `secrets/`:

| File | What it is |
|---|---|
| `ca.key` | The private key of **your own certificate authority**. Never leaves the VM. |
| `ca.crt` | That authority's public certificate. This is the one browsers must trust. |
| `server.key` | The web server's private key. |
| `server.crt` | The certificate for `dlesieur.42.fr`, **signed by `ca.key`**. |

NGINX presents `server.crt`. A browser checks it and asks: *who signed this?*
The answer is "Inception Local CA" — an authority that exists only on your
machine and that no browser has ever heard of. Hence the warning.

Real websites work because your browser ships with ~150 authorities baked in. You
are adding a 151st, by hand, for this one project.

---

## 2. Why it comes back every time you rebuild the VM

This is the part that catches people out.

`make setup` generates the CA **only if `secrets/ca.crt` does not already
exist**. Destroy the VM and its disk, and `secrets/` goes with it. The next build
generates a **brand-new CA, with a new key and a new serial number**.

Your browser is still trusting the *old* one. The new server certificate is
signed by a key the browser has never seen, so it is rejected exactly as if you
had never configured anything.

```
Before rebuild   browser trusts CA serial 3372C194…   server signed by 3372C194…   ✅
After  rebuild   browser trusts CA serial 3372C194…   server signed by 20D0EF7B…   ❌ warning
```

**So yes — after every VM rebuild you have to re-trust the new CA on the host.**
There is no way around it: the certificate genuinely is different. It is one
command, and it is scriptable, but it does have to happen.

---

## 3. Why it has to be done on the host, not in the VM

Trust is **per machine, and per program**. The VM trusting its own CA does
nothing for a browser running on the host — they are different machines with
different trust stores.

Worse, on Linux there is no single store. Each program keeps its own:

| Program | Where it looks | Notes |
|---|---|---|
| `curl`, `wget`, most CLI tools | `/etc/ssl/certs` | System-wide — **needs root** |
| Firefox | `cert9.db` inside *each profile* | Ignores the system store entirely |
| Chrome / Chromium | `~/.pki/nssdb` | Also ignores the system store |
| Chromium **snap** | `~/snap/chromium/*/.pki/nssdb` | Confined: it cannot even read `~/.pki` |

Firefox and Chrome deliberately ignore the system store, which is why "I
installed the CA system-wide and the browser still complains" is such a common
confusion. On a 42 machine you have no root anyway, so the system store is out of
reach — but the browser stores are all in your home directory and need no
privileges at all.

---

## 4. Doing it by hand

The tool is `certutil`, from `libnss3-tools`. Installing that package needs root,
but the package can simply be unpacked as a normal user:

```bash
mkdir -p ~/.cache/nss && cd ~/.cache/nss
apt-get download libnss3-tools          # no root required
dpkg-deb -x libnss3-tools_*.deb .       # certutil is now at ./usr/bin/certutil
```

Then, **on the host**:

```bash
# 1. Fetch the CA the VM just generated
ssh b2b 'cat ~/inception/secrets/ca.crt' > /tmp/inception-ca.crt

# 2. Check it is the one actually being served (these serials must match)
openssl x509 -in /tmp/inception-ca.crt -noout -serial
openssl s_client -connect 127.0.0.1:8443 -servername dlesieur.42.fr </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer

# 3. Trust it in every store. -D first, then -A:
#    -D removes the previous VM's CA, which otherwise stays behind under the
#    same nickname and you end up with two entries and a still-broken browser.
CU=~/.cache/nss/usr/bin/certutil
for STORE in ~/snap/firefox/common/.mozilla/firefox/*.default*/ \
             ~/.pki/nssdb \
             ~/snap/chromium/current/.pki/nssdb; do
    [ -d "$STORE" ] || continue
    "$CU" -D -n "Inception Local CA" -d "sql:$STORE" 2>/dev/null
    "$CU" -A -n "Inception Local CA" -t "C,," -d "sql:$STORE" -i /tmp/inception-ca.crt
done

# 4. Restart the browser. Trust decisions are read at launch; a running
#    browser will keep showing the warning no matter what is on disk.
```

`-t "C,,"` is the trust flag: *trusted to issue server certificates*, and nothing
else. It does not grant email or code-signing trust.

---

## 5. Doing it automatically

All of the above is what `born2root`'s `make host_access` performs — plus the
name resolution and port mapping the domain also needs. From the born2root
checkout on the host:

```bash
make host_access     # trust the CA, wire up the domain, restart the browsers
make verify_access   # prove it: fails loudly if anything is stale
```

`make inception` and `make fresh` call it for you at the end of a build, so it is
only a manual step when you build inside the VM by hand.

**The rule: re-run `make host_access` after every VM rebuild.**

---

## 6. Checking your work

```bash
# Does the chain validate against the CA? 0 means yes.
curl -s --cacert /tmp/inception-ca.crt \
     --resolve dlesieur.42.fr:8443:127.0.0.1 \
     -o /dev/null -w '%{http_code} verify=%{ssl_verify_result}\n' \
     https://dlesieur.42.fr:8443/
```

`200 verify=0` means the certificate is genuinely trusted. Anything else:

| `ssl_verify_result` | Meaning | Fix |
|---|---|---|
| `0` | Valid | — |
| `20` | Cannot find the issuer's certificate | The CA is not in that store — step 3 |
| `10` | Expired | Rebuild; the server cert lasts one year |
| `62` | Hostname mismatch | Wrong SAN — check `make certs` |

And to confirm the browser stores agree with the VM, compare serials — they must
be identical:

```bash
openssl x509 -in /tmp/inception-ca.crt -noout -serial
$CU -L -n "Inception Local CA" -d sql:~/.pki/nssdb -a | openssl x509 -noout -serial
```

---

## 7. What about just clicking "Accept the Risk"?

It works, and for a quick look it is fine. But it is worth knowing what it does
differently:

- it stores an exception for **that one host**, not trust in the CA, so every
  other hostname on the same certificate warns again;
- it is per browser and per profile, so it must be repeated everywhere;
- the padlock stays broken, and Chrome keeps flagging the page;
- and it teaches the habit of clicking through security warnings, which is the
  actual risk here — not this certificate.

Trusting the CA properly costs one command and leaves you with a real padlock.

---

## 8. Common symptoms

| What you see | Cause |
|---|---|
| `ERR_CERT_AUTHORITY_INVALID` / "Someone pretending to be the site" | CA not trusted, or stale after a rebuild |
| Warning in Firefox, fine in Chrome (or vice-versa) | Only one store was updated — they are separate |
| Trusted it, warning persists | Browser not restarted, or a snap that cannot read `~/.pki` |
| `ERR_CERT_COMMON_NAME_INVALID` | Not a trust problem — the certificate's SAN does not cover the name |
| Works in the VM, warns on the host | Normal: the VM trusts its own CA, the host does not |
