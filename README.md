# fprint-538d — Goodix 27c6:538d fingerprint reader on Linux

*[Versão em português: LEIAME.md](LEIAME.md)*

Makes the Goodix `27c6:538d` fingerprint reader (power button of the Dell Inspiron 5590 and other
Dell laptops) work on Linux: login, screen unlock, `sudo` and password dialogs.

| Guided test on an Inspiron 5590 | |
|---|---|
| Enrolled finger | 8/8 accepted |
| Other fingers | 0/8 accepted |

## Install

Open a terminal and paste (as your normal user, **not** with sudo):

```sh
curl -fsSLO https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh && bash instalar.sh
```

The installer:

1. checks that the `27c6:538d` reader is present (and refuses anything else);
2. downloads a prebuilt driver bundle (checksum verified) — no compiling;
3. asks for your password **once** and installs it in `/opt/fprint-538d`, next to your
   distribution's `fprintd` (no distribution file is overwritten);
4. checks the reader firmware and undoes everything if it is not compatible;
5. optionally enables the fingerprint for login, screen unlock, `sudo` and password dialogs
   (**your password always keeps working**), and stops a light touch on the power button from
   turning the laptop off;
6. guides you through enrollment and a quick right-finger / wrong-finger test.

Running it again updates or repairs the installation and keeps your fingerprints.

**Uninstall** (restores login settings and the original `fprintd`):

```sh
bash /opt/fprint-538d/share/fprint-538d/instalar.sh --uninstall
```

Tips: **touch lightly** (pressing distorts the print and may trigger the power button), and do the
second enrollment the installer offers (same finger, rotated) so it is accepted at more angles.

## Supported

| Family | Distributions | PAM (login) setup |
|---|---|---|
| Debian/Ubuntu | Ubuntu, Linux Mint, Pop!_OS, Zorin, elementary, Debian 12+ | `pam-auth-update` |
| Fedora | Workstation; Atomic: Silverblue, Kinoite, Bazzite, Aurora, Bluefin | `authselect` |
| Arch | Arch, CachyOS, EndeavourOS, Manjaro | lines in `sudo`, `polkit-1`, `system-local-login` |
| openSUSE | Tumbleweed, Leap 15.6, Aeon/Kalpa | `pam-config` |

Tested so far: Linux Mint 22.3 on an Inspiron 5590. The other distributions are checked
automatically (the bundle loads on each of them) but not yet on real hardware — **please report
your result** (model, distribution, test result) in the
[issues](https://github.com/AndrePorrete/leitor-digital-goodix-538d/issues).

Laptops known to have this reader: Dell Inspiron 5590, 5402, 5409, 3501, 7506; Latitude 3410;
Vostro 3500. Any computer with USB `27c6:538d` and firmware `GF5298_GM168SEC_APP_13016` is accepted.
**Nothing is ever written to the sensor.**

## How it works

- Driver: community SIGFM fork of libfprint for this sensor
  ([BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d)), with a new
  matcher (aligned correlation + block verification: the sensor shows only 4–5 parallel ridges,
  too few minutiae for the usual algorithms), learning only from confident matches, automatic
  sensor calibration, and a fix for an enrollment hang.
- `fprintd` 1.94.5 with a patch to store learned prints and allow a second enrollment of the same
  finger. A systemd drop-in makes the distribution's `fprintd.service` start this one.
- Details, measurements and what failed: [PROTOCOLO.md](PROTOCOLO.md) (Portuguese).

Repository: `instalar.sh` (installer), `patches/` (libfprint, fprintd), `construir/` (bundle build
in an Ubuntu 22.04 container; also run by GitHub Actions), `ferramentas/` (test and analysis tools),
`config/` (reference configuration).

Build the bundle yourself: `construir/no-conteiner.sh` (podman or docker), or
`bash instalar.sh --compilar`.

## Credits and licenses

- [BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d) and its libfprint
  fork; [goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev); infinytum's libfprint work;
  [01xcampos/goodix-27c6-538d-ubuntu](https://github.com/01xcampos/goodix-27c6-538d-ubuntu).
- libfprint patches: LGPL-2.1-or-later; fprintd patch: GPL-2.0-or-later; scripts: GPL-2.0-or-later
  ([LICENSE](LICENSE)). The bundle includes OpenCV and OpenSSL (Apache-2.0), statically linked;
  licenses and source references are in `/opt/fprint-538d/share/fprint-538d/`.
