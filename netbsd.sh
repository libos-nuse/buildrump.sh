
checkcheckout ()
{

	[ -x "${SRCDIR}/build.sh" ] || die "Cannot find ${SRCDIR}/build.sh!"

	[ ! -z "${TARBALLMODE}" ] && return

	if ! ${BRDIR}/checkout.sh checkcheckout ${SRCDIR} \
	    && ! ${TITANMODE}; then
		die 'revision mismatch, run checkout (or -H to override)'
	fi
}


#
# Create tools and wrappers.  This step needs to be run at least once.
# The routine is run if the "tools" argument is specified.
#
# You might want to skip it because:
# 1) iteration speed on a slow-ish host
# 2) making manual modifications to the tools for testing and avoiding
#    the script nuking them on the next iteration
#
# external toolchain links are created in the format that
# build.sh expects.
#
maketools ()
{

	checkcheckout

	probeld
	probenm
	probear
	${HAVECXX} && probecxx

	cd ${OBJDIR}

	# Create mk.conf.  Create it under a temp name first so as to
	# not affect the tool build with its contents
	MKCONF="${BRTOOLDIR}/mk.conf.building"
	> "${MKCONF}"
	mkconf_final="${BRTOOLDIR}/mk.conf"
	> ${mkconf_final}

	${KERNONLY} || probe_rumpuserbits

	checkcompiler

	#
	# Create external toolchain wrappers.
	mkdir -p ${BRTOOLDIR}/bin || die "cannot create ${BRTOOLDIR}/bin"
	for x in CC AR NM OBJCOPY; do
		maketoolwrapper true $x
	done
	for x in AS CXX LD OBJDUMP RANLIB READELF SIZE STRINGS STRIP; do
		maketoolwrapper false $x
	done

	# create a cpp wrapper, but run it via cc -E
	if [ "${CC_FLAVOR}" = 'clang' ]; then
		cppname=clang-cpp
	else
		cppname=cpp
	fi
	tname=${BRTOOLDIR}/bin/${MACHINE_GNU_ARCH}--${RUMPKERNEL}${TOOLABI}-${cppname}
	printf '#!/bin/sh\n\nexec %s -E -x c "${@}"\n' ${CC} > ${tname}
	chmod 755 ${tname}

	for x in 1 2 3; do
		! ${HOST_CC} -o ${BRTOOLDIR}/bin/brprintmetainfo \
		    -DSTATHACK${x} ${BRDIR}/brlib/utils/printmetainfo.c \
		    >/dev/null 2>&1 || break
	done
	[ -x ${BRTOOLDIR}/bin/brprintmetainfo ] \
	    || die failed to build brprintmetainfo

	${HOST_CC} -o ${BRTOOLDIR}/bin/brrealpath \
	    ${BRDIR}/brlib/utils/realpath.c || die failed to build brrealpath

	cat >> "${MKCONF}" << EOF
BUILDRUMP_IMACROS=${BRIMACROS}
.if \${BUILDRUMP_SYSROOT:Uno} == "yes"
BUILDRUMP_CPPFLAGS=--sysroot=\${BUILDRUMP_STAGE}
.else
BUILDRUMP_CPPFLAGS=-I\${BUILDRUMP_STAGE}/usr/include
.endif
BUILDRUMP_CPPFLAGS+=${EXTRA_CPPFLAGS}
LIBDO.pthread=_external
INSTPRIV=-U
AFLAGS+=-Wa,--noexecstack
MKPROFILE=no
MKARZERO=no
USE_SSP=no
MKHTML=no
MKCATPAGES=yes
MKNLS=no
RUMP_NPF_TESTING?=no
RUMPRUN=yes
EOF

	if ! ${KERNONLY}; then
	    # queue.h is not available on all systems, but we need it for
	    # the hypervisor build.  So, we make it available in tooldir.
	    mkdir -p ${BRTOOLDIR}/compat/include/sys \
		|| die create ${BRTOOLDIR}/compat/include/sys
	    cp -p ${SRCDIR}/sys/sys/queue.h ${BRTOOLDIR}/compat/include/sys
	    echo "CPPFLAGS+=-I${BRTOOLDIR}/compat/include" >> "${MKCONF}"
	fi

	printoneconfig 'Cmd' "SRCDIR" "${SRCDIR}"
	printoneconfig 'Cmd' "DESTDIR" "${DESTDIR}"
	printoneconfig 'Cmd' "OBJDIR" "${OBJDIR}"
	printoneconfig 'Cmd' "BRTOOLDIR" "${BRTOOLDIR}"

	appendmkconf 'Cmd' "${RUMP_DIAGNOSTIC:-}" "RUMP_DIAGNOSTIC"
	appendmkconf 'Cmd' "${RUMP_DEBUG:-}" "RUMP_DEBUG"
	appendmkconf 'Cmd' "${RUMP_LOCKDEBUG:-}" "RUMP_LOCKDEBUG"
	appendmkconf 'Cmd' "${DBG:-}" "DBG"
	printoneconfig 'Cmd' "make -j[num]" "-j ${JNUM}"

	if ${KERNONLY}; then
		appendmkconf Cmd yes RUMPKERN_ONLY
	fi

	if ${KERNONLY} && ! cppdefines __NetBSD__; then
		appendmkconf 'Cmd' '-D__NetBSD__' 'CPPFLAGS' +
		appendmkconf 'Probe' "${RUMPKERN_UNDEF}" 'CPPFLAGS' +
	else
		appendmkconf 'Probe' "${RUMPKERN_UNDEF}" "RUMPKERN_UNDEF"
	fi
	appendmkconf 'Probe' "${RUMP_CURLWP:-}" 'RUMP_CURLWP' ?
	appendmkconf 'Probe' "${CTASSERT:-}" "CPPFLAGS" +
	appendmkconf 'Probe' "${RUMP_VIRTIF:-}" "RUMP_VIRTIF"
	appendmkconf 'Probe' "${EXTRA_CWARNFLAGS}" "CWARNFLAGS" +
	appendmkconf 'Probe' "${EXTRA_LDFLAGS}" "LDFLAGS" +
	appendmkconf 'Probe' "${EXTRA_CPPFLAGS}" "CPPFLAGS" +
	appendmkconf 'Probe' "${EXTRA_CFLAGS}" "BUILDRUMP_CFLAGS"
	appendmkconf 'Probe' "${EXTRA_AFLAGS}" "BUILDRUMP_AFLAGS"
	_tmpvar=
	for x in ${EXTRA_RUMPUSER} ${EXTRA_RUMPCOMMON}; do
		appendvar _tmpvar "${x#-l}"
	done
	appendmkconf 'Probe' "${_tmpvar}" "RUMPUSER_EXTERNAL_DPLIBS" +
	_tmpvar=
	for x in ${EXTRA_RUMPCLIENT} ${EXTRA_RUMPCOMMON}; do
		appendvar _tmpvar "${x#-l}"
	done
	appendmkconf 'Probe' "${_tmpvar}" "RUMPCLIENT_EXTERNAL_DPLIBS" +
	appendmkconf 'Probe' "${LDSCRIPT:-}" "RUMP_LDSCRIPT"
	appendmkconf 'Probe' "${SHLIB_MKMAP:-}" 'SHLIB_MKMAP'
	appendmkconf 'Probe' "${SHLIB_WARNTEXTREL:-}" "SHLIB_WARNTEXTREL"
	appendmkconf 'Probe' "${MKSTATICLIB:-}"  "MKSTATICLIB"
	appendmkconf 'Probe' "${MKPIC:-}"  "MKPIC"
	appendmkconf 'Probe' "${MKSOFTFLOAT:-}"  "MKSOFTFLOAT"
	appendmkconf 'Probe' $(${HAVECXX} && echo yes || echo no) _BUILDRUMP_CXX

	printoneconfig 'Mode' "${TARBALLMODE}" 'yes'

	rm -f ${BRTOOLDIR}/toolchain-conf.mk
	exec 3>&1 1>${BRTOOLDIR}/toolchain-conf.mk
	printf 'BUILDRUMP_TOOL_CFLAGS=%s\n' "${EXTRA_CFLAGS}"
	printf 'BUILDRUMP_TOOL_CXXFLAGS=%s\n' "${EXTRA_CFLAGS}"
	printf 'BUILDRUMP_TOOL_CPPFLAGS=-D__NetBSD__ %s %s\n' \
	       "${EXTRA_CPPFLAGS}" "${RUMPKERN_UNDEF}"
	exec 1>&3 3>&-

	chkcrt begins
	chkcrt ends
	chkcrt i
	chkcrt n

	# add vars from env last (so that they can be used for overriding)
	cat >> "${MKCONF}" << EOF
CPPFLAGS+=\${BUILDRUMP_CPPFLAGS}
CFLAGS+=\${BUILDRUMP_CFLAGS}
AFLAGS+=\${BUILDRUMP_AFLAGS}
LDFLAGS+=\${BUILDRUMP_LDFLAGS}
EOF

	if ! ${KERNONLY}; then
	    echo >> "${MKCONF}"
	    cat >> "${MKCONF}" << EOF
# Support for NetBSD Makefiles which use <bsd.prog.mk>
# It's mostly a question of erasing dependencies that we don't
# expect to see
.ifdef PROG
LIBCRT0=
LIBCRTBEGIN=
LIBCRTEND=
LIBCRTI=
LIBC=

LDFLAGS+= -L\${BUILDRUMP_STAGE}/usr/lib -Wl,-R${DESTDIR}/lib
LDADD+= ${EXTRA_RUMPCOMMON} ${EXTRA_RUMPUSER} ${EXTRA_RUMPCLIENT}
EOF
	    appendmkconf 'Probe' "${LD_AS_NEEDED}" LDFLAGS +
	    echo '.endif # PROG' >> "${MKCONF}"
	fi

	# skip the zlib tests run by "make tools", since we don't need zlib
	# and it's only required by one tools autoconf script.  Of course,
	# the fun bit is that autoconf wants to use -lz internally,
	# so we provide some foo which macquerades as libz.a.
	export ac_cv_header_zlib_h=yes
	echo 'int gzdopen(int); int gzdopen(int v) { return 0; }' > fakezlib.c
	${HOST_CC} -o libz.a -c fakezlib.c
	rm -f fakezlib.c

	# Run build.sh.  Use some defaults.
	# The html pages would be nice, but result in too many broken
	# links, since they assume the whole NetBSD man page set to be present.
	cd ${SRCDIR}

	# create user-usable wrapper script
	makemake ${BRTOOLDIR}/rumpmake ${BRTOOLDIR}/dest makewrapper

	# create wrapper script to be used during buildrump.sh, plus tools
	makemake ${RUMPMAKE} ${OBJDIR}/dest.stage tools

	# Just set no MSI in imacros universally now.
	# Need to:
	#   a) migrate more defines there
	#   b) set no MSI only when necessary
	printf '#define NO_PCI_MSI_MSIX\n' > ${BRIMACROS}.building

	unset ac_cv_header_zlib_h

	# tool build done.  flip mk.conf name so that it gets picked up
	omkconf="${MKCONF}"
	MKCONF="${mkconf_final}"
	mv "${omkconf}" "${MKCONF}"
	unset omkconf mkconf_final

	# set new BRIMACROS only if the contents change (avoids
	# full rebuild, since every file in the rump kernel depends on the
	# contents of BRIMACROS
	if ! diff "${BRIMACROS}" "${BRIMACROS}.building" > /dev/null 2>&1; then
	    mv "${BRIMACROS}.building" "${BRIMACROS}"
	fi
}


# create the makefiles used for building
mkmakefile ()
{

	makefile=$1
	shift
	exec 3>&1 1>${makefile}
	printf '# GENERATED FILE, MIGHT I SUGGEST NOT EDITING?\n'
	printf 'SUBDIR='
	for dir in $*; do
		case ${dir} in
		/*)
			printf ' %s' ${dir}
			;;
		*)
			printf ' %s' ${SRCDIR}/${dir}
			;;
		esac
	done

	printf '\n.include <bsd.subdir.mk>\n'
	exec 1>&3 3>&-
}

domake ()
{

	mkfile=${1}; shift
	mktarget=${1}; shift

	[ ! -x ${RUMPMAKE} ] && die "No rumpmake (${RUMPMAKE}). Forgot tools?"
	${RUMPMAKE} $* -j ${JNUM} -f ${mkfile} ${mktarget}
	[ $? -eq 0 ] || die "make $mkfile $mktarget"
}

makebuild ()
{

	checkcheckout

	# ensure we're in SRCDIR, in case "tools" wasn't run
	cd ${SRCDIR}

	targets="obj includes dependall install"

	#
	# Building takes 4 passes, just like when
	# building NetBSD the regular way.  The passes are:
	# 1) obj
	# 2) includes
	# 3) dependall
	# 4) install
	#

	DIRS_first='lib/librumpuser'
	DIRS_second='lib/librump'
	DIRS_third="lib/librumpdev lib/librumpnet lib/librumpvfs
	    sys/rump/dev sys/rump/fs sys/rump/kern sys/rump/net
	    sys/rump/include ${BRDIR}/brlib"

	# sys/rump/share was added to ${SRCDIR} 11/2014
	[ -d ${SRCDIR}/sys/rump/share ] \
	    && appendvar DIRS_second ${SRCDIR}/sys/rump/share

	if [ ${MACHINE} = "i386" -o ${MACHINE} = "amd64" \
	     -o ${MACHINE#evbearm} != ${MACHINE} \
	     -o ${MACHINE#evbppc} != ${MACHINE} ]; then
		DIRS_emul=sys/rump/kern/lib/libsys_linux
	fi
	${SYS_SUNOS} && appendvar DIRS_emul sys/rump/kern/lib/libsys_sunos
	if ${HIJACK}; then
		DIRS_final="lib/librumphijack"
	else
		DIRS_final=
	fi

	DIRS_third="${DIRS_third} ${DIRS_emul}"

	if ${KERNONLY}; then
		mkmakefile ${OBJDIR}/Makefile.all \
		    sys/rump ${DIRS_emul} ${BRDIR}/brlib
	else
		DIRS_third="lib/librumpclient ${DIRS_third}"

		mkmakefile ${OBJDIR}/Makefile.first ${DIRS_first}
		mkmakefile ${OBJDIR}/Makefile.second ${DIRS_second}
		mkmakefile ${OBJDIR}/Makefile.third ${DIRS_third}
		mkmakefile ${OBJDIR}/Makefile.final ${DIRS_final}
		mkmakefile ${OBJDIR}/Makefile.all \
		    ${DIRS_first} ${DIRS_second} ${DIRS_third} ${DIRS_final}
	fi

	# try to minimize the amount of domake invocations.  this makes a
	# difference especially on systems with a large number of slow cores
	for target in ${targets}; do
		if [ ${target} = "dependall" ] && ! ${KERNONLY}; then
			domake ${OBJDIR}/Makefile.first ${target}
			domake ${OBJDIR}/Makefile.second ${target}
			domake ${OBJDIR}/Makefile.third ${target}
			domake ${OBJDIR}/Makefile.final ${target}
		else
			domake ${OBJDIR}/Makefile.all ${target}
		fi
	done

	if ! ${KERNONLY}; then
		mkmakefile ${OBJDIR}/Makefile.utils \
		    usr.bin/rump_server usr.bin/rump_allserver \
		    usr.bin/rump_wmd
		for target in ${targets}; do
			domake ${OBJDIR}/Makefile.utils ${target}
		done
	fi
}

makeinstall ()
{

	# ensure we run this in a directory that does not have a
	# Makefile that could confuse rumpmake
	stage=$(cd ${BRTOOLDIR} && ${RUMPMAKE} -V '${BUILDRUMP_STAGE}')
	(cd ${stage}/usr ; tar -cf - .) | (cd ${DESTDIR} ; tar -xf -)

}

#
# install kernel headers.
# Note: Do _NOT_ do this unless you want to install a
#       full rump kernel application stack
#  
makekernelheaders ()
{

	dodirs=$(cd ${SRCDIR}/sys && \
	    ${RUMPMAKE} -V '${SUBDIR:Narch:Nmodules:Ncompat:Nnetnatm}' includes)
	# missing some architectures
	appendvar dodirs arch/amd64/include arch/i386/include arch/x86/include
	appendvar dodirs arch/arm/include arch/arm/include/arm32
	appendvar dodirs arch/evbarm64/include arch/aarch64/include
	appendvar dodirs arch/evbppc/include arch/powerpc/include
	appendvar dodirs arch/evbmips/include arch/mips/include
	appendvar dodirs arch/riscv/include
	for dir in ${dodirs}; do
		(cd ${SRCDIR}/sys/${dir} && ${RUMPMAKE} obj)
		(cd ${SRCDIR}/sys/${dir} && ${RUMPMAKE} includes)
	done
	# create machine symlink
	(cd ${SRCDIR}/sys/arch && ${RUMPMAKE} NOSUBDIR=1 includes)
}

maketests ()
{

	if ${KERNONLY}; then
		diagout 'Kernel-only; skipping tests (no hypervisor)'
	else
		. ${BRDIR}/tests/testrump.sh
		alltests
	fi
}
