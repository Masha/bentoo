# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop udev xdg

# Upstream names the archive after a TWO-component version ("21.1"), while the
# API that .autoupdate probes reports three ("21.1.0").  The ${PV%.0} strip is
# what reconciles them, and it is only correct while the third component is 0 --
# a hypothetical 21.1.1 would keep all three, which is also what upstream names
# such a release.  A bump that changes this shape must re-check the file name
# before trusting the Manifest.

# Blackmagic RESPINS a release under the SAME file name: "21.1" was build 0014
# on 7 Sep 2026 and build 0017 on 10 Sep 2026, and only the second one is still
# served.  The zip is RESTRICT=fetch, so the mismatch surfaces as a digest
# failure on the user's machine and nowhere else -- there is no fetch here that
# could have caught it.  The build the Manifest describes is readable from the
# payload itself:
#
#   unzip -o DaVinci_Resolve_21.1_Linux.zip
#   chmod u+x DaVinci_Resolve_21.1_Linux.run
#   unsquashfs -o "$(./DaVinci_Resolve_21.1_Linux.run --appimage-offset)" \
#       -d out DaVinci_Resolve_21.1_Linux.run bin/resolve
#   strings -a out/bin/resolve | grep -oE '21\.1\.0\.[0-9]{4}'
#
# A digest failure reported by a user is therefore a respin until proven
# otherwise, NOT a corrupt download.
ZIP_NAME="DaVinci_Resolve_${PV%.0}_Linux"
RUN_NAME="${ZIP_NAME}.run"

DESCRIPTION="Professional video editing, color, effects and audio post-processing"
HOMEPAGE="https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"
SRC_URI="${ZIP_NAME}.zip"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
# ~amd64 only, and this is the one case where that is not a shortcut: Blackmagic
# publishes a single Linux build and it is x86_64.  ARM64 exists for macOS on
# Apple silicon, not for Linux, so there is no arm64 payload to key.
KEYWORDS="~amd64"

IUSE="video_cards_amdgpu video_cards_intel video_cards_nvidia"
RESTRICT="fetch mirror bindist strip"

QA_PREBUILT="*"

BDEPEND="
	app-arch/unzip
	dev-util/patchelf
"

# RDEPEND was not inherited on trust: it is the DT_NEEDED closure of every ELF
# surviving src_prepare (scanelf -RyBF), minus the ~470 sonames the bundle ships
# itself.  Two results are worth recording, because both are invisible in the
# ebuild text:
#
#  * media-libs/libpulse is NOT here, and its absence is deliberate.  The string
#    "libpulse" does not occur anywhere in the 7 GiB payload -- not as DT_NEEDED,
#    not as a dlopen literal.  Resolve talks to ALSA (libasound.so.2 is a real
#    DT_NEEDED); PulseAudio reaches it through ALSA like any other client.  The
#    upstream overlays list it anyway, which forces PulseAudio onto anyone
#    running plain ALSA or PipeWire.
#  * the whole CUDA stack (libcudart, libcublas, libcudnn, libcufft) is BUNDLED
#    under libs/, so video_cards_nvidia only has to supply libcuda.so.1 -- that
#    is the driver, and nothing from dev-util/nvidia-cuda-toolkit is needed.
#
# The libs that only ever appeared through files src_prepare deletes are the
# reason those deletions exist: bin/sqlite3 was the sole consumer of ncurses 5
# and readline 6, and "DaVinci Control Panels Setup/libk5crypto.so.3" the sole
# consumer of OpenSSL 1.1.  Neither version exists in the tree any more.
RDEPEND="
	app-arch/bzip2
	app-arch/xz-utils
	app-crypt/mit-krb5
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/glu
	media-libs/libglvnd
	sys-apps/dbus
	sys-apps/util-linux
	sys-devel/gcc:*[openmp]
	virtual/libcrypt:=
	virtual/libudev
	virtual/opencl
	virtual/udev
	virtual/zlib:=
	sys-libs/mtdev
	video_cards_amdgpu? ( dev-libs/rocm-opencl-runtime )
	video_cards_intel? ( dev-libs/intel-compute-runtime )
	video_cards_nvidia? ( x11-drivers/nvidia-drivers )
	x11-libs/libdrm
	x11-libs/libICE
	x11-libs/libSM
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXext
	x11-libs/libXi
	x11-libs/libXrender
	x11-libs/libXt
	x11-libs/libXtst
	x11-libs/libXxf86vm
	x11-libs/libxkbcommon[X]
	x11-libs/libxkbfile
	x11-libs/xcb-util
	x11-libs/xcb-util-cursor
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
"

