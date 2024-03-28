# Fraise-toolchain
Pre-compiled binaries for compiling [Fraise](https://github.com/MetaluNet/Fraise) firmwares

All files in bin/ are tracked with git-lfs.

To upload a new build to deken, do:

`toolchain-upload.sh OS(linux/windows/macos) ARCH(i386/amd64/arm32/arm64) [test]`

Example:

`toolchain-upload.sh linux amd64`

If the 3rd arg is `test`, the deken package will be built but not uploaded to deken.
