include $(TOPDIR)/rules.mk
LUCI_TITLE:=PassWall node DNS assistant
LUCI_DEPENDS:=+luci-compat +luci-lib-jsonc +luci-lib-nixio +luci-base
LUCI_PKGARCH:=all
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
include $(TOPDIR)/feeds/luci/luci.mk
