# adb-for-android

在 arm64 Android 设备上**直接运行**的 `adb` / `fastboot` 客户端（非 Termux 运行环境），
从 AOSP 官方 `platform-tools-35.0.2` 交叉编译，附带 KernelSU 模块。

- 链接方式：**bionic 动态 + 第三方全静态**（运行时只需要系统的 `libc/libm/libdl`）
- `adb`：TCP 连接、`adb pair` 无线调试（TLS）、USB/OTG（root）
- `fastboot`：usbfs / OTG（root）
- 目标：arm64-v8a，Android 10+（在 Android 16 / HyperOS 上实测）

## 产物

| 文件 | 说明 |
|---|---|
| `prebuilt/adb` | ELF aarch64 PIE，约 5.4 MB，已 strip |
| `prebuilt/fastboot` | ELF aarch64 PIE，约 1.1 MB，已 strip |
| `dist/adb-fastboot-tools.zip` | KernelSU/Magisk 模块包 |

二进制属性（`llvm-readelf`）：

```
Type:    DYN (PIE)
Machine: ARM aarch64
INTERP:  /system/bin/linker64
NEEDED:  libdl.so, libm.so, libc.so
```

protobuf、abseil、BoringSSL、fmt、pcre2、brotli、lz4、zstd、zlib、libusb、
libbase/liblog/libcutils 等全部静态链接，不需要 `libc++_shared.so` 等额外依赖。

## 仓库结构

```
├── prebuilt/              # 编译好的 adb、fastboot
├── dist/                  # KernelSU 模块 zip
├── module/                # 模块源文件（module.prop、customize.sh、wrapper）
├── patches-local/         # 构建时对 AOSP 源码的本地补丁
├── scripts/
│   ├── build.sh           # 从 AOSP 源码一键构建
│   └── make-module.sh     # 从 prebuilt/ 打包模块 zip
├── LICENSE                # Apache-2.0
└── NOTICE                 # 第三方来源说明
```

## 使用

### 直接放在 /data/local/tmp

```sh
adb push prebuilt/adb prebuilt/fastboot /data/local/tmp/
adb shell chmod 755 /data/local/tmp/adb /data/local/tmp/fastboot
```

adb 在 Android 上必须指定可写的 `HOME` 和 `TMPDIR`（shell/root 默认 `HOME=/`，且无 `/tmp`）：

```sh
adb shell 'HOME=/data/local/tmp/home TMPDIR=/data/local/tmp /data/local/tmp/adb version'
adb shell 'TMPDIR=/data/local/tmp /data/local/tmp/fastboot --version'
```

`$HOME` 目录必须已存在，adb 会在其中创建 `.android/`（`adbkey`、`adbkey.pub`、
`adb.5037`，配对后还有 `adb_known_hosts`）。adb 不会递归创建父目录。

连接本机 adbd（root 打开 TCP 监听）：

```sh
adb shell 'su -c "setprop service.adb.tcp.port 5555; stop adbd; start adbd"'
adb shell 'HOME=/data/local/tmp/home TMPDIR=/data/local/tmp /data/local/tmp/adb connect 127.0.0.1:5555'
adb shell 'HOME=/data/local/tmp/home TMPDIR=/data/local/tmp /data/local/tmp/adb devices -l'
```

首次使用会生成客户端密钥，但 **生成不等于授权**。`ro.adb.secure=1` 时需把公钥加入
`/data/misc/adb/adb_keys`（root），否则显示 `unauthorized`：

```sh
su -c 'cat $HOME/.android/adbkey.pub >> /data/misc/adb/adb_keys'
su -c 'chmod 640 /data/misc/adb/adb_keys; chown system:shell /data/misc/adb/adb_keys; restorecon /data/misc/adb/adb_keys'
su -c 'stop adbd; start adbd'
```

也可以直接把 PC 上已授权的 `~/.android/adbkey` 复制到设备的 `$HOME/.android/`。

> 注意：不要先用 root 再以 shell 身份共用同一个 HOME —— root 创建的 `.android`
> 是 0750/0600，shell 读不到密钥。建议固定用同一身份，或使用模块 wrapper 的
> 按 uid 分目录方案。

### fastboot

fastboot 只能作为 USB host，通过 OTG 操作**另一台**设备；手机不能刷自己。
需要 root 与 OTG 主机模式：

```sh
adb shell 'su -c "TMPDIR=/data/local/tmp /data/local/tmp/fastboot devices"'
```

### KernelSU 模块

安装 `dist/adb-fastboot-tools.zip` 后：

- `/system/bin/adb`、`/system/bin/fastboot`：wrapper，自动设置
  `HOME=/data/local/tmp/adb-home-$(id -u)` 与 `TMPDIR=/data/local/tmp`
- `/system/bin/adb.bin`、`/system/bin/fastboot.bin`：实际二进制

```sh
adb push dist/adb-fastboot-tools.zip /data/local/tmp/
adb shell 'su -c "ksud module install /data/local/tmp/adb-fastboot-tools.zip"'
# 重启后
adb shell 'which adb; adb version'
adb shell 'ls -Z /system/bin/adb*'   # 期望 u:object_r:system_file:s0
```

## 从源码构建

需要：NDK r29、CMake 4.x、ninja、python3、git、patch、go、bison、flex、
构建机 C/C++ 编译器。首次运行会浅克隆约 40 个 AOSP 仓库（约 5 GB）。

```sh
export NDK=/path/to/android-ndk-r29
./scripts/build.sh
```

脚本会：

1. `sdk-tools/get_source.py` 拉取 `platform-tools-35.0.2` 源码；
2. 应用 `patches-local/` 下的 4 个兼容补丁；
3. 用 `--link=shared --api=30 --target adb fastboot` 交叉编译；
4. 产物输出到 `out/`。

重新打包模块：`./scripts/make-module.sh`。

### 构建时解决的问题

1. **fmt 10.2 + clang 21**：`consteval` 格式串检查报错，用 `-DFMT_CONSTEVAL=` 关闭。
2. **openscreen `task_runner.h`**：NDK r29 的 libc++ 没有
   `std::packaged_task<void() noexcept>`，改为 `std::packaged_task<void()>`。
3. **fdsan（关键）**：AOSP 35.0.2 的 fdsan 打标签与 Android 16 不兼容，
   adb server 启动时在 `adb_auth_inotify_init` 后 abort。按 Termux 的做法在
   `libbase/unique_fd.h`、`libcutils/native_handle.cpp`、`libziparchive/zip_archive.cc`
   禁用 fdsan，退回普通 `close()`。**不应用此补丁，adb server 无法启动。**

构建系统基于 [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools)。
不要使用 `--target all`：无关目标 `libprocessgroup` 会因 API 36 符号在 NDK r29 下失败。

## 已验证

- `adb version` / `fastboot --version`
- shell 与 root 身份下 `adb start-server` 均成功
- `adb devices`、`adb connect 127.0.0.1:5555`
- `fastboot devices`（无 OTG 目标时正常返回空）

未验证：授权后的 `adb shell/push/install`、OTG fastboot 实际刷写。

## 许可

本项目脚本与补丁使用 Apache License 2.0，见 [LICENSE](LICENSE)。
`adb`/`fastboot` 来自 AOSP platform-tools 35.0.2（Apache-2.0），
第三方来源与修改说明见 [NOTICE](NOTICE)。