# The manual route comes FIRST and stays complete on its own: bentoolkit is not a
# dependency of this package, and whoever does not have it installed may not be
# left without a way to get the archive.
pkg_nofetch() {
	einfo
	einfo "  ${ZIP_NAME}.zip is behind a registration form, so Portage cannot"
	einfo "  fetch it. Download it from:"
	einfo
	einfo "    ${HOMEPAGE}"
	einfo
	einfo "  place it in your DISTDIR directory, and re-run emerge."
	einfo
	einfo "  With app-portage/bentoolkit installed, one command does the same --"
	einfo "  it submits the form and writes the archive under the exact name this"
	einfo "  package's Manifest expects:"
	einfo
	einfo "    bentoo distfile fetch ${CATEGORY}/${PN} --version ${PV%.0}"
	einfo
	einfo "  The version there is the TWO-component one, matching the file name."
	einfo
}

src_unpack() {
	unpack "${ZIP_NAME}.zip" || die

	chmod u+x "${RUN_NAME}" || die
	"${S}/${RUN_NAME}" --appimage-extract || die
}

_is_elf() {
	[[ -f ${1} ]] || return 1
	[[ $(LC_ALL=C od -An -tx1 -N4 "${1}" 2>/dev/null) == *"7f 45 4c 46"* ]]
}

_set_rpath() {
	local rpath=${1}
	shift

	local f
	for f; do
		[[ -e ${f} ]] || continue
		_is_elf "${f}" || continue
		patchelf --force-rpath --set-rpath "${rpath}" "${f}" ||
			die "patchelf failed on ${f}"
	done
}

_has_bad_rpath() {
	local rpath
	rpath=$(patchelf --print-rpath "${1}" 2>/dev/null) || return 1

	[[ ${rpath} == *"/home/"* ||
		${rpath} == *"/persistent/"* ||
		${rpath} == *"/var/lib/jenkins/"* ||
		${rpath} == *"/xxxxxxxx"* ||
		${rpath} == *@loader_path* ||
		${rpath} == *"/lib/qt-"* ]]
}

_sanitize_bad_rpaths() {
	local root=${1}
	local rpath=${2}
	local f

	[[ -d ${root} ]] || return

	while IFS= read -r -d '' f; do
		_is_elf "${f}" || continue
		_has_bad_rpath "${f}" || continue
		_set_rpath "${rpath}" "${f}"
	done < <(find "${root}" -type f -print0)
}

_patch_desktop_file() {
	local file=${1}
	local exec=${2}
	local icon=${3}

	sed -i \
		-e "s|^Exec=.*|Exec=${exec}|" \
		-e "s|^Icon=.*|Icon=${icon}|" \
		-e "/^Path=/d" \
		"${file}" || die
}

_fperms_image() {
	local mode=${1}
	shift

	local f
	for f; do
		[[ -e ${f} ]] || continue
		fperms "${mode}" "${f#${ED}}" || die
	done
}

_newlib_ldscript() {
	local lib=${1}
	local target=${2}

	insinto "/usr/$(get_libdir)"
	newins - "${lib}" <<-EOF
		/* GNU ld script */
		GROUP ( ${EPREFIX}${target} )
	EOF
	fperms a+x "/usr/$(get_libdir)/${lib}" || die
}

