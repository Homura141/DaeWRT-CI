# === 高功率 BDF 覆盖（由 WRT-CORE.yml 追加） ===
define Build/Compile
	$(CP) $(TOPDIR)/../files/board-2.bin $(PKG_BUILD_DIR)/board-redmi_ax6.ipq8074
endef
