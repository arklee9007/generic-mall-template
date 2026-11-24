# 部署说明

## 1. 准备

- 微信小程序 AppID（你自己主体的小程序），格式为 wx + 16 位小写十六进制。
- CloudBase 环境（PostgreSQL 数据库），记下环境 ID 与地域（默认 ap-shanghai）。
- 一个域名（或 CloudBase 静态托管地址）放管理后台，记下后台访问域名。

## 2. 填入你的标识（三处一致）

AppID 须在三处填成同一个值，环境 ID 填入项目配置与访问策略：

```
node scripts/setup-env.mjs --appid wx你的AppID --env-id 你的环境ID --admin-host 你的后台云函数域名 [--region ap-shanghai]
```

该脚本改 6 个文件：config/project.json、project.config.json、apps/storefront/src/manifest.json（含顶层与 mp-weixin 两处 appid）、cloudbase/policies/ 下 3 个 rego 策略文件（替换 {{ENV_ID}} 与 {{ADMIN_FUNCTION_HOST}} 占位）。加 --check 可先试看不写盘。重复运行结果相同。

## 3. 云函数环境变量

在 CloudBase 控制台给全部业务云函数设置：

- WECHAT_APP_ID：你的小程序 AppID（未配置时登录一律拒绝）。
- ADMIN_ORIGIN：管理后台的精确来源，如 https://admin.example.com（未配置时后台 HTTP 入口一律拒绝）。
- TCB_REGION：地域，默认 ap-shanghai。

## 4. 数据库迁移

在 PostgreSQL 中按文件名顺序执行 cloudbase/migrations/ 下的全部 SQL 文件（从 20261109030500 到 20261115000000_generic_base.sql）。执行前确认数据库中有 anon、authenticated、service_role 三个角色（CloudBase 环境自带）。通用迁移 20261115000000 可重复执行（幂等）。

种子数据：迁移自带中性演示数据（[示例] 商品 6 件、分类 3 个、轮播 2 张、公告 1 条、FAQ 2 条、默认运费模板、会员档位 2 档）。

## 5. 云函数部署

```
node scripts/build-business-functions.mjs shop auth customer order member admin
node scripts/build-release.mjs
```

第一个命令把 server/ 源码组装成各云函数包（cloudfunctions/<域名>/）；第二个命令打包发布产物并做违禁扫描（自动化词、旧品牌、旧环境 ID 形态一律不许出现）。

## 6. 初始管理员（bootstrap）

数据库函数 mall_admin_bootstrap(username, hash) 只允许在尚无管理员时调用一次，建第一个管理员账号。密码哈希格式与登录流程见 server/admin.js 与迁移 20261109110000_admin_access.sql。建好后立即用新账号登录后台改密码；bootstrap 函数此后拒绝再次调用。

## 7. 管理后台地址

管理后台构建时设置环境变量 VITE_ADMIN_API_URL，指向 admin 云函数的 HTTP 地址（见 apps/admin/.env.example）。后台来源须与 ADMIN_ORIGIN 精确一致，否则请求被拒。

## 8. 顾客端发布

用微信开发者工具打开本项目（project.config.json 已指好小程序根目录与云函数根目录），确认 AppID 与第 2 步填入的一致，编译上传提交审核。H5 端标题与路由见 apps/storefront/src/manifest.json 的 h5 一节。

## 9. 部署后自查

- 打开小程序能进首页，看到 [示例] 商品；
- 打开后台能登录，工作台看板有数字；
- 后台「商品管理」里点「清空演示数据」，演示商品消失、配置不动（先确认无真实订单引用演示商品，否则会报 DEMO_IN_USE）；
- 充值 1 元测试：余额到账、流水有两条（充值 + 赠送，如命中套餐）。
