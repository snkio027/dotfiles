# 新个人 Mac 从零部署

适用于全新的 Apple Silicon Mac 和个人 GitHub 账户。完成后，GitHub SSH 认证和 Git 提交签名使用 Proton Pass 中的个人密钥，新终端会加载工作区快捷方式，Neovim 会加载仓库配色。所有命令都在**新 Mac** 上运行。

## 1. 安装命令行工具和 Homebrew

用个人账户完成开机设置，按 `⌘ Space` 搜索并打开「终端」，运行：

```sh
xcode-select --install
```

在弹窗中确认，等安装完成。打开 [Homebrew 官网](https://brew.sh/)，下载并运行 macOS 的 `.pkg` 安装包。回到终端，运行以下命令，并保留这个窗口直到第 4 步结束：

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"
export XDG_CONFIG_HOME="$HOME/.config"

brew install chezmoi
brew install --cask proton-pass
open -a "Proton Pass"
```

## 2. 准备 Proton Pass 里的个人 SSH 密钥

在桌面应用登录并解锁个人账户。如果保险库里已经有打算用于个人 GitHub 的 SSH 密钥，选中它。如果还没有，可在手机的 Proton Pass 中选择 **+ → Other → SSH Key → Public key → Generate SSH key**，生成 Ed25519 密钥，命名为 `Personal Mac GitHub` 并保存。等该条目同步到 Mac。[Proton SSH Agent 指南](https://proton.me/support/ssh-agent)

在 **Mac 桌面版 Proton Pass → Settings → General → SSH Agent** 勾选 **Use Proton Pass as SSH agent**。首次保存公钥时，在终端运行下面两行。如果提示文件已存在，直接比较下一段的指纹。

```sh
install -d -m 700 ~/.ssh ~/.ssh/keys
(set -C; cat > ~/.ssh/keys/git_signing.pub)
```

当终端等待输入时，回到 Proton Pass，复制该条目的 **Public key**。回终端按 `⌘V` 粘贴，按一次 `Return`，再按 `Ctrl+D` 保存。Ed25519 公钥是一行以 `ssh-ed25519` 开头的文本。私钥留在 Proton Pass 中。

```sh
ssh-keygen -lf ~/.ssh/keys/git_signing.pub
SSH_AUTH_SOCK="$HOME/.ssh/proton-pass-ssh-agent.sock" ssh-add -l
```

**看到第一条命令的 `SHA256:…` 指纹出现在第二条的列表中，再继续。** 如果无法连接，先确认桌面应用已解锁并启用了 SSH Agent。如果列表里有其他指纹，回到所选密钥条目核对公钥。

## 3. 在个人 GitHub 登记公钥

将刚验证过的公钥复制到剪贴板：

```sh
pbcopy < ~/.ssh/keys/git_signing.pub
```

登录个人账户，打开 [GitHub → Settings → SSH and GPG keys](https://github.com/settings/keys)。点击 **New SSH key**，按下表登记同一行公钥。已有相应用途时，只补缺少的那项。[GitHub 公钥登记说明](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)

| Key type | Title 示例 | 用途 |
| --- | --- | --- |
| Authentication Key | Personal Mac SSH | 通过 SSH 拉取或推送仓库 |
| Signing Key | Personal Mac Git Signing | 让 GitHub 验证提交签名 |

## 4. 预览并完整部署 dotfiles

```sh
chezmoi init https://github.com/snkio027/dotfiles
```

按提示填写**个人 Git 姓名**与**已在个人 GitHub 账户验证的邮箱**。先预览，再执行完整部署：

```sh
chezmoi diff --no-pager
```

```sh
chezmoi apply
```

这一步会安装工作站工具、部署 Shell、Ghostty、Neovim、Git 与 SSH 配置，并应用 Finder、Dock、键盘和截图等 macOS 偏好。如果部署提示 Agent 或公钥缺失，回到第 2 步，确认指纹匹配后重新运行 `chezmoi apply`。成功后**打开一个新的终端窗口**，在新窗口完成下面的检查。[部署范围与维护手册](operations.md#初始化)

## 5. 验证 GitHub、默认签名和日用配置

先确认 GitHub 识别的是你的个人账户：

```sh
ssh -T git@github.com
```

首次连接若询问是否信任主机，先核对 [GitHub 官方主机指纹](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)。认证成功会显示 `Hi 你的用户名! You've successfully authenticated…`。这条 GitHub 探测命令在成功认证时也会以状态码 1 退出。[GitHub 测试说明](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection)

接着在临时仓库创建一条普通提交，验证默认签名已经生效：

```sh
check_dir="$(mktemp -d)"
git -C "$check_dir" init -q
git -C "$check_dir" commit --allow-empty -m "Verify personal Mac signing"
git -C "$check_dir" verify-commit HEAD
```

最后一条应显示 `Good "git" signature` 和你的个人邮箱。若 SSH 认证成功但签名失败，按[签名配置排查步骤](operations.md#ssh-与提交签名)检查生效的签名程序和公钥。

建立个人工作区并试用快捷方式：

```zsh
mkdir -p ~/Workspace/{projects,lab,data,archive}
install -d -m 700 ~/Workspace/vault
w3
pwd
nvim
```

`pwd` 应显示以 `/Workspace/projects` 结尾的路径。让 Neovim 完成首次插件安装，即可使用仓库配色。个人项目按需 clone 到 `~/Workspace/projects`。

## 6. 按需设置 Chrome 自动填充

```sh
brew install --cask google-chrome
```

1. 打开 Chrome，从 [Proton 官方安装指南](https://proton.me/support/pass-setup) 进入 Chrome Web Store，添加 Proton Pass 扩展，登录个人账户并固定到工具栏。
2. 打开 **Google 密码管理器 → 设置**，关闭「提供保存密码和通行密钥」与「自动登录」。[Chrome 密码设置说明](https://support.google.com/chrome/answer/95606)
3. 在地址栏打开 `chrome://extensions`。如果装有 iCloud Passwords，停用这个 Chrome 扩展。Safari 和其他 Apple 应用可以继续使用 Apple Passwords。
4. 打开一个在 Proton Pass 中已有登录记录的网站，确认扩展能填充。下次注册新账户时，确认由 Proton 生成并保存新密码。已有 Apple、Google 密码及 Passkey 可以先保留。
