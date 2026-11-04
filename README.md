# Zabbix proxy for Windows

**A native Windows build of the Zabbix proxy, packaged as an MSI.**

Zabbix ships its proxy for Linux only. If the site you need to monitor has a
Windows server and nothing else, you have been choosing between a Linux VM you
must now maintain, WSL, or no proxy at all. This project builds the official
Zabbix proxy source for Windows, as a regular Windows service.

[![Build](../../actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)

> Unofficial community build. Not affiliated with or endorsed by Zabbix SIA.
> "Zabbix" is a trademark of Zabbix SIA.

## Quick start

Download the MSI from the [latest release](../../releases/latest), then from an
elevated prompt:

```powershell
msiexec /i zabbix_proxy-7.4.16-x64.msi SERVER=zabbix.example.com HOSTNAME=proxy-site-a /qn
Start-Service "Zabbix Proxy"
```

Declare `proxy-site-a` as an active proxy on your Zabbix server, assign hosts
to it, done. The configuration lands in `%ProgramFiles%\Zabbix Proxy`, the log
and the SQLite buffer in `%ProgramData%\Zabbix Proxy`. Upgrades keep your edited
`zabbix_proxy.conf`.

The binary is not code-signed yet: check it against `SHA256SUMS` in the release.

## What works

| Feature | Status |
|---|---|
| Active and passive proxy, SQLite buffer | Yes |
| Zabbix agent checks, simple checks, trapper, HTTP agent | Yes |
| ICMP ping (native Windows ICMP API, no fping, no elevation) | Yes |
| SNMP v1 / v2c / v3 authPriv (SHA + AES) | Yes, numeric OIDs (no MIBs shipped) |
| SNMP traps (bundled `snmptrapd` service) | Yes |
| SSH, ODBC, LDAP checks | Yes |
| Preprocessing, including JavaScript | Yes |
| Runtime control (`-R config_cache_reload`, log levels) | Yes |
| VMware monitoring | Built, not yet tested against a live vCenter |
| IPMI | No, reported as unsupported |

Tested in CI on Windows Server 2022 and 2025: install, service start and stop,
upgrade, end-to-end collection against a stand-in server, and the full proxy
under AddressSanitizer.

The operator guide, with every log message the port can emit, is in
[`overlay/build/win32/OPERATING_proxy`](overlay/build/win32/OPERATING_proxy).

## How it works

The proxy source is upstream Zabbix, unchanged except where Windows needs it.
On Unix the proxy forks one process per worker; here each worker is a thread
of a single process. That one decision drives most of the port:

- shared memory becomes ordinary heap memory, and locks map onto Windows
  synchronisation primitives;
- the internal IPC moves from Unix sockets to loopback TCP;
- ICMP ping talks to the Windows ICMP driver instead of fping;
- the SQLite buffer runs in WAL mode so the syncer threads do not block each
  other.

## Repository layout

This repository does not copy the Zabbix source. Like a Linux distribution
package, it holds the pinned upstream version and the changes on top of it:

```
UPSTREAM_VERSION   Zabbix release this port applies to
overlay/           files the port adds (Windows code, nmake files, MSI, tests)
patches/           changes to upstream files, one patch per topic, in `series` order
scripts/
  prepare.sh       upstream tag + overlay + patches -> ./zabbix
  prepare.ps1      the same, from PowerShell (uses Git for Windows' bash)
  refresh-patches.sh   turn edits made in ./zabbix back into overlay/ and patches/
  rebase.sh        carry the port onto another Zabbix release, three-way, with a report
.github/workflows/ build, test, package, release
```

Read `patches/` to see exactly what the port changes in Zabbix.

## Building

```bash
scripts/prepare.sh        # ./zabbix: Zabbix 7.4.16 with the port applied
```

Then follow [`overlay/build/win32/README_proxy`](overlay/build/win32/README_proxy)
(Visual Studio Build Tools, vcpkg, nmake, WiX). The CI workflow is the
reference build and runs the same steps.

## Contributing and maintaining

Work in the prepared tree, then fold the changes back:

```bash
scripts/prepare.sh
# edit, build, test in ./zabbix
scripts/refresh-patches.sh
git diff patches/ overlay/    # review, commit
```

A change to an upstream file goes to the patch that already owns that file.
A file no patch owns goes to `patches/9999-unsorted.patch` until you move it.

Moving to a new Zabbix release: `scripts/rebase.sh <version>` applies every
patch three-way and lists the conflicts. Resolve them in `./zabbix`, write the
version to `UPSTREAM_VERSION`, run `refresh-patches.sh`. A weekly workflow
(`upstream-watch.yml`) runs the same check against the newest 7.4 and 8.0
releases, so a breaking upstream change shows up before release day.

Releases: push a tag `v<zabbix version>-<n>` (for example `v7.4.16-3`). CI
publishes the MSI once every job passes.

Issues and pull requests are welcome, especially test reports from real
deployments (VMware, large SNMP fleets, many hosts per proxy).

## License

AGPL-3.0, like Zabbix itself. See [LICENSE](LICENSE).
