# 好友申请保留规则

- 每条申请从创建时间起保留完整 72 小时，收到和发出使用同一条记录。
- pending / accepted / ignored / invalidated 均适用；接受、忽略或重试不会延长保留期。
- 接口立即过滤到期申请及申请红点，拒绝接受过期申请。到期后可用新的操作编号重新申请。
- `hegong-friend-requests.timer` 每 30 分钟启动清理；关机错过的计划在启动后补跑。每批最多 200 条，每次最多 25 批，积压由后续周期继续处理。
- 清理删除申请及关联的 `friend_request` 系统通知，不删除已建立的好友关系、普通消息、卡牌或交易。
- 好友申请操作的幂等回执只保留操作编号、哈希和申请引用等小型标记。旧完整响应分批压缩，重试读取当前状态，避免过期申请被重新创建。
- 使用账号排序锁、批次事务及 advisory lock；异常回滚当前批次。PostgreSQL 的 autovacuum 回收死元组供后续写入复用，不运行 `VACUUM FULL`。

运维：

```sh
systemctl status hegong-friend-requests.timer
journalctl -u hegong-friend-requests.service -n 20 --no-pager
systemctl start hegong-friend-requests.service
```

服务使用现有 `/etc/hegong/backend.env`，不增加凭据。日志只输出清理数量。
上线前先备份数据库；备份按运维保留策略管理，不属于客户端申请列表。
后端源码、测试和部署文件仅保存在本地及服务器，不上传 GitHub。
