FROM ubuntu:24.04 AS build

ARG USERNAME=builder
ARG USER_UID=7000
ARG USER_GID=${USER_UID}

RUN apt update -y && \
    apt install build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget patch \
    android-sdk-libsparse-utils -y && \
    groupadd --gid "${USER_GID}" "${USERNAME}" && \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home "${USERNAME}"

USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN git clone -b 24.10 https://github.com/liudf0716/chawrt.git

WORKDIR /home/${USERNAME}/chawrt

RUN echo '# CONFIG_REALTEK_PHY_HWMON is not set' >> target/linux/generic/config-6.6
RUN ./scripts/feeds update -a && \
    ./scripts/feeds install -a
COPY --chown=${USERNAME}:${USERNAME} configs/thunder-onecloud.config .config
COPY --chmod=0755 scripts/package-onecloud-image.sh /usr/local/bin/package-onecloud-image

RUN make defconfig

RUN make download -j8

RUN make V=s -j1

RUN set -eu; \
    boot_image="$(find build_dir -type f -name '*thunder-onecloud-ext4-emmc.img.boot' -print -quit)"; \
    rootfs_image="$(find build_dir -type f -name 'root.ext4' -print -quit)"; \
    test -n "$boot_image"; \
    test -n "$rootfs_image"; \
    package-onecloud-image \
        bin/targets/amlogic/meson8b/thunder-onecloud-usb-burning.img \
        "$boot_image" \
        "$rootfs_image"

FROM scratch AS firmware

COPY --from=build /home/builder/chawrt/bin/targets/amlogic/meson8b/ /

FROM build AS final

