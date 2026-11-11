# SNMP support through Net-SNMP. vcpkg has no net-snmp port, so the library is
# built from source in a dedicated CI job (build_netsnmp.bat) and its install
# tree is pointed to here with SNMPINCDIR and SNMPLIBDIR. Leave both unset and
# the proxy builds without SNMP, exactly as before: the SNMP objects are always
# compiled, but with HAVE_NETSNMP undefined they collapse to reporting the
# checks unsupported.
#
# The library is the static netsnmp.lib configured with --linktype=static, so
# its net-snmp-config.h leaves NETSNMP_IMPORT empty and no DLL import applies.

!	IF "$(SNMPINCDIR)" != "" || "$(SNMPLIBDIR)" != ""

!		IF "$(SNMPINCDIR)" == ""
!			ERROR Please specify directory containing Net-SNMP header files (e. g. SNMPINCDIR="\somepath\include").
!		ENDIF

!		IF "$(SNMPLIBDIR)" == ""
!			ERROR Please specify directory containing Net-SNMP libraries (e. g. SNMPLIBDIR="\somepath\lib").
!		ENDIF

!		IF !EXISTS("$(SNMPINCDIR)\net-snmp\net-snmp-config.h")
!			ERROR SNMPINCDIR "$(SNMPINCDIR)" cannot find "$(SNMPINCDIR)\net-snmp\net-snmp-config.h"
!		ENDIF

!		IF !EXISTS("$(SNMPLIBDIR)\netsnmp.lib")
!			ERROR SNMPLIBDIR "$(SNMPLIBDIR)" cannot find "$(SNMPLIBDIR)\netsnmp.lib"
!		ENDIF

# Zabbix's configure detects the strong SHA-2 auth protocols with a link test and
# defines HAVE_NETSNMP_STRONG_AUTH (m4/netsnmp.m4). This port uses a hand-written
# config.h, so that detection never runs. The Net-SNMP built by build_netsnmp.bat
# (5.9.x with --with-ssl) provides usmHMAC192SHA256AuthProtocol and friends, so
# define it here. Without it checks_snmp.c compiles out the SHA224/256/384/512
# cases and reports "Unsupported authentication protocol [3]" for SHA256.
#
# HAVE_NETSNMP_STRONG_PRIV (AES192/256) is deliberately left undefined: Net-SNMP
# only exposes usmAES192PrivProtocol/usmAES256PrivProtocol when configured with
# --enable-blumenthal-aes, which build_netsnmp.bat does not pass.
CFLAGS =	$(CFLAGS) /DHAVE_NETSNMP /DHAVE_NETSNMP_STRONG_AUTH
INCS =	$(INCS) /I "$(SNMPINCDIR)"
LIBS =	$(LIBS) "$(SNMPLIBDIR)\netsnmp.lib"

!	ENDIF
