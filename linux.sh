RUMPKERN_CPPFLAGS="-D__linux__"

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

