cmd_/nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder/.install := /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/uapi/linux/byteorder big_endian.h little_endian.h; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/linux/byteorder ; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/generated/uapi/linux/byteorder ; for F in ; do echo "\#include <asm-generic/$$F>" > /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder/$$F; done; touch /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/linux/byteorder/.install
