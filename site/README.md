# 支持与隐私页面

- 技术支持：https://compass-level-support.pages.dev/support
- 隐私政策：https://compass-level-support.pages.dev/privacy
- 联系邮箱：tamia.here@gmail.com

Cloudflare Pages advanced mode 通过 `_worker.mjs` 提供静态 HTML 和 CSS，无数据库或分析服务。修改 `support.html`、`privacy.html`、`style.css` 后，需要同步更新 `_worker.mjs` 内嵌内容。

使用已登录的本地 `cf` CLI，在此目录部署：

```sh
cf pages deployments create compass-level-support --branch main --manifest '{}' --worker-js @_worker.mjs
```

部署前通过 `CLOUDFLARE_ACCOUNT_ID` 选择自己的 Cloudflare 账户；凭据不保存在仓库中。应用的数据处理方式变化后，应同步复核隐私政策。
