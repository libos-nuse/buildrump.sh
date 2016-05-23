checkcheckout ()
{

	[ -f "${LKLSRC}/arch/lkl/Makefile" ] || \
	    die "Cannot find ${LKLSRC}/arch/lkl/Makefile!"

	[ ! -z "${TARBALLMODE}" ] && return

	if ! ${BRDIR}/checkout.sh checkcheckout ${LKLSRC} \
	    && ! ${TITANMODE}; then
		die 'revision mismatch, run checkout (or -H to override)'
	fi
}

maketools_ ()
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
	tname=${BRTOOLDIR}/bin/${MACHINE_GNU_ARCH}--netbsd${TOOLABI}-${cppname}
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
	printf 'BUILDRUMP_TOOL_CPPFLAGS=-D__Linux__ %s %s\n' \
	       "${EXTRA_CPPFLAGS}" "${RUMPKERN_UNDEF}"
	exec 1>&3 3>&-

	# XXX: make rumpmake from src-netbsd
	cd ${SRCDIR}
	# create user-usable wrapper script
	makemake ${BRTOOLDIR}/rumpmake ${BRTOOLDIR}/dest makewrapper

	# create wrapper script to be used during buildrump.sh, plus tools
	makemake ${RUMPMAKE} ${OBJDIR}/dest.stage tools

	CC=${BRTOOLDIR}/bin/${MACHINE_GNU_ARCH}--${RUMPKERNEL}${TOOLABI}-gcc

}

makebuild ()
{
	echo "=== Linux build LKLSRC=${LKLSRC} ==="
	cd ${LKLSRC}
	VERBOSE="V=0"
	if [ ${NOISE} -gt 1 ] ; then
		VERBOSE="V=1"
	fi

	CROSS=$(${CC} -dumpmachine)
	if [ ${CROSS} = "$(gcc -dumpmachine)" ]
	then
		CROSS=
	else
		CROSS=${CROSS}-
	fi

	set -e
	set -x
	export RUMP_PREFIX=${RUMPSRC}/sys/rump
	export RUMP_INCLUDE=${RUMPSRC}/sys/rump/include
	mkdir -p ${OBJDIR}/lkl-linux

	cd tools/lkl
	rm -f ${OBJDIR}/lkl-linux/tools/lkl/lib/lkl.o
	make CROSS_COMPILE=${CROSS} rumprun=yes -j ${JNUM} ${VERBOSE} O=${OBJDIR}/lkl-linux/

	cd ../../
	make CROSS_COMPILE=${CROSS} headers_install ARCH=lkl O=${RROBJ}/rumptools/dest

	set +e
	set +x
}

makeinstall ()
{

	# XXX for app-tools
	mkdir -p ${DESTDIR}/bin/
	# XXX: RROBJ is rumprun obj so, should not be used in buildrump...
	mkdir -p ${RROBJ}/rumptools/dest/usr/include/rumprun

	export RUMP_PREFIX=${RUMPSRC}/sys/rump
	export RUMP_INCLUDE=${RUMPSRC}/sys/rump/include
	make rumprun=yes headers_install libraries_install DESTDIR=${RROBJ}/rumptools/dest\
	     -C ${LKLSRC}/tools/lkl/ O=${OBJDIR}/lkl-linux/

}

#
# install kernel headers.
# Note: Do _NOT_ do this unless you want to install a
#       full rump kernel application stack
#
makekernelheaders ()
{
	return
}

maketests ()
{
	printf 'Linux libos test ... '
	make -C ${LKLSRC}/tools/lkl test || die Linux libos failed
}

