include $(TOPDIR)/rules.mk

PKG_NAME:=relaywatch
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=Relay Watch Team <maintainers@example.com>

include $(INCLUDE_DIR)/package.mk

define Package/relaywatch
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Wireless relay watchdog daemon
  DEPENDS:=+relayd +iwinfo +jsonfilter +uclient-fetch +libubus +ubus +ubox
endef

define Package/relaywatch/description
 relaywatchd monitors wireless STA links built via relayd bridging.
 It performs periodic connectivity checks, switches among candidate
 uplinks, and exposes state for LuCI integrations.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/relaywatch/conffiles
/etc/config/relaywatch
endef

define Package/relaywatch/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/relaywatch $(1)/etc/config/relaywatch

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/relaywatch $(1)/etc/init.d/relaywatch

	$(INSTALL_DIR) $(1)/etc/hotplug.d/wireless
	$(INSTALL_BIN) ./files/etc/hotplug.d/wireless/99-relaywatch $(1)/etc/hotplug.d/wireless/99-relaywatch

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/relaywatchd $(1)/usr/sbin/relaywatchd
endef

$(eval $(call BuildPackage,relaywatch))
