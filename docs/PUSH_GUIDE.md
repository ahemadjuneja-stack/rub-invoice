# Pushing to GitHub + Deploy Key

Repo: `https://github.com/ahemadjuneja-stack/rub-invoice`

A deploy key pair has been generated for this repo:

* `ruby_invoice_ed25519` (PRIVATE key - keep safe, never commit, never share)
* `ruby_invoice_ed25519.pub` (PUBLIC key - safe to add to GitHub)

> Deploy keys give access to exactly ONE repository. If you prefer, you can
> also push with your usual GitHub login (HTTPS + browser token) and skip
> this setup entirely.

## Step 1 - add the public key to the repo

1. GitHub -> open the repo -> **Settings** -> **Deploy keys** -> **Add deploy key**.
2. Title: `ruby-invoice-ci`, paste the FULL contents of
   `ruby_invoice_ed25519.pub` (one line starting with `ssh-ed25519 AAAA...`).
3. Tick **Allow write access** -> Add key.

## Step 2 - configure SSH on your machine

Copy the private key file somewhere safe, e.g. `~/.ssh/`:

```bash
mkdir -p ~/.ssh
cp ruby_invoice_ed25519 ~/.ssh/ruby_invoice_ed25519
chmod 600 ~/.ssh/ruby_invoice_ed25519
```

Add a host alias in `~/.ssh/config` (create the file if needed):

```
Host github-ruby-invoice
    HostName github.com
    User git
    IdentityFile ~/.ssh/ruby_invoice_ed25519
    IdentitiesOnly yes
```

## Step 3 - push

The repo folder ships with an initial commit on `main`. Attach your remote
and push:

```bash
cd ruby_invoice
git remote add origin git@github-ruby-invoice:ahemadjuneja-stack/rub-invoice.git
git push -u origin main
```

(If the remote already exists, use `git remote set-url origin ...` instead.
If you push with HTTPS instead, simply use
`https://github.com/ahemadjuneja-stack/rub-invoice.git` and your GitHub
credentials.)

## Step 4 - first CI build

* Pushing to `main` triggers **Android CI**: analyze + release APK.
  Download the APK from the run's **Artifacts** section.
* To publish a release: `git tag v0.1.0 && git push origin v0.1.0` ->
  the APK is attached to a GitHub Release automatically, and the app's
  *Check Updates* button finds it.

## Verify the key works

```bash
ssh -T git@github-ruby-invoice
# -> "Hi ahemadjuneja-stack/rub-invoice! You've successfully authenticated..."
```

## Security notes

* The private key in this folder is unencrypted for convenience. If you
  plan to keep it long-term, re-encrypt it:
  `ssh-keygen -p -f ~/.ssh/ruby_invoice_ed25519`
* Delete `ruby_invoice_ed25519` from this folder after copying it.
* If a key ever leaks: repo Settings -> Deploy keys -> remove, then
  generate a new one (`ssh-keygen -t ed25519 -C "ruby-invoice-deploy-key"`).
