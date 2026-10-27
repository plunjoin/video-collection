# Bllii 代码签名指南

> 覆盖 Windows / macOS / Android 三端发布签名。本地打包与 CI 均已接入本文所述流程，
> 未配置签名凭据时自动跳过，不会导致构建失败。

## 1. 为什么要签名

| 平台 | 不签名的后果 |
|---|---|
| Windows | 安装/运行时弹 "Windows 已保护你的电脑" (SmartScreen)，用户信任度暴跌；后台静默更新基本不可用 |
| macOS | Gatekeeper 拦截 "已损坏，无法打开"（未公证应用） |
| Android | release 包只能用正式 keystore 签名；用 debug key 签名的包无法上架，且无法覆盖升级 |

## 2. Windows 证书选购

| 方案 | 参考价格 | SmartScreen 表现 | 适用场景 |
|---|---|---|---|
| **Azure Trusted Signing**（推荐） | 约 $9.99/月 | 立即可信（等同 EV） | 独立开发者 / 小团队，无需硬件，CI 友好 |
| OV 代码签名证书 | ¥1000–3000/年 | 需积累一定安装量后才免警告 | 已有采购预算 |
| EV 代码签名证书 | ¥3000–6000/年 | 立即可信 | 企业，需硬件令牌/U 盾 |
| 自签名证书 | 免费 | 仅本机有效 | 开发调试，**不可用于分发** |

**Azure Trusted Signing 开通**：Azure 门户创建 "Trusted Signing" 资源 → 账户 → 证书配置文件，
然后用官方客户端在本地/CI 签名（见 3.3）。

## 3. 本地签名

### 3.1 脚本一览

`scripts/sign-release.ps1` 支持三种凭据（按优先级自动探测）：

1. **PFX 文件**：`-PfxPath` / `-PfxPassword`，或环境变量 `BLLII_CERT_PFX` / `BLLII_CERT_PASSWORD`
2. **证书存储区指纹**：`-Thumbprint`，或环境变量 `BLLII_CERT_THUMBPRINT`
   （自动在 `CurrentUser\My`、`LocalMachine\My` 中查找）
3. **Azure Trusted Signing**：`-DlibPath` / `-DmdfPath`，或环境变量 `BLLII_AZURE_DLIB` / `BLLII_AZURE_DMDF`

签名对象支持：目录（递归签 `*.exe` / `*.dll`）、单个文件、`.zip` 包（自动解压→签名→重新打包）。

### 3.2 快速开始（PFX 模式）

```powershell
# 1) 配置凭据（只需做一次，可写入 $PROFILE 持久化）
$env:BLLII_CERT_PFX = "$env:USERPROFILE\certs\bllii.pfx"
$env:BLLII_CERT_PASSWORD = "your-pfx-password"

# 2) 手动签名
cd video-collection-app
.\scripts\sign-release.ps1 -Path build\windows\x64\runner\Release
.\scripts\sign-release.ps1 -Path dist\bllii_setup_windows_v1.0.1.exe

# 3) 或者打包时自动签名（build-release.ps1 已内置）
.\build-release.ps1                 # 自动签名；未配置证书时自动跳过并提示
.\build-release.ps1 -SkipSign       # 显式跳过签名
```

本地生成自签名证书（仅测试用）：

```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject "CN=Bllii Dev Test" -CertStoreLocation Cert:\CurrentUser\My
$pwd = ConvertTo-SecureString -String "123456" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$env:USERPROFILE\bllii-test.pfx" -Password $pwd
# 如需存储区模式:
$env:BLLII_CERT_THUMBPRINT = ($cert.Thumbprint)
```

### 3.3 Azure Trusted Signing 模式

```powershell
# 安装官方客户端 (任选其一)
dotnet tool install --global Microsoft.Trusted.Signing.Client
# 或
winget install Microsoft.Trusted.Signing.Client

# 配置
$env:BLLII_AZURE_DLIB = "$env:USERPROFILE\.dotnet\tools\Microsoft.Trusted.Signing.Client\bin\x64\Azure.CodeSigning.dll"
$env:BLLII_AZURE_DMDF = "$env:USERPROFILE\azure-signing-metadata.json"
$env:AZURE_CLIENT_ID     = "<app registration client id>"
$env:AZURE_CLIENT_SECRET = "<app registration secret>"
$env:AZURE_TENANT_ID     = "<tenant id>"
```

`azure-signing-metadata.json`（含账户信息，注意保管、勿提交仓库）：

```json
{
  "Endpoint": "https://< region >.codesigning.azure.com",
  "CodeSigningAccountName": "<Trusted Signing 账户名>",
  "CertificateProfileName": "<证书配置文件名称>"
}
```

## 4. CI（GitHub Actions）配置

`.github/workflows/release.yml` 已内置签名步骤，**只需在仓库 Settings → Secrets 中配置对应变量**；
未配置时对应平台自动跳过签名，构建不会失败。

