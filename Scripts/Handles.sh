#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/$WRT_DIR/package/"

#预置HomeProxy数据
if [ -d *"homeproxy"* ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	rm -rf ./$HP_PATH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

	cd .. && rm -rf ./$HP_RULE/

	cd $PKG_PATH && echo "homeproxy date has been updated!"
fi

#修改argon主题字体和颜色
if [ -d "$PKG_PATH/luci-theme-argon" ]; then
	echo " "
	if sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" \
		"$PKG_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"; then
		echo "theme-argon has been fixed!"
	else
		echo "theme-argon fix failed; continuing!"
	fi
fi

#修改aurora菜单式样
if [ -d "$PKG_PATH/luci-app-aurora-config" ]; then
	echo " "
	if find "$PKG_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec \
		sed -i "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +; then
		echo "theme-aurora has been fixed!"
	else
		echo "theme-aurora fix failed; continuing!"
	fi
fi

#修改mini-diskmanager菜单位置
if [ -d "$PKG_PATH/luci-app-mini-diskmanager" ]; then
	echo " "
	if sed -i "s/services/system/g" \
		"$PKG_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"; then
		echo "mini-diskmanager has been fixed!"
	else
		echo "mini-diskmanager fix failed; continuing!"
	fi
fi

#修复TailScale配置文件冲突
FEEDS_PACKAGES="$PKG_PATH/../feeds/packages"
TS_FILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/tailscale/Makefile' -print -quit 2>/dev/null)"
if [ -f "$TS_FILE" ]; then
	echo " "
	if sed -i '/\/files/d' "$TS_FILE"; then
		echo "tailscale has been fixed!"
	else
		echo "tailscale fix failed; continuing!"
	fi
fi

#修复Rust编译失败
RUST_FILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/rust/Makefile' -print -quit 2>/dev/null)"
if [ -f "$RUST_FILE" ]; then
	echo " "
	if sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"; then
		echo "rust has been fixed!"
	else
		echo "rust fix failed; continuing!"
	fi
fi

# ============================================================
# 内核 eBPF/BTF 选项在 Config/IPQ807X-WIFI.txt 里设置
# ============================================================
echo ">>> Kernel options are set in Config/IPQ807X-WIFI.txt"

# ============================================================
# 修复 apk 包下载
# ============================================================
echo ">>> Fixing apk package download..."
WRT_ROOT="$GITHUB_WORKSPACE/$WRT_DIR"
APK_MK="$WRT_ROOT/package/system/apk/Makefile"
if [ -f "$APK_MK" ]; then
    sed -i 's|https://gitlab.alpinelinux.org/alpine/apk-tools.git|https://github.com/alpinelinux/apk-tools.git|' "$APK_MK"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$APK_MK"
    if grep -q "^PKG_SOURCE_URL" "$APK_MK"; then
        sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/alpinelinux/apk-tools.git|' "$APK_MK"
    fi
    echo "apk Makefile patched"
fi

# ============================================================
# 强制禁用 daed
# ============================================================
echo ">>> Disabling luci-app-daed..."
CONFIG_FILE="$GITHUB_WORKSPACE/$WRT_DIR/.config"
if [ -f "$CONFIG_FILE" ]; then
    sed -i 's/^CONFIG_PACKAGE_luci-app-daed=y/CONFIG_PACKAGE_luci-app-daed=n/' "$CONFIG_FILE"
    echo "  luci-app-daed disabled"
fi

# ============================================================
# 应用 ath11k 内存泄漏修复补丁
# ============================================================
echo ">>> Applying ath11k memory leak fix patch..."

PATCH_SRC="$GITHUB_WORKSPACE/patches/911-ath11k-reduce-dma-buffer-to-save-memory.patch"
PATCH_DEST_DIR="$WRT_ROOT/package/kernel/mac80211/patches/ath11k"

if [ -f "$PATCH_SRC" ]; then
    mkdir -p "$PATCH_DEST_DIR"
    cp "$PATCH_SRC" "$PATCH_DEST_DIR/"
    echo "  Patch copied to mac80211"

    # 清理 mac80211 的编译 stamp，强制重新编译
    find "$WRT_ROOT/build_dir" -maxdepth 3 -type d -name "mac80211-*" -exec rm -rf {} + 2>/dev/null
    find "$WRT_ROOT/staging_dir" -name ".mac80211*" -type f -delete 2>/dev/null
    echo "  mac80211 stamps cleared"
else
    echo "  WARNING: Patch file not found at $PATCH_SRC"
fi

# ============================================================
# 直接替换 BDF（进 squashfs，开机即 29dBm）
# ============================================================
echo ">>> Setting up direct BDF replacement..."

BDF_SRC="$GITHUB_WORKSPACE/files/board-2.bin"
[ -f "$BDF_SRC" ] || BDF_SRC="$GITHUB_WORKSPACE/files/board-redmi_ax6.ipq8074"

if [ ! -f "$BDF_SRC" ]; then
    echo "  ERROR: BDF source not found"
    exit 1
fi
echo "  BDF source MD5:"
md5sum "$BDF_SRC"

# 1. 把 BDF 放进 base-files 的驱动路径
BASE_FW_DIR="$WRT_ROOT/package/base-files/files/lib/firmware/ath11k/IPQ8074/hw2.0"
mkdir -p "$BASE_FW_DIR"
cp "$BDF_SRC" "$BASE_FW_DIR/board-2.bin"
echo "  [1/2] Placed in base-files: $BASE_FW_DIR/board-2.bin"
md5sum "$BASE_FW_DIR/board-2.bin"

# 2. 禁用 ipq-wifi 的 BDF 安装
IPQ_WIFI_MK="$WRT_ROOT/package/firmware/ipq-wifi/Makefile"
if [ -f "$IPQ_WIFI_MK" ]; then
    sed -i 's|\$(INSTALL_DATA) \$(1) \$(2)/lib/firmware/ath11k/\$(3)/board-2.bin|true|' "$IPQ_WIFI_MK"
    sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/' "$IPQ_WIFI_MK"
    echo "  [2/2] Disabled ipq-wifi BDF install"
fi

# 清 stamp，强制重新安装
find "$WRT_ROOT/staging_dir" -name ".base-files*" -type f -delete 2>/dev/null
find "$WRT_ROOT/staging_dir" -name ".ipq-wifi*" -type f -delete 2>/dev/null
echo "  Stamps cleared"

# ============================================================
# 内存优化 sysctl 配置（首次启动自动生效）
# ============================================================
echo ">>> Adding memory optimization sysctl..."

BASE_FILES_DIR="$WRT_ROOT/package/base-files/files"
mkdir -p "$BASE_FILES_DIR/etc/sysctl.d"

cat > "$BASE_FILES_DIR/etc/sysctl.d/99-memory-optimize.conf" << 'SYSCTLEOF'
# conntrack 表（默认 65536，改小到 16384 省内存）
net.netfilter.nf_conntrack_max=16384

# 加快 conntrack 超时回收
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_udp_timeout=30

# 减小网络缓冲
net.core.rmem_max=262144
net.core.wmem_max=262144
net.core.rmem_default=65536
net.core.wmem_default=65536
net.core.netdev_max_backlog=2048

# TCP 内存限制
net.ipv4.tcp_rmem=4096 131072 262144
net.ipv4.tcp_wmem=4096 65536 262144
SYSCTLEOF

echo "  sysctl config added"

echo ">>> Handles.sh done"
