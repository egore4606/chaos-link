# Security policy

## Supported versions

Chaos Link is a small early-stage project. Security fixes target the latest code on `main` and the newest published release only.

## Reporting a vulnerability

Please do not publish exploitable details in a public issue. Use [GitHub private vulnerability reporting](https://github.com/egore4606/chaos-link/security/advisories/new) and include:

- the affected version or commit;
- reproduction steps and expected impact;
- whether the issue exposes a room, host input, credentials, or local files;
- a suggested mitigation, if known.

Do not test against systems or users without their permission.

## Deployment guidance

- Generate unique room, guest, admin, and agent credentials for every installation.
- Share only the guest key with controllers and keep the admin and agent keys private.
- Do not commit `.runtime`, `deploy`, `dist`, logs, or custom media containing personal information.
- Expose the web server only through HTTPS/WSS or a trusted LAN; never expose a separate remote-control or shell endpoint.
- Stop the app and use the emergency release if input behavior is unexpected.

The bundled development credentials are examples only and must not be used for an internet-accessible manual deployment. The installer generates fresh random credentials.
