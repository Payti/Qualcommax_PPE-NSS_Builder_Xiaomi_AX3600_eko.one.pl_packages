# Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages

### Prebuilt OpenWrt firmware with Qualcomm PPE-NSS hardware offload for Xiaomi AX3600 (with eko.one.pl packages & English + Polish LuCI)

[![Build PPE-NSS](https://img.shields.io/github/actions/workflow/status/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/build-ppe-nss.yml?branch=main&style=flat-square&logo=github&label=Build%20PPE-NSS)](https://github.com/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/actions/workflows/build-ppe-nss.yml)
[![License](https://img.shields.io/github/license/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages?style=flat-square&label=License)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages?style=flat-square&label=Last%20Commit)](https://github.com/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/commits/main)
[![Releases](https://img.shields.io/github/v/release/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages?include_prereleases&style=flat-square&label=Latest%20Release)](https://github.com/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/releases)

OpenWrt sysupgrade images with **PPE and NSS hardware offload** (NAT, PPPoE,
VLAN, SQM, bridge, multicast and Wi-Fi) dedicated to the **Xiaomi AX3600**
(`qualcommax/ipq807x`), extended with **eko.one.pl** packages (`ekooneplstat`,
`ekooneplconfigs`, `sysinfo`, `luci-app-ekooneplstat`) and full Polish LuCI
translations (`luci-i18n-*-pl`).

The wired traffic (routing, NAT, PPPoE, VLAN, bridging, multicast snooping and
SQM) runs in the PPE, the packet engine in the SoC's switch, through OpenWrt's
upstream `qca_edma`/`qca_ppe` drivers and the kernel's own offload interfaces.
The Wi-Fi data path of the SoC radios runs on the NSS cores through
`kmod-nss-wifi-drv`: no ECM, no NSS qdiscs and no legacy vendor NSS host driver.
They are built automatically by GitHub Actions from the `ppe-nss` branch of
[openwrt-ppe-nss](https://github.com/JuliusBairaktaris/openwrt-ppe-nss); the
NSS firmware comes from
[nss-packages](https://github.com/JuliusBairaktaris/nss-packages) (`edma-nss`
branch), and additional packages come from
[obsy/packages](https://github.com/obsy/packages) (eko.one.pl).

> [!NOTE]
> For builds using pure kernel PPE flowtable offload without NSS Wi-Fi cores,
> see the sister repository:
> [Payti/Qualcommax_PPE_Builder_Xiaomi_AX3600_eko.one.pl_packages](https://github.com/Payti/Qualcommax_PPE_Builder_Xiaomi_AX3600_eko.one.pl_packages).

Background and design are described in the upstream
[wiki](https://github.com/JuliusBairaktaris/openwrt-ppe-nss/wiki), starting
with [PPE and NSS Wi-Fi Offload](https://github.com/JuliusBairaktaris/openwrt-ppe-nss/wiki/PPE-and-NSS-Wi-Fi-Offload).

## Install

Download `ppe-nss-...-xiaomi_ax3600-squashfs-sysupgrade.bin` from the
[Releases page](https://github.com/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/releases)
and flash it from LuCI (System -> Backup / Flash Firmware) or over SSH:

```sh
sysupgrade -n /tmp/ppe-nss-openwrt-qualcommax-ipq807x-xiaomi_ax3600-squashfs-sysupgrade.bin
```

There is no factory image. The device must already run OpenWrt; install stock
OpenWrt first using its [device page](https://openwrt.org/toh/xiaomi/ax3600).

| Release | NSS Firmware | Use it for |
|---|---|---|
| `ppe-nss-*` | **12.5** (`NSS.FW.12.5-210-HK.R`) + **11.4.0.5** | **Default (Unified image).** Carries both NSS firmware lines and boots **12.5** by default for Router / AP / WDS setups. For 802.11s mesh (which requires 11.4.0.5), switch at runtime with:<br>`uci set nss-wifi.general.firmware=11.4; uci commit nss-wifi; reboot` |
| `ppe-nss-mesh-*` | **11.4.0.5** | Earlier mesh builds on 11.4. No longer built separately: the `ppe-nss` images now carry both firmware lines. |

<details>
<summary>Devices built: Xiaomi AX3600 (IPQ8071A)</summary>

| Device | Target | RAM Profile | Notes |
|---|---|---|---|
| **Xiaomi AX3600** | `qualcommax/ipq807x` | 512 MB (`CONFIG_IPQ_MEM_PROFILE_512=y`) | Includes eko.one.pl packages, Polish LuCI, wireless defaults and PPE-QoS / SQM templates |

</details>

## Offload on and off

The wired offload uses the `fw4` flowtable, enabled on first boot (Network ->
Firewall -> Hardware flow offloading). Check active hardware flows in PPE with:

```sh
grep -c HW_OFFLOAD /proc/net/nf_conntrack
```

The NSS Wi-Fi offload (`kmod-nss-wifi-drv`) is on by default. Turn it off with:

```sh
uci set nss-wifi.general.offload='0'; uci commit nss-wifi; reboot
```

To switch between NSS firmware **12.5** (default) and **11.4** (for 802.11s mesh):

```sh
uci set nss-wifi.general.firmware='11.4'; uci commit nss-wifi; reboot
```

While the offload starts, the service keeps a marker in `/etc/nss-wifi.pending`
and removes it two minutes later. A boot that hangs leaves the marker, and the
next boot stays on the host Wi-Fi path until it is deleted. `logread -e nss-wifi`
shows the bring-up.

## Coming from edma-nss or pure ppe

Upgrade with a normal sysupgrade; settings may be kept. See the upstream
[migration page](https://github.com/JuliusBairaktaris/openwrt-ppe-nss/wiki/Migrating-from-edma-nss):

- Turn hardware flow offloading on in Network -> Firewall if upgrading from `edma-nss`.
- The legacy `nss` and `nssqos` configs are no longer read.
- On the Xiaomi AX3600 image the `sqm.wan` section uses `hw_ppe.qos`.
- Set up queue classifiers under **Network -> PPE QoS** (`luci-app-qca-ppe-qos`).

## What ships

| Area | Packages |
|---|---|
| **Routing, NAT** | PPE through the `fw4` flowtable: IPv4/IPv6, NAT, PPPoE, 802.1Q VLAN, DS-Lite, MAP, WireGuard, GRE, VXLAN, L2TP |
| **Bridge, multicast** | PPE through switchdev, IGMP/MLD snooping, kernel multicast routing enabled + `igmpproxy` |
| **SQM & QoS** | PPE shaper through `tc` qdisc offload: `hw_ppe.qos` in `sqm-scripts`, `luci-app-sqm`, `qca-ppe-qos`, `luci-app-qca-ppe-qos` (with PL translation), `dcb`, `tc-full`, `ethtool-full`, `devlink` |
| **Wi-Fi** | `kmod-nss-wifi-drv` + `ath11k-firmware-ipq8074` (NSS Wi-Fi data path on by default, carries both NSS FW 12.5 and 11.4), `kmod-ath10k-ct-smallbuffers` (IoT radio), full `wpad-mbedtls`, `usteer`, `mesh11sd` |
| **eko.one.pl & LuCI** | `ekooneplconfigs`, `ekooneplstat`, `luci-app-ekooneplstat`, `sysinfo`, `owut`, `luci-mod-dashboard`, `luci-app-adblock`, `luci-app-ddns`, `luci-app-nlbwmon`, `luci-app-vnstat2`, `luci-app-statistics`, `luci-app-ttyd`, `luci-app-upnp`, `luci-app-wol`, `luci-app-wifischedule`, `luci-app-commands`, full Polish language pack (`CONFIG_LUCI_LANG_pl=y`) |
| **Base & Diagnostics** | Dropbear, mbedTLS (`apk-mbedtls`, `libustream-mbedtls`), LuCI over HTTPS, BCP38, `ppe-help`, `kmod-ramoops` (`/root/pstore`), `mc`, `htop`, `bmon`, `nano`, `iperf3`, `curl`, `qca-ssdk-shell` |
| **Toolchain** | GCC 15, Binutils 2.46, mold, LTO, PIE/SSP/FORTIFY_SOURCE=3/RELRO |

All compiled `.apk` packages from the build are also archived into
`compiled_packages.tar.gz` and attached to each GitHub Release.

## Build it yourself

Fork this repo and run the **Build PPE-NSS** workflow in GitHub Actions, or
build locally:

```sh
git clone --branch ppe-nss https://github.com/JuliusBairaktaris/openwrt-ppe-nss openwrt
git clone https://github.com/Payti/Qualcommax_PPE-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages builder
cd openwrt
OPENWRT_DIR="$PWD" BUILDER_REPO="$PWD/../builder" DEVICE="xiaomi_ax3600" VARIANT="ppe-nss" RUN_FEEDS_IN_PREPARE=1 bash ../builder/scripts/prepare-build.sh
make defconfig && make -j"$(nproc)"
```

> [!IMPORTANT]
> `ppe-nss` is rebased regularly, `git pull` does not update it automatically. Use:
>
> ```sh
> git fetch origin && git reset --hard origin/ppe-nss
> ./scripts/feeds update -a && ./scripts/feeds install -a
> make defconfig
> ```

[docs/CUSTOMIZE.md](docs/CUSTOMIZE.md) covers build options and overlays.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes the CI pipeline.

## Acknowledgements

- [JuliusBairaktaris](https://github.com/JuliusBairaktaris) for the
  [openwrt-ppe-nss](https://github.com/JuliusBairaktaris/openwrt-ppe-nss) tree
  and [Qualcommax_NSS_Builder](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder).
- [Cezary Jackiewicz (obsy / eko.one.pl)](https://github.com/obsy) for the
  [eko.one.pl](https://eko.one.pl) packages and OpenWrt Polish community addons.
- [Christian Marangi (Ansuel)](https://github.com/Ansuel) for the upstream
  EDMA and PPE drivers.
- [Robert Marko (robimarko)](https://github.com/robimarko) for maintaining the
  OpenWrt qualcommax target.
- [qosmio](https://github.com/qosmio) for NSS development, the
  [openwrt-ipq](https://github.com/qosmio/openwrt-ipq) tree and the NSS
  firmware packaging.
- [rodriguezst](https://github.com/rodriguezst) for the original
  [ipq807x-openwrt-builder](https://github.com/rodriguezst/ipq807x-openwrt-builder).
- The OpenWrt community in the
  [NSS build thread](https://forum.openwrt.org/t/qualcommax-nss-build/148529).

## License

[GPL-2.0](LICENSE), as OpenWrt.