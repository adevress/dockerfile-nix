cmd_/nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi/.install := /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/uapi/scsi scsi_bsg_fc.h scsi_netlink.h scsi_netlink_fc.h; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/scsi ; /bin/sh scripts/headers_install.sh /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi /tmp/nix-build-linux-headers-3.12.32.drv-0/linux-3.12.32/include/generated/uapi/scsi ; for F in ; do echo "\#include <asm-generic/$$F>" > /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi/$$F; done; touch /nix/store/qwwxgsg6l33lhx0v75mgmb077qggh8yl-linux-headers-3.12.32/include/scsi/.install
