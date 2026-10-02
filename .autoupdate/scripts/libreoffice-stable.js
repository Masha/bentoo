// Newest RELEASED LibreOffice build of one release line, as a 4-segment
// version ("26.8.1.2"). Evaluated by bentoolkit's "script" parser against
//   <mirror>/libreoffice/stable/#<X.Y>
// The fragment names the release line; the page itself is never reloaded.
// src/ is resolved relative to the loaded stable/ page, so any full TDF mirror
// works: the records point at ftp.fau.de because the master,
// download.documentfoundation.org, timed out or reset repeatedly on 2026-10-02.
// The script parser has no fallback_url, so the mirror IS the single source.
//
// Two listings, because neither answers alone:
//   stable/        lists a release only once it is PROMOTED, but names it
//                  with three segments (26.8.1/) -- no build number;
//   src/X.Y.Z/     carries the one build that became the release
//                  (libreoffice-26.8.0.3.tar.xz), i.e. the 4th segment.
// downloadarchive old/, which the records used before, lists every build
// directory including RCs, so it proposed 26.8.1.1 (RC1) as a final version.
//
// Throws rather than returning a guess: a failed probe is visible, a wrong
// version gets applied.
(async () => {
	const series = decodeURIComponent(location.hash.slice(1));
	if (!/^\d+\.\d+$/.test(series)) {
		throw new Error(`series fragment must be X.Y, got "${series}"`);
	}
	const esc = series.replace(/\./g, "\\.");
	const dirRe = new RegExp(`^(${esc}\\.\\d+)/$`);
	const cmp = (a, b) => {
		const x = a.split(".").map(Number), y = b.split(".").map(Number);
		for (let i = 0; i < Math.max(x.length, y.length); i++) {
			if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0);
		}
		return 0;
	};
	const hrefs = [...document.querySelectorAll("a[href]")]
		.map(a => a.getAttribute("href") || "");
	// No X.Y.Z/ directory of ANY line means the listing never loaded (timeout,
	// reset, error page), not that the series is gone -- say so, or a mirror
	// hiccup reads like a release line that vanished.
	if (!hrefs.some(h => /^\d+\.\d+\.\d+\/$/.test(h))) {
		throw new Error(`stable/ listing unavailable: no release directories at all (${location.href})`);
	}
	const released = hrefs
		.map(h => h.match(dirRe))
		.filter(Boolean)
		.map(m => m[1])
		.sort(cmp);
	if (released.length === 0) {
		throw new Error(`stable/ lists no ${series}.x release`);
	}
	const v = released[released.length - 1];
	const res = await fetch(new URL(`../src/${v}/`, location.href));
	if (!res.ok) throw new Error(`src/${v}/ answered HTTP ${res.status}`);
	const body = await res.text();
	const vesc = v.replace(/\./g, "\\.");
	const builds = [...body.matchAll(new RegExp(`libreoffice-${vesc}\\.(\\d+)\\.tar\\.xz"`, "g"))]
		.map(m => Number(m[1]));
	if (builds.length === 0) {
		throw new Error(`src/${v}/ holds no libreoffice-${v}.N.tar.xz`);
	}
	return `${v}.${Math.max(...builds)}`;
})()
