# Delivest landing

Static landing page of Delivest: `index.html` and `screens/`.

## Deploy

On a server with nginx and certbot, with the domain already pointing to it:

```bash
git clone https://github.com/ShafranovKirill/delivest-landing.git
cd delivest-landing
cp .env.example .env
nano .env
sudo ./deploy.sh
```

The script copies the page to `/var/www/<DOMAIN>`, writes the nginx config for `DOMAIN`, issues a Let's Encrypt certificate and redirects HTTP to HTTPS. To update: `git pull && sudo ./deploy.sh`.
