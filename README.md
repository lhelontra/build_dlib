# build_dlib

Multiarch cross compiling environment for dlib

## Edit tweaks like flags to enable or disable features, toolchain url, and others
see configuration file examples in: configs/

## Cross-compilation
For example, let's demonstrates how to cross-compile to raspberry pi using gcc linaro.
Make you sure added arm architecture, see how to adds in debian flavors:
```shell
dpkg --add-architecture armhf
apt-get update
```
```shell
./build_dlib.sh -c configs/rpi_linaro.conf --build
# will be asked to download the dependencies, we recommended dependencies downloads locally. The script will configure pkg-config so that dlib's cmake will detect selected libraries in config.
# If you selected, for example, backend lapack, the script no ask if you wants download dependencies, use:
./build_dlib.sh -c configs/rpi.conf --dw-cross-deps "liblapack-dev=armhf"

# For next build
./build_dlib.sh -c configs/rpi.conf --clean # copy debian package before execute this command.
./build_dlib.sh -c configs/odroidc2.conf --build
```

## License
The file LICENSE applies to other files in this repository. I want to stress that a majority of the lines of code found in the guide of this repository was created by others. If any of those original authors want more prominent attribution, please contact me and we can figure out how to make it acceptable.
