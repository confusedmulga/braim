# Security Policy

Braim keeps your library on your phone and runs no server of its own. The parts
with a security surface are Braim Web (a local web server you can switch on),
backup files, and the pages and previews the App fetches.

## Reporting a problem

Please report security problems privately, not in a public issue:

- Use GitHub's **Report a vulnerability** button on this repository's
  Security tab, or
- email **yellowisjoyy@gmail.com** with "Braim security" in the subject.

Include what you found, the steps to reproduce it, and the App version
(Settings › About). We aim to reply within a week and will credit you in the
fix unless you'd rather not be named.

## Known limitations (by design, documented)

- The **Crypt** folder restricts access inside the App; it is **not
  encrypted**.
- **Backups** are plain zip files and include Crypt items.
- **Braim Web** uses plain HTTP on your local network. Use it only on networks
  you trust.

These are described in the [Privacy Policy](PRIVACY.md) and are not
vulnerabilities in themselves, but reports of ways around them (for example,
reaching Braim Web without pairing, or reading Crypt items from it) are very
welcome.
