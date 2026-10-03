# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Merge this to pull in a minimal Plasma 6 desktop, without applications"
HOMEPAGE="https://kde.org/plasma-desktop/"

LICENSE="metapackage"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+bluetooth +kwallet +networkmanager +pulseaudio"

# What a Plasma session needs to start and be usable, and nothing else: no
# kde-apps (no file manager, no terminal) -- pick those separately, or merge
# kde-plasma/plasma-meta for the full desktop. plasma-desktop brings the rest
# of the session itself: plasma-workspace, kwin, breeze, kscreenlocker,
# plasma-integration and xdg-desktop-portal-kde. The login manager's session
# entries come with plasma-workspace too -- through plasma-login-sessions up to
# Plasma 6.7, inside plasma-workspace (which blocks that package) from 6.8 on --
# so they are not named here.
RDEPEND="
	kde-plasma/kde-cli-tools:6
	kde-plasma/kscreen:6
	kde-plasma/plasma-desktop:6
	kde-plasma/polkit-kde-agent:6
	kde-plasma/powerdevil:6
	kde-plasma/systemsettings:6
	bluetooth? ( kde-plasma/bluedevil:6 )
	kwallet? ( kde-plasma/kwallet-pam:6 )
	networkmanager? (
		kde-plasma/plasma-nm:6
		net-misc/networkmanager
	)
	pulseaudio? ( kde-plasma/plasma-pa:6 )
"