src_prepare() {
	default

	local squashfs="squashfs-root"
	local install_dir="/opt/${PN}"

	chmod -R u+rwX "${squashfs}" || die

	mkdir -p "${squashfs}/panel-framework" || die
	tar -xzf "${squashfs}/share/panels/dvpanel-framework-linux-x86_64.tgz" \
		-C "${squashfs}/panel-framework" || die
	chmod -R u+rwX "${squashfs}/panel-framework" || die
	rm -f "${squashfs}/share/panels/dvpanel-framework-linux-x86_64.tgz" || die

	rm -rf "${squashfs}"/{installer*,AppRun*,CentOSUpdate} || die
	rm -f "${squashfs}/DaVinci Control Panels Setup/libk5crypto.so.3" || die
	rm -f "${squashfs}/share/DaVinciResolveInstaller.desktop" || die
	rm -f "${squashfs}/scripts/"{pre_install.sh,post_install.sh,uninstall.sh} || die
	rm -f "${squashfs}/LUT/GenLut" "${squashfs}/LUT/GenOutputLut" || die
	rm -f "${squashfs}/bin/sqlite3" || die
	if ! use video_cards_nvidia; then
		rm -f \
			"${squashfs}/BlackmagicRAWPlayer/BlackmagicRawAPI/libDecoderCUDA.so" \
			"${squashfs}/BlackmagicRAWSpeedTest/BlackmagicRawAPI/libDecoderCUDA.so" \
			"${squashfs}/libs/libDecoderCUDA.so" || die
	fi
	rm -rf \
		"${squashfs}/Onboarding/qml/Qt/labs/lottieqt" \
		"${squashfs}/Onboarding/qml/QtQml/RemoteObjects" \
		"${squashfs}/Onboarding/qml/QtQuick/Particles.2" \
		"${squashfs}/Onboarding/qml/QtQuick/Shapes" \
		"${squashfs}/Onboarding/qml/QtQuick/VirtualKeyboard" || die

	_set_rpath "\$ORIGIN/../libs:\$ORIGIN/../libs/Fusion" \
		"${squashfs}/bin/resolve"
	_set_rpath "\$ORIGIN/../libs:\$ORIGIN/../libs/Fusion" \
		"${squashfs}/Onboarding/DaVinci_Resolve_Welcome"
	_set_rpath "\$ORIGIN/lib" \
		"${squashfs}/panel-framework/libDaVinciPanelAPI.so" \
		"${squashfs}/panel-framework/libFairlightPanelAPI.so"

	patchelf --set-soname libsonyxavcenc.so \
		"${squashfs}/libs/libsonyxavcenc.so.1.1.11.68" || die

	while IFS= read -r -d '' f; do
		_set_rpath "\$ORIGIN" "${f}"
	done < <(find "${squashfs}" -type f \
		\( -name "libc++abi.so*" \
		-o -name "libgcc_s.so.1" \
		-o -name "libCrmSdk.so.*" \
		-o -name "libcrypto.so.*" \
		-o -name "libcurl.so" \
		-o -name "libsharpyuv.so.0.1.1" \
		-o -name "libssl.so.*" \
		-o -name "libwebpdecoder.so.3.1.10" \
		-o -name "libxmlsec1-openssl.so" \) -print0)

	_sanitize_bad_rpaths "${squashfs}/libs" "\$ORIGIN:\$ORIGIN/Fusion"
	_sanitize_bad_rpaths "${squashfs}/plugins" "\$ORIGIN:\$ORIGIN/../libs"
	_sanitize_bad_rpaths "${squashfs}/Onboarding" \
		"\$ORIGIN:${install_dir}/libs:${install_dir}/libs/Fusion"

	ln -s "../BlackmagicRAWPlayer/BlackmagicRawAPI" \
		"${squashfs}/bin/BlackmagicRawAPI" || die

	while IFS= read -r -d '' f; do
		sed -i "s|RESOLVE_INSTALL_LOCATION|${install_dir}|g" "${f}" || die
	done < <(find "${squashfs}/share" -type f \
		\( -name "*.desktop" -o -name "*.directory" -o -name "*.menu" \) -print0)

	_patch_desktop_file "${squashfs}/share/DaVinciResolve.desktop" \
		"davinci-resolve %u" "davinci-resolve"
	_patch_desktop_file "${squashfs}/share/DaVinciResolveCaptureLogs.desktop" \
		"davinci-resolve-capture-logs" "davinci-resolve"
	_patch_desktop_file "${squashfs}/share/DaVinciControlPanelsSetup.desktop" \
		"davinci-control-panels-setup" "davinci-resolve-panels-setup"
	_patch_desktop_file "${squashfs}/share/blackmagicraw-player.desktop" \
		"blackmagicraw-player %f" "blackmagicraw-player"
	_patch_desktop_file "${squashfs}/share/blackmagicraw-speedtest.desktop" \
		"blackmagicraw-speedtest %f" "blackmagicraw-speedtest"

	sed -i 's#Categories=Video#Categories=AudioVideo;Video;#' \
		"${squashfs}/share/blackmagicraw-player.desktop" \
		"${squashfs}/share/blackmagicraw-speedtest.desktop" || die
	echo "StartupWMClass=resolve" >> "${squashfs}/share/DaVinciResolve.desktop" || die

	cat > "${squashfs}/share/etc/udev/rules.d/75-sdx.rules" <<-EOF || die
	SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="096e", MODE="0666"
	EOF
}

