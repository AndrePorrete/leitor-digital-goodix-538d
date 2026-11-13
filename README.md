# Goodix 27c6:538d fingerprint reader on Linux

**🇧🇷 Em português: [LEIAME.md](LEIAME.md)**

Makes the fingerprint reader in the **power button** of the Dell Inspiron 5590 (and other Dell
laptops with the same reader) work on Linux: login, screen unlock, `sudo` and password dialogs.
Your password always keeps working; the fingerprint is just a shortcut.

| Guided test on an Inspiron 5590 | |
|---|---|
| Enrolled finger | 8 of 8 accepted |
| Other fingers | 0 of 8 accepted |

## Install (5 minutes)

1. Open a **Terminal**: press **Ctrl + Alt + T** (or look for "Terminal" in the applications menu).
2. Copy the line below (copy button on its right), paste it in the Terminal with
   **Ctrl + Shift + V** and press **Enter**:

```sh
sh -c "wget -qO- https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh || curl -fsSL https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh" | bash
```

3. Follow the screen. It explains every step and shows when it is working:
   1. checks that the `27c6:538d` reader is present (otherwise it stops without changing anything);
   2. asks two questions: fingerprint for login, and the recognition level (for callused or dry
      fingers, choose **Tolerant**);
   3. downloads the prebuilt driver (checksum verified);
   4. asks for **your password once** (nothing shows while you type; that is normal) and installs;
   5. guides you through enrolling a finger: 15 **light** touches on the power button.

**Touch tips:** touch lightly without pressing the button; clean, dry finger; vary the position a
little while enrolling (tip, centre, slightly sideways).

## After installing: the "Fingerprint reader" menu

Open the applications menu and look for **Fingerprint reader** (or type `leitor-digital` in a
terminal): 1 enroll a finger (another one, or the same again), 2 test, 3 recognition level,
4 delete fingerprints, 5 update or repair, 6 uninstall. No commands to type.
After reinstalling the system, just run the install line again.

## Recognition level

| Level | Minimum score | When |
|---|---|---|
| Strict | 70 | maximum security, you accept repeating a touch now and then |
| Default | 60 | most people |
| Tolerant | 55 | callused or dry fingers, or fingers that often fail |

In the tests, wrong fingers scored at most 51: Tolerant is still above that, with less margin. The
level is kept on updates. Without questions: `--level tolerant` (or `default`, `strict`), on install
or with `--tune`.

## Systems

Needs an **x86_64** computer (64-bit Intel/AMD), **systemd** and **glibc 2.33 or newer**. The
installer checks all of this before changing anything.

**Tested on real hardware** (Inspiron 5590): Linux Mint 22.3 and CachyOS.

**Checked in containers for every release** (the driver loads, the installer recognises the system
and turns fingerprint login on and off cleanly):

| Family | Checked | Fingerprint login is turned on with |
|---|---|---|
| Ubuntu / Debian | Ubuntu 22.04, 24.04, 26.04; Linux Mint 22; Debian 12, 13 | `pam-auth-update` (the system's standard switch) |
| Fedora | Fedora 42, 43, 44; Fedora Kinoite 43; Bazzite; AlmaLinux 9, 10 | `authselect` |
| Arch | Arch Linux, Manjaro, CachyOS | no standard switch (see "Common problems") |
| openSUSE | Tumbleweed; Leap 15.6, 16.0 | `pam-config` |

**Expected to work** (same family, not yet checked): Pop!_OS, Zorin OS, elementary OS, KDE neon,
Nobara, Fedora Silverblue, Aurora, Bluefin, Rocky Linux 9+, EndeavourOS, Garuda, openSUSE Aeon and
Kalpa.

**Not supported:** 32-bit or ARM; glibc older than 2.33 (e.g. Ubuntu 20.04, Debian 11, Linux Mint
20); no systemd (Devuan, Void, Artix) or musl (Alpine).

**Laptops** known to have this reader: Dell Inspiron 5590, 5402, 5409, 3501, 7506; Latitude 3410;
Vostro 3500. Any computer with USB `27c6:538d` and firmware `GF5298_GM168SEC_APP_13016` is accepted.
**Nothing is ever written to the sensor.**

## Common problems

- **Finger not recognised:** touch more lightly and wait a moment. If it fails often, choose
  **Tolerant** (menu option 3) and enroll the same finger again (option 1), ideally the way it
  usually is day to day (e.g. dry). You can enroll several fingers.
- **The laptop shuts down or suspends when I touch it:** the button was pressed. Just touch it. You
  can set the power button to "Do nothing" in *Settings > Power*; holding it for 4 seconds still
  forces power-off.
- **Arch, Manjaro, CachyOS, EndeavourOS:** the GNOME and KDE login and lock screens use the
  fingerprint on their own. For `sudo` and password dialogs, follow the
  [Arch wiki](https://wiki.archlinux.org/title/Fprint) (one line in `/etc/pam.d/sudo` and
  `/etc/pam.d/polkit-1`).
- **I tried another guide first:** some scripts install a different driver over the system's
  fingerprint library (`libfprint`). The installer notices and offers to restore the original; this
  driver does not depend on it.
- **Stopped working after a big system upgrade:** menu "Fingerprint reader", **5 Update or repair**.
- **Remove everything:** menu "Fingerprint reader", **6 Uninstall**.

## Tell us how it went

Worked (or not) on your laptop? Open a report in
[Issues](https://github.com/AndrePorrete/leitor-digital-goodix-538d/issues/new/choose) with the
laptop model, the system and the test result. Reports from Fedora, Arch and openSUSE on real
hardware help a lot.

## How it works

- Driver: community SIGFM fork of libfprint for this sensor
  ([BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d)), with a new
  matcher (aligned correlation + block verification: the sensor shows only 4–5 parallel ridges, too
  few minutiae for the usual algorithms), learning only from confident matches, automatic sensor
  calibration, and fixes for an enrollment hang and a crash.
- `fprintd` 1.94.5 with a patch to store learned prints. A systemd drop-in makes the distribution's
  `fprintd.service` start this one from `/opt/fprint-538d`; nothing of the distribution is overwritten.

Repository: `instalar.sh` (installer), `patches/` (libfprint, fprintd), `construir/` (bundle build
in an Ubuntu 22.04 container, also run by GitHub Actions for every release).
Build the bundle yourself: `construir/no-conteiner.sh` (podman or docker) or `bash instalar.sh --build`.
Check it on many distributions in containers: `construir/testar-distros.sh` and `construir/testar-pam.sh`.

## Credits and licenses

- [BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d) and its libfprint
  fork; [goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev); infinytum's libfprint work;
  [01xcampos/goodix-27c6-538d-ubuntu](https://github.com/01xcampos/goodix-27c6-538d-ubuntu).
- libfprint patches: LGPL-2.1-or-later; fprintd patch: GPL-2.0-or-later; scripts: GPL-2.0-or-later
  ([LICENSE](LICENSE)). The bundle includes OpenCV and OpenSSL (Apache-2.0), statically linked;
  licenses and source references are in `/opt/fprint-538d/share/fprint-538d/`.
