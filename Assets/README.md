# 应用图标

`Pulse.icns` 是构建脚本使用的 macOS 图标，由项目自带的 AppKit 绘图工具生成。

在项目根目录重新生成：

```sh
mkdir -p Assets
swift Tools/MakeIcon.swift Assets
iconutil -c icns Assets/Pulse.iconset -o Assets/Pulse.icns
```

生成后的 `Pulse.iconset` 是中间资源，打包应用只需要 `Pulse.icns`。
