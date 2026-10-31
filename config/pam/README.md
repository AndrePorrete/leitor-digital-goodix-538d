# PAM — digital em login, desbloqueio, sudo e janelas de senha

Linha usada (Mint, via perfil `pam-auth-update`):

    auth [success=end default=ignore] pam_fprintd.so max-tries=3 timeout=20

`pam_fprintd.so` vem do pacote da distro (não é compilado aqui); ele fala com o fprintd por D-Bus,
então funciona com o fprintd de `/opt/fprint-538d`.

| Distro | Como ativar |
|---|---|
| Mint/Ubuntu | perfil em `/usr/share/pam-configs/` + `pam-auth-update --package` (o app Fingwit cria um com `max-tries=1`; trocamos para 3) |
| Fedora / Bazzite | `authselect enable-feature with-fingerprint` (ajustar `max-tries` no perfil custom do authselect) |
| Arch / CachyOS | não há ferramenta: adicionar a linha no topo de `/etc/pam.d/sudo`, `/etc/pam.d/polkit-1`, `/etc/pam.d/system-local-login`; KDE (SDDM/kscreenlocker) e GNOME (GDM) já têm arquivo próprio de digital |

Sempre: backup do arquivo antes, e um terminal root aberto durante o teste.