### 4.1 Secrets 清单

| Secret | 用于 | 生成方式 |
|---|---|---|
| `BLLII_CERT_PFX_BASE64` | Windows PFX | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("bllii.pfx"))` |
| `BLLII_CERT_PASSWORD` | Windows PFX 密码 | 导出 PFX 时设置 |
| `BLLII_CERT_THUMBPRINT` | Windows 存储区模式（与 PFX 二选一） | `certmgr.msc` 中查看证书指纹 |
| `ANDROID_KEYSTORE_BASE64` | Android keystore | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PROPERTIES_BASE64` | Android key.properties | `base64 -w0 android/key.properties` |
| `MACOS_CERT_BASE64` | macOS p12 证书 | `base64 -i cert.p12 \| tr -d '\n'` |
| `MACOS_CERT_PASSWORD` | p12 导出密码 | 导出时设置 |
| `MACOS_KEYCHAIN_PASSWORD` | CI 临时 keychain 密码 | 任意强密码 |
| `MACOS_API_KEY_ID` / `MACOS_API_ISSUER` / `MACOS_API_KEY_BASE64` | notarytool 公证 | App Store Connect → 用户和访问 → 密钥 → App Store Connect API |

### 4.2 Android keystore 与 key.properties

```bash
keytool -genkey -v -keystore upload-keystore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`android/key.properties`（`storeFile` 相对 `android/app/` 目录，CI 会把 keystore 解码到该处）：

```properties
storePassword=<keystore 密码>
keyPassword=<key 密码>
keyAlias=upload
storeFile=upload-keystore.jks
```

本地开发把 keystore 放到 `android/app/upload-keystore.jks` 并创建上述
`android/key.properties` 即可；不放则自动回退 debug key，不影响 `flutter run`。

> ⚠️ keystore 和密码丢失将永远无法更新已上架应用，务必离线备份。

### 4.3 macOS 证书与公证

需要 Apple Developer Program（$99/年）中的 **Developer ID Application** 证书：

```bash
# 本地手动签名 + 公证（CI 中已自动完成）
security import cert.p12 -k ~/Library/Keychains/login.keychain-db
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: <团队名> (<TEAMID>)" \
    video_collection_app.app
ditto -c -k --sequesterRsrc --keepParent video_collection_app.app bllii.zip
xcrun notarytool submit bllii.zip --apple-id <id> --password <app-specific> --team-id <TEAMID> --wait
xcrun stapler staple video_collection_app.app
```

## 5. 时间戳服务器

脚本默认使用 DigiCert；证书过期后，带时间戳的签名仍然有效。可用 `-TimestampUrl` 切换：

| 提供商 | URL |
|---|---|
| DigiCert（默认） | `http://timestamp.digicert.com` |
| Sectigo | `http://timestamp.sectigo.com` |
| GlobalSign | `http://timestamp.globalsign.com/tsa/r6advanced` |
| Certum | `http://time.certum.pl` |
| Azure Trusted Signing | `http://timestamp.acs.microsoft.com`（Azure 模式默认） |

## 6. 验证签名

```powershell
# Windows 安装包 / exe
signtool verify /pa dist\bllii_setup_windows_v1.0.1.exe
Get-AuthenticodeSignature dist\bllii_setup_windows_v1.0.1.exe | Format-List

# zip 内文件：先解压再验证，或直接对 zip 签名（脚本自动处理）
.\scripts\sign-release.ps1 -Path dist\bllii_for_windows_v1.0.1.zip
```

```bash
# Android
$ANDROID_HOME/build-tools/<版本>/apksigner verify --print-certs dist/bllii_for_android_v1.0.1.apk

# macOS
codesign -dv --verbose=4 video_collection_app.app
spctl -a -v -t exec video_collection_app.app
xcrun stapler validate video_collection_app.app
```

## 7. 与后台静默更新的关系

- 签名后的安装包才能避免 SmartScreen 拦截，是"后台下载 + 静默安装"的前提
- 注意 `installer/bllii.iss` 目前 `DefaultDirName={autopf}`（Program Files），
  即使用户接受了 UAC，静默安装也会弹提权框；若追求完全无感更新，
  可将默认安装目录改为 `{localappdata}\Bllii`（配合现有 `PrivilegesRequired=lowest`）

## 8. 注意事项

1. **不要把任何签名材料提交进仓库**——`*.pfx` / `*.p12` / `*.jks` / `*.p8` / `key.properties`
   已加入 `.gitignore`
2. signtool 的 `/p` 密码会出现在进程参数中，CI 一律用 Secrets + 环境变量传入，切勿硬编码
3. PFX 模式下未提供密码时，交互式环境会提示输入；非交互环境（CI）直接报错，不会挂起
4. 每次发版前建议跑一次第 6 节的验证命令，防止"静默失败"产出未签名包
5. iOS 暂未接入自动签名（CI 为 `--no-codesign`），如需真机分发建议后续引入 Fastlane Match
