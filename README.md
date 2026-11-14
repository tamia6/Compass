# 指南针

原生 SwiftUI iOS 17+ App，依据 iPhone 镜像中的指南针布局复刻。

- Core Location：方向、位置、经纬度、海拔；无有效读数时显示 —。
- Core Motion：中央水平检测，圆点随倾斜移动，平放时与十字对齐。
- 仅前台读取传感器；定位需用户允许。海拔来自系统定位，精度取决于设备和环境。

打开 `CompassReplica.xcodeproj`，选择 CompassReplica scheme 运行。真机运行需在 Signing & Capabilities 中选择自己的开发团队。

模拟器没有磁力计和运动传感器；在 Run → Arguments 中添加 `--preview` 可查看 278° 西的固定示例画面，底部明确标记示例数据。正常运行不使用示例数据。

最小逻辑检查：

```sh
swiftc CompassReplica/CompassMath.swift checks/main.swift -o /tmp/compass-check && /tmp/compass-check
```

Apple API 参考：https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatingheading()

## 系统语言

使用原生 String Catalog 自动跟随系统/App 语言，支持简体中文、繁体中文、英语、日语、韩语、法语、德语和西班牙语；其他语言回退英语。方位、坐标、海拔、提示、无障碍描述、App 名称和权限说明均已本地化。地名请求使用当前系统区域语言，海拔保留米，数字与单位按系统区域格式显示。

将已构建的 `.app` 路径作为 `/tmp/compass-check` 的参数，可检查全部八种语言的编译资源和坐标格式。

## 水平反馈与放大

由倾斜进入 1° 范围时强触感震动一次；超过 2° 后重新允许触发，避免传感器抖动导致重复震动。初次启动和从后台恢复不因当前已水平而震动。阈值位于 `LevelDetector`，可按真机手感校准。

点击中央水平仪放大 2.5 倍，再点恢复；外圈刻度保持原尺寸。

中央水平仪使用简单半透明圆点，直接跟随倾斜移动，无水滴高光、渐变、描边或回弹形变动画。下方说明、地址、经纬度及海拔统一字号和字重。

## 显示模式

右上角图标切换普通指南针、风水罗盘与水平仪，自动记住所选模式。风水模式采用后天八卦、二十四山（每山 15°，子居正北），红字标出当前朝向对应的山位。传统盘面字符保持汉字，按钮及无障碍描述跟随系统语言。指南针模式共用原有方位数据。

方位排列参考：https://iching10.com/docs/principle/29-24-directions

## iPhone Duo

使用 Xcode 27.2 或更新 SDK 构建。iOS 27.1+ 根据可用空间调整上下或左右布局，半折状态将仪表和读数放在折叠区域两侧；原生工具栏避让系统区域。屏幕开合时保留模式、外观和中央水平仪放大状态。较早系统保留竖屏布局。

已在 Duo iOS 27.1 模拟器检查外屏、展开、半折与横竖屏，以及中英文、深浅色样例。真实传感器精度和触觉反馈仍需在真机验证。

## 支持与隐私

- [技术支持](https://compass-level-support.pages.dev/support)
- [隐私政策](https://compass-level-support.pages.dev/privacy)

静态网站源码位于 `site/`。

在应用中长按外观切换按钮，可打开隐私政策和技术支持页面。手机桌面名称为“指南针与水平仪”（英语为“Compass & Level”），避免与系统指南针重名。
