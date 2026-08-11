/* Copyright 1999-2026 Gentoo Authors
 * Distributed under the terms of the GNU General Public License v2
 *
 * Stub for the two libsystemd entry points www-client/orion-bin needs.
 *
 * The prebuilt WebKit in Orion is linked against libsystemd.so.0 purely for
 * release logging (sd_journal_send). On a system without systemd the library
 * does not exist, so the browser would fail to start; dropping the DT_NEEDED
 * entry instead would leave the calls unresolved and abort the process the
 * first time anything logged.
 *
 * These stubs discard the message and report success, which is what a
 * journal-less system would effectively do anyway. They are installed into a
 * private directory reachable only through orion-bin's own RPATH, so a real
 * libsystemd is never shadowed for anything else.
 */

int sd_journal_send(const char *format, ...);
int sd_journal_send_with_location(const char *file, const char *line,
	const char *func, const char *format, ...);

int
sd_journal_send(const char *format, ...)
{
	(void) format;
	return 0;
}

int
sd_journal_send_with_location(const char *file, const char *line,
	const char *func, const char *format, ...)
{
	(void) file;
	(void) line;
	(void) func;
	(void) format;
	return 0;
}