src_install() {
	local install_dir="/opt/${PN}"
	local app_dir="${ED}${install_dir}"
	local iconsrc="${app_dir}/graphics"

	dodir "${install_dir}"
	cp -a squashfs-root/. "${app_dir}/" || die

	local f
	while IFS= read -r -d '' f; do
		_fperms_image 0755 "${f}"
	done < <(find "${app_dir}" -type d -print0)

	while IFS= read -r -d '' f; do
		_is_elf "${f}" || continue
		_fperms_image 0755 "${f}"
	done < <(find "${app_dir}" -type f -print0)

	_fperms_image 0755 \
		"${app_dir}/bin/run_bmdpaneld" \
		"${app_dir}/libs/libc++.so" \
		"${app_dir}/scripts/script.checkfirmware" \
		"${app_dir}/scripts/script.getlogs.v4" \
		"${app_dir}/scripts/script.halt" \
		"${app_dir}/scripts/script.kill" \
		"${app_dir}/scripts/script.reboot" \
		"${app_dir}/scripts/script.start" \
		"${app_dir}/scripts/script.update"

	local runtime_dir
	for runtime_dir in \
		"Apple Immersive/Calibration" \
		.crashreport \
		.LUT \
		configs \
		DolbyVision \
		GPUCache \
		logs
	do
		keepdir "${install_dir}/${runtime_dir}"
	done

	# Directories resolve writes to at RUNTIME, as an ordinary user.  The install
	# image is root-owned 0755, so each one has to be made writable here or it is
	# simply not writable at all.  Four independent sources, no overlap:
	#
	#  * "Immersive" is the one that made 21.1 unusable.  bin/resolve mkdir()s
	#    ${install_dir}/Immersive/Canon/STMap during startup and ABORTS with
	#    "Failed to create application support directories" when that returns
	#    EACCES.  Measured, not guessed: an LD_PRELOAD mkdir(2) tracer over the
	#    installed image names that mkdir and no other as the failing one, and the
	#    abort disappears once the directory exists writable.  Note the name -- it
	#    is NOT the "Apple Immersive" below, which is a different directory.
	#  * easyDCP, LUT and .license are what the vendor scripts/post_install.sh
	#    creates 0775 and chowns to the installing user (create_config_files), and
	#    "Apple Immersive" is its set_folder_permissions "chmod a+w".  src_prepare
	#    deletes that script, which is why those permissions are reproduced here.
	#  * /var/BlackmagicDesign/DaVinci Resolve is the installer's "Common Data
	#    Dir", shared by every user of the machine.  The path is hardcoded in
	#    bin/resolve, which creates ".migrated" inside it, so it cannot be moved
	#    under /opt.
	#  * Extras and Fairlight are absent from the payload AND from post_install.sh,
	#    so nothing above predicts them -- they were read off a running 21.1.0.0017
	#    on 2026-09-19.  Extras is the Download Manager's package store: failing to
	#    create it is not degraded, it aborts the whole subsystem
	#    ("DDM: failed to create storage dir ... (Permission denied)" ->
	#    "DDM init failed"), so Blackmagic Cloud and downloadable extras are gone
	#    for the session.  Fairlight logs "mkdir failed ... (errno 13)" three times
	#    and then comes up anyway, which is exactly why it went unnoticed.
	#
	# 0777 rather than a group: upstream chowns to the single user running the
	# installer, which a package cannot do -- there is no such user at merge time,
	# and the machine may well have several.  Upstream itself uses 0777 for the
	# /var directory.
	local writable_dir
	for writable_dir in \
		"Apple Immersive" \
		.license \
		easyDCP \
		Extras \
		Fairlight \
		Immersive
	do
		keepdir "${install_dir}/${writable_dir}"
		fperms 0777 "${install_dir}/${writable_dir}"
	done

	# LUT ships in the payload, so it needs the mode and not the directory.
	fperms 0777 "${install_dir}/LUT"

	keepdir "/var/BlackmagicDesign/DaVinci Resolve"
	fperms 0777 "/var/BlackmagicDesign/DaVinci Resolve"

	cp "${app_dir}/share/"{default-config.dat,log-conf.xml} "${app_dir}/configs/" || die
	cp "${app_dir}/share/default_cm_config.bin" "${app_dir}/DolbyVision/" || die

	dosym "${install_dir}/bin/resolve" "/usr/bin/${PN}"
	dosym "${install_dir}/scripts/script.getlogs.v4" "/usr/bin/davinci-resolve-capture-logs"
	dosym "${install_dir}/DaVinci Control Panels Setup/DaVinci Control Panels Setup" \
		"/usr/bin/davinci-control-panels-setup"
	dosym "${install_dir}/BlackmagicRAWPlayer/BlackmagicRAWPlayer" \
		"/usr/bin/blackmagicraw-player"
	dosym "${install_dir}/BlackmagicRAWSpeedTest/BlackmagicRAWSpeedTest" \
		"/usr/bin/blackmagicraw-speedtest"
	_newlib_ldscript libDaVinciPanelAPI.so \
		"${install_dir}/panel-framework/libDaVinciPanelAPI.so"
	_newlib_ldscript libFairlightPanelAPI.so \
		"${install_dir}/panel-framework/libFairlightPanelAPI.so"

	newmenu "${app_dir}/share/DaVinciResolve.desktop" \
		com.blackmagicdesign.resolve.desktop
	newmenu "${app_dir}/share/DaVinciResolveCaptureLogs.desktop" \
		com.blackmagicdesign.resolve-CaptureLogs.desktop
	newmenu "${app_dir}/share/DaVinciControlPanelsSetup.desktop" \
		com.blackmagicdesign.resolve-Panels.desktop
	newmenu "${app_dir}/share/blackmagicraw-player.desktop" \
		com.blackmagicdesign.rawplayer.desktop
	newmenu "${app_dir}/share/blackmagicraw-speedtest.desktop" \
		com.blackmagicdesign.rawspeedtest.desktop

	newicon -s 64 "${iconsrc}/DV_Resolve.png" davinci-resolve.png
	newicon -s 64 "${iconsrc}/DV_Panels.png" davinci-resolve-panels-setup.png

	newicon -s 48 "${iconsrc}/blackmagicraw-player_48x48_apps.png" blackmagicraw-player.png
	newicon -s 48 "${iconsrc}/blackmagicraw-speedtest_48x48_apps.png" blackmagicraw-speedtest.png

	newicon -s 256 "${iconsrc}/blackmagicraw-player_256x256_apps.png" blackmagicraw-player.png
	newicon -s 256 "${iconsrc}/blackmagicraw-speedtest_256x256_apps.png" blackmagicraw-speedtest.png

	# -c mimetypes is load-bearing, not tidiness.  These nine names are the seven
	# MIME types resolve.xml and blackmagicraw.xml declare, with "/" rewritten as
	# "-" per the icon-naming spec, and a mimetype icon is only ever looked up in
	# the mimetypes context.  newicon defaults to apps/, where nothing consults
	# them -- verified on the installed image: without this the files land in
	# hicolor/*/apps/ and no file manager shows an icon for a .braw or .drp.
	# Upstream already names the braw sources "..._mimetypes.png".
	newicon -s 64 -c mimetypes "${iconsrc}/DV_ResolveBin.png" application-x-resolvebin.png
	newicon -s 64 -c mimetypes "${iconsrc}/DV_ResolveProj.png" application-x-resolveproj.png
	newicon -s 64 -c mimetypes "${iconsrc}/DV_ResolveTimeline.png" application-x-resolvetimeline.png
	newicon -s 64 -c mimetypes "${iconsrc}/DV_ServerAccess.png" application-x-resolvedbkey.png
	newicon -s 64 -c mimetypes "${iconsrc}/DV_TemplateBundle.png" application-x-resolvetemplatebundle.png

	newicon -s 48 -c mimetypes "${iconsrc}/application-x-braw-clip_48x48_mimetypes.png" \
		application-x-braw-clip.png
	newicon -s 48 -c mimetypes "${iconsrc}/application-x-braw-sidecar_48x48_mimetypes.png" \
		application-x-braw-sidecar.png

	newicon -s 256 -c mimetypes "${iconsrc}/application-x-braw-clip_256x256_mimetypes.png" \
		application-x-braw-clip.png
	newicon -s 256 -c mimetypes "${iconsrc}/application-x-braw-sidecar_256x256_mimetypes.png" \
		application-x-braw-sidecar.png

	insinto /usr/share/mime/packages
	doins "${app_dir}/share/resolve.xml" "${app_dir}/share/blackmagicraw.xml"

	udev_dorules "${app_dir}/share/etc/udev/rules.d/"*.rules

	dodir "/usr/share/licenses/${PN}"
	dosym "${install_dir}/docs/License.html" "/usr/share/licenses/${PN}/License.html"
}

