include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openbox
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

# Use a dummy source - we download pre-built binaries in Build/Prepare
PKG_SOURCE:=dummy
PKG_SOURCE_URL:=https://github.com/liandu2024/Open-Box.git
PKG_HASH:=skip

PKG_LICENSE:=Proprietary
PKG_MAINTAINER:=liandu2024

# Build flags
PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-openbox
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Open-Box transparent proxy panel
  URL:=https://github.com/liandu2024/Open-Box
  DEPENDS:=+kmod-tun +kmod-nft-queue +kmod-nft-nat +kmod-veth +ip-full +ca-bundle +libcap +libcap-bin
  PKGARCH:=x86_64 aarch64
endef

define Package/luci-app-openbox/description
  Open-Box all-in-one transparent proxy for OpenWrt / Debian / Ubuntu / Docker.
  Proprietary core components; third-party components retain their original licenses.
endef

# Download pre-built release package from GitHub Releases
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	cd $(PKG_BUILD_DIR) && \
	case "$(ARCH)" in \
		x86_64) OB_ARCH="x64" ;; \
		aarch64) OB_ARCH="arm64" ;; \
	esac && \
	VERSION=$$(curl -sfL --connect-timeout 10 --max-time 30 \
		"https://api.github.com/repos/liandu2024/Open-Box/releases/latest" 2>/dev/null | \
		grep '"tag_name"' | head -1 | cut -d'"' -f4) && \
	[ -n "$$VERSION" ] || VERSION="v0.1.346" && \
	echo "Downloading Open-Box $$VERSION for $$OB_ARCH..." && \
	curl -fL --connect-timeout 15 --speed-limit 1024 --speed-time 60 \
		"https://github.com/liandu2024/Open-Box/releases/download/$$VERSION/open-box-$$VERSION-linux-$$OB_ARCH.tar.gz" \
		-o openbox.tar.gz 2>/dev/null || \
	curl -fL --connect-timeout 15 --speed-limit 1024 --speed-time 60 \
		"https://gh-proxy.com/https://github.com/liandu2024/Open-Box/releases/download/$$VERSION/open-box-$$VERSION-linux-$$OB_ARCH.tar.gz" \
		-o openbox.tar.gz && \
	tar -xzf openbox.tar.gz && \
	rm -f openbox.tar.gz
endef

define Build/Compile
	# No compilation needed - using pre-built binaries
	true
endef

define Package/luci-app-openbox/install
	$(INSTALL_DIR) $(1)/opt/open-box
	$(CP) $(PKG_BUILD_DIR)/* $(1)/opt/open-box/

	# Install init.d scripts
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/init.d/openbox $(1)/etc/init.d/openbox
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/init.d/openbox-panel $(1)/etc/init.d/openbox-panel

	# Install LuCI static resources
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/openbox
	$(CP) $(PKG_BUILD_DIR)/openwrt/www/luci-static/resources/view/openbox/* $(1)/www/luci-static/resources/view/openbox/

	# Install LuCI menu
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/openwrt/usr/share/luci/menu.d/luci-app-openbox.json $(1)/usr/share/luci/menu.d/

	# Install LuCI ACL
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/openwrt/usr/share/rpcd/acl.d/luci-app-openbox.json $(1)/usr/share/rpcd/acl.d/

	# Install open-box command link
	$(INSTALL_DIR) $(1)/usr/bin
	$(LN_S) /opt/open-box/openwrt/bin/open-box $(1)/usr/bin/open-box

	# Create data directory for persistence
	$(INSTALL_DIR) $(1)/opt/open-box/data

	# Set proper permissions
	chmod -R 755 $(1)/opt/open-box
	chmod 755 $(1)/etc/init.d/openbox $(1)/etc/init.d/openbox-panel
endef

$(eval $(call BuildPackage,luci-app-openbox))