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
# daed 所需的内核 eBPF/BTF 选项 + hostapd 编译错误修复
# ============================================================
echo ">>> Applying daed kernel options and hostapd fix..."
SOURCE_DIR="$GITHUB_WORKSPACE/$WRT_DIR"
if [ -d "$SOURCE_DIR" ]; then
    (
        cd "$SOURCE_DIR" || exit 1

        # 1. 开启 eBPF/BTF 内核选项（dae 运行前提）
        TARGET_CONFIG=$(find target/linux/qualcommax -maxdepth 1 -name "config-*" | head -1)
        if [ -n "$TARGET_CONFIG" ]; then
            scripts/config --file "$TARGET_CONFIG" \
                --enable BPF_SYSCALL \
                --enable BPF_JIT \
                --enable DEBUG_INFO_BTF \
                --enable BPF_EVENTS \
                --enable CGROUP_BPF \
                --enable NET_CLS_BPF \
                --enable NET_SCH_INGRESS \
                --enable KALLSYMS \
                --enable KALLSYMS_ALL \
                --enable TCP_CONG_BBR \
                --enable NET_SCH_FQ
            echo "eBPF/BTF options enabled in $TARGET_CONFIG"
        else
            echo "WARNING: qualcommax target config not found"
        fi

        # 2. 修复 hostapd he_mu_edca 编译错误（注释掉报错行）
        HOSTAPD_SRC="package/network/services/hostapd/src/ap/hostapd.c"
        if [ -f "$HOSTAPD_SRC" ]; then
            sed -i 's/hapd->iface->conf->he_mu_edca.he_qos_info &= 0xfff0;/\/\* & \*\//' "$HOSTAPD_SRC"
            echo "hostapd.c patched"
        else
            echo "WARNING: hostapd.c not found at $HOSTAPD_SRC"
        fi

        # 3. 替换为高功率 BDF（Redmi AX6，来自 QSDK 12.5）
        echo ">>> Replacing Redmi AX6 board-2.bin with high-power version..."
        BDF_SRC="$GITHUB_WORKSPACE/files/board-redmi_ax6.ipq8074"
        BDF_DEST=$(find "$SOURCE_DIR/package/firmware" -name "board-redmi_ax6.ipq8074" 2>/dev/null | head -n 1)
        if [ -f "$BDF_SRC" ] && [ -n "$BDF_DEST" ]; then
            echo "Source: $BDF_SRC"
            echo "Target: $BDF_DEST"
            cp "$BDF_DEST" "${BDF_DEST}.bak"
            cp "$BDF_SRC" "$BDF_DEST"
            echo "board-2.bin replaced successfully"
        else
            echo "WARNING: BDF source or target not found"
            echo "  BDF_SRC=$BDF_SRC"
            echo "  BDF_DEST=$BDF_DEST"
        fi
    )
else
    echo "WARNING: source directory not found at $SOURCE_DIR"
fi
