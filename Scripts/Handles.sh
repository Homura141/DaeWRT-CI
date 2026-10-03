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
# BDF 进固件 squashfs（重置后保留）：双保险
# ============================================================
echo ">>> Adding BDF to firmware squashfs..."

BDF_SRC="$GITHUB_WORKSPACE/files/board-2.bin"
[ -f "$BDF_SRC" ] || BDF_SRC="$GITHUB_WORKSPACE/files/board-redmi_ax6.ipq8074"

if [ ! -f "$BDF_SRC" ]; then
    echo "  ERROR: BDF source not found"
    exit 1
fi
echo "  BDF source MD5:"
md5sum "$BDF_SRC"

# ---------- 保险 1：base-files/files/ + init.d 脚本 ----------
BASE_FILES_DIR="$WRT_ROOT/package/base-files/files"
mkdir -p "$BASE_FILES_DIR/etc/init.d"
mkdir -p "$BASE_FILES_DIR/etc/rc.d"

cp "$BDF_SRC" "$BASE_FILES_DIR/etc/board-2.bin.highpower"

cat > "$BASE_FILES_DIR/etc/init.d/replace-bdf" << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99

start() {
    if [ -f /etc/board-2.bin.highpower ]; then
        cp /etc/board-2.bin.highpower /lib/firmware/ath11k/IPQ8074/hw2.0/board-2.bin
        logger -t replace-bdf "High power BDF applied"
    fi
}

boot() {
    start
}
INITEOF

chmod +x "$BASE_FILES_DIR/etc/init.d/replace-bdf"
ln -sf ../init.d/replace-bdf "$BASE_FILES_DIR/etc/rc.d/S99replace-bdf"

echo "  [1/2] Placed in base-files/files/"
md5sum "$BASE_FILES_DIR/etc/board-2.bin.highpower"

# 清 base-files stamp，强制重新安装
find "$WRT_ROOT/staging_dir" -name ".base-files*" -type f -delete 2>/dev/null
find "$WRT_ROOT/staging_dir" -path "*stamp*" -name "*base-files*" -delete 2>/dev/null
echo "  base-files stamps cleared"

# ---------- 保险 2：wrt/files/ rootfs overlay ----------
WRT_FILES_DIR="$WRT_ROOT/files"
mkdir -p "$WRT_FILES_DIR/lib/firmware/ath11k/IPQ8074/hw2.0"
cp "$BDF_SRC" "$WRT_FILES_DIR/lib/firmware/ath11k/IPQ8074/hw2.0/board-2.bin"
echo "  [2/2] Placed in wrt/files/ rootfs overlay"
md5sum "$WRT_FILES_DIR/lib/firmware/ath11k/IPQ8074/hw2.0/board-2.bin"

echo ">>> Handles.sh done"