pkg_postinst() {
	xdg_pkg_postinst
	udev_reload

	elog "DaVinci Resolve requires a working OpenCL runtime and GPU driver."
	elog "Install the vendor GPU stack matching your hardware if Resolve cannot detect OpenCL."

	# Measured on 2026-09-19, NVIDIA-only host with four ICDs installed: GPUDetect
	# calls clGetPlatformIDs, the ICD loader dlopen()s EVERY file in
	# /etc/OpenCL/vendors, and the static constructor of libhsa-runtime64.so.1
	# (pulled in by libamdocl64.so) binds std::filesystem::path::_M_split_cmpts()
	# to the copy exported by the bundled libs/libProResRAW.so -- an old statically
	# linked libstdc++ that is already in the global scope.  SIGSEGV, milliseconds
	# in, with no error message of any kind.
	#
	# There is no ebuild-side fix: the rpaths are correct and the colliding symbol
	# comes out of a proprietary blob we cannot relink.  Narrowing the ICD set is
	# the user's call because it is hardware-dependent -- a machine with both an
	# AMD and an NVIDIA GPU genuinely needs both ICDs -- so this is documented
	# rather than wrapped.
	elog
	elog "If Resolve dies with no message right after startup, an unrelated OpenCL"
	elog "ICD is likely crashing inside it. The loader opens every file in"
	elog "/etc/OpenCL/vendors, and a runtime for a GPU you do not have is enough."
	elog "Confirm it by restricting the set to the ICD of your own GPU:"
	elog
	elog "    mkdir -p ~/.config/resolve-icd"
	elog "    cp /etc/OpenCL/vendors/<your-vendor>.icd ~/.config/resolve-icd/"
	elog "    OCL_ICD_VENDORS=~/.config/resolve-icd davinci-resolve"
	elog
}

pkg_postrm() {
	xdg_pkg_postrm
	udev_reload
}
