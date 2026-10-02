# === 高功率 BDF 覆盖（由 WRT-CORE.yml 追加） ===
define Package/ipq-wifi-redmi_ax6/install-overlay
	$(INSTALL_DIR) $(1)/lib/firmware/ath11k/IPQ8074/hw2.0/
	$(INSTALL_DATA) $(TOPDIR)/../files/board-2.bin $(1)/lib/firmware/ath11k/IPQ8074/hw2.0/board-2.bin
endef
