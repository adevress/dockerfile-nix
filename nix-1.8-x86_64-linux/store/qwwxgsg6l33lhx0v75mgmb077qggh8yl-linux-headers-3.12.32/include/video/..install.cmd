cmd_/nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video/.install := /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/uapi/video edid.h sisfb.h uvesafb.h; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/video ; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/generated/uapi/video ; for F in ; do echo "\#include <asm-generic/$$F>" > /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video/$$F; done; touch /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/video/.install