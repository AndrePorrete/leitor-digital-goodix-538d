# fprint-538d — Goodix 27c6:538d fingerprint reader on Linux

*[Versão em português: LEIAME.md](LEIAME.md)*

Makes the Goodix `27c6:538d` fingerprint reader (power button of the Dell Inspiron 5590 and other
Dell laptops) work on Linux: login, screen unlock, `sudo` and password dialogs.

| Guided test on an Inspiron 5590 | |
|---|---|
| Enrolled finger | 8/8 accepted |
| Other fingers | 0/8 accepted |

## Install

1. Open a **Terminal**: press **Ctrl + Alt + T** (or look for "Terminal" in the menu).
2. Copy the line below (copy button on its right), paste it in the Terminal with
   **Ctrl + Shift + V** and press **Enter**:

```sh
bash <(wget -qO- https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh || curl -fsSL https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh)
```

3. Follow the screen. The installer explains every step and shows when it is working:
   1. checks that the `27c6:538d` reader is present (refuses anything else);
   2. asks two questions — fingerprint for login (your password keeps working) and the
      recognition level (for callused fingers, choose **Tolerant**);
   3. downloads the prebuilt driver (checksum verified);
   4. asks for **your password once** (nothing shows while you type — normal) and installs it in
      `/opt/fprint-538d`, next to your distribution's `fprintd` (nothing overwritten); the reader
      firmware is checked and everything is undone if it is not compatible;
   5. guides you through enrolling a finger: 15 **light** touches.

Fingerprint login uses your distribution's own standard switch. Nothing else on the system is
changed and nothing is written to the sensor. After reinstalling the system, just repeat.

### After installing

Open the applications menu and look for **Fingerprint reader** (or type `leitor-digital` in a
terminal): enroll more fingers, test, change the recognition level, update or uninstall — no
commands to type.

## Hard fingers (calluses, dry skin)

String players, manual workers or people with very dry skin may have fingers the reader recognises
poorly. Then:

1. **Enroll the fingers with fewer calluses** (e.g. the ones that do not press strings). You can
   enroll several: any of them is accepted.
2. **Choose the recognition level** — the installer asks during installation; to change it later:

   ```sh
   leitor-digital      # menu option 3
   ```

   Without questions: `--level tolerant` (or `default`, `strict`), on install or with `--tune`.

   | Level | Minimum score | When |
   |---|---|---|
   | Strict | 70 | maximum security, you accept repeating touches |
   | Default | 60 | most people |
   | Tolerant | 55 | callused or dry fingers |

   In the tests, wrong fingers scored at most 51: Tolerant is still above that, with less margin.
   The setting is kept on updates.
3. Enroll again when the calluses change a lot. The reader also learns from well recognised
   touches (score ≥ 75).

## Supported

| Family | Distributions | PAM (login) setup |
|---|---|---|
| Debian/Ubuntu | Ubuntu, Linux Mint, Pop!_OS, Zorin, elementary, Debian 12+ | `pam-auth-update` |
| Fedora | Workstation; Atomic: Silverblue, Kinoite, Bazzite, Aurora, Bluefin | `authselect` |
| Arch | Arch, CachyOS, EndeavourOS, Manjaro | no standard switch: GNOME/KDE login and lock screens use it on their own; `sudo` needs a manual line ([Arch wiki](https://wiki.archlinux.org/title/Fprint)) |
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
