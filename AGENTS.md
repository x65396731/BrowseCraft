# BrowseCraft Codex Instructions

- 对所有代码任务：只帮我修改代码，不要主动跑测试。
- 对所有代码任务：不要自动 build；只有我明确要求时才可以 build。
- BrowseCraft 使用 XcodeGen 管理工程。遇到 `.xcodeproj` 因新增、移动、删除源码文件或工程文件不同步导致的错误时，先运行 `scripts/regenerate-project.sh`，再继续测试、build 或排查。
