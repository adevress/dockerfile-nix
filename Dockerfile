FROM busybox

# copy and install nix
COPY nix-1.8-x86_64-linux /tmp/nix-1.8-x86_64-linux

RUN cd /tmp/nix-1.8-x86_64-linux/ \
	&& sh install-docker \
	&& cd / \
	&& rm -rf /tmp/nix-1.8-x86_64-linux/

ENV HOME /home/default
ENV ENV /home/default/.nix-profile/etc/profile.d/nix.sh

WORKDIR /home/default
USER default

