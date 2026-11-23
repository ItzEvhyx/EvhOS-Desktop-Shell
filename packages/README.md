# CachyOS package inventory

These files document the explicit packages installed on the machine that produced this desktop capture. They are an inventory for reproducing the broader workstation, not an unattended package-install script.

- `arch-explicit.txt` is the complete `pacman -Qqe` list.
- `arch-foreign.txt` lists packages not supplied by the configured official repositories, typically AUR packages.

Start with `./install.sh --plan` and the package lists documented in `install.sh`. Review this inventory, especially the foreign packages, before installing anything extra. The installer does not enable third-party repositories, invoke an AUR helper, install development tools, or modify boot/system configuration without an explicit option.
