# kinfocenter's "About this System" reads /etc/xdg/kcm-about-distrorc first and
# falls back to os-release field by field (Name, Version, Website, LogoPath).
# The file ::gentoo installs only sets LogoPath to a Gentoo logo, so leaving it
# out makes the page show what os-release says -- the TODO in the ebuild.
INSTALL_MASK+=" /etc/xdg/kcm-about-distrorc /usr/share/kinfocenter/glogo-small.png"
