# 通用商城模板

微信小程序 + H5 顾客端（uni-app Vue 3）、Vue 3 管理后台、CloudBase 云函数 + PostgreSQL。
跨行业适用：规格 0-3 维、维名可配，店名、品牌字、主色等参数后台可配。

## 界面

![顾客端首页](docs/screenshots/mall-home.png)

顾客端首页（H5 本地演示）：首页、分类、搜索、购物车、下单、订单、地址、登录、我的、客服。演示数据为中性示例店，后台可一键清空。

## 包含什么

- 顾客端：首页、分类、搜索、商品详情、购物车、下单、订单、地址、登录、我的、客服两段式、会员充值与余额。
- 管理后台：工作台看板、商品管理（含三段闸审核）、首页管理、订单管理、运费模板、FAQ 管理、会员与档位管理、系统设置、操作留痕。
- 交易链：按件部分退款、退款原因分责任、撤销退款、库存预占与释放、退款分路（各回各路 / 全部退余额）。
- 会员：充值可开关、余额、折扣、充赠可设、N 档等级后台可设、累计充值实付定级只升不降、会员总开关加充值开关、每档会员卡背景图商家上传加可编辑文字、无图纯色兜底。
- 演示数据：中性示例店（6 件 [示例] 商品、3 个分类、2 张轮播、1 条公告），后台可一键清空演示数据。

## 不包含什么

- 不含任何账号、密钥、AppSecret 与演示店铺数据；AppID 与环境 ID 由买家自己填（见 docs/deploy.md）。
- 不含自动化功能（自动上新、自动上下架等为另售的加购包）。
- 不含定制系统（印制、版型、图库）与赠券赠品服务。

## 快速开始

1. 按 docs/deploy.md 填入你自己的 AppID、环境 ID、后台域名（可用 `node scripts/setup-env.mjs` 一键填）。
2. 按顺序执行 cloudbase/migrations/ 下的全部迁移（文件名即顺序）。
3. 部署云函数：`node scripts/build-business-functions.mjs shop auth customer order member admin`，再用 `node scripts/build-release.mjs` 打包。
4. 初始管理员见 docs/deploy.md 的 bootstrap 一节。

## 文档

- docs/deploy.md：部署步骤（AppID 三处一致、函数环境变量、策略占位、初始管理员、迁移顺序、后台地址配置）。
- docs/config.md：店铺配置与会员档位口径。
- docs/scope.md：可编辑收口、售后边界、已知限制。

## 本地检查

```
node scripts/check-foundation.mjs   # 基础检查：三处 AppID 一致性、违禁字符串扫描
node scripts/selfcheck.mjs          # 钱账与规格纯函数自检
scripts/replay-db.sh                # 全新数据库回放全部迁移 + 验收断言（需本机 PostgreSQL）
node scripts/money-chain-check.mjs  # 充值→报价→下单→支付→退款全链路模拟对账
```

## 开源协议

本项目采用 AGPL-3.0 开源协议，详见 LICENSE 文件。
