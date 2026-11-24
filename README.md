# HumanPlus 双目视频脱敏部署

HF 数据仓库已公开。默认入口全程非交互，不需要 Token，自动下载软件/环境/模型和30秒测试输入，处理并校验左右视频，结果保存在计算节点本地。

先按集群规则申请 GPU，在分配的 Linux 计算节点中运行：

```bash
git clone https://github.com/FLLTT/hp1000-blur-deploy.git hp1000-blur
bash hp1000-blur/run.sh
```

已经下载过仓库时，先更新：

```bash
git -C hp1000-blur pull --ff-only
bash hp1000-blur/run.sh
```

建议将工作文件放在 scratch：

```bash
bash hp1000-blur/run.sh --work-dir /实际scratch路径/humanplus-blur
```

## 自动上传结果（可选，仍需要写入 Token）

公开仓库允许匿名下载，但不允许匿名写入。默认模式**不上传结果**，完成时会明确显示 `PUBLIC DOWNLOAD MODE`，任务回执为 `completed_local_only`。需要自动上传并从固定提交回读校验SHA时，通过私有文件提供有该仓库写权限的 Token：

```bash
chmod 600 /实际私有路径/token.private
bash hp1000-blur/run.sh --token-file /实际私有路径/token.private --work-dir /实际scratch路径/humanplus-blur
```

也支持作业系统通过秘密环境变量提供 `HF_TOKEN`，不提示输入，临时凭证文件退出时删除。不要把 Token 写到 GitHub、脚本或命令历史。公开模式不会自动读取旧的交互凭证缓存。

## 输出与验收

默认工作根目录是仓库下 `.run/`，也可用 `--work-dir` 指定。其下任务目录：

`work-public-r1/jobs/LSEQ_73a37c51d124-45s-75s/`

- 最终视频：`output/fisheye_left.mp4`、`output/fisheye_right.mp4`。
- 日志：`attempts/*/inference.log`；进度：`attempts/*/pipeline/status.json`。
- 处理结果：`reports/execution.json`；上传回执：`reports/return_receipt.json`。
- 批次总结：工作根目录下 `work-public-r1/batch.json`。

终端 `Batch finished: 1/1 passed` 和退出码0表示所选模式通过。匿名模式只表示本地处理/完整解码/逐PTS校验通过，上传字段会明确为false；提供有效Token时才执行HF上传和回读。失败保留工作目录，重试复用同一输入/版本已验证成功的处理结果；处理途中失败则从整片重试。旧R5工作目录保留，公开模式使用新的独立目录。

## 环境与范围

Linux x86_64/glibc>=2.28、兼容NVIDIA驱动、Git、bash/tar/gzip/sha256sum/flock和curl或wget。无需sudo、系统Python、Conda或Docker，Python、视频工具、PyTorch、模型由脚本自动准备。网络需能访问GitHub及HF主站与实际文件域名。脚本不包含国内代理或SSH配置。

建议一张GPU至少8GiB可用显存、8CPU、32GiB内存、至少50GiB可用磁盘。软件包约4.69GB、测试输入约607MB，首次需展开并安装环境。使用调度系统分配到的GPU，当前不自动多卡并行或提交Slurm作业。

当前默认和 `--all` 都只包含同一条30秒样本：session_20260902_132925，源PTS44.974–74.968秒，双目各904帧。原算法/模型/阈值保持固定，仅增加公开下载及可选写入的传输层。RTX3090已通过旧R5完整链路，完整345秒及另外4条整段也已验收退出0；公开入口完成了无终端控制测试、源文件补丁/哈希与公开配置下载检查，尚未在德国/B200上实跑。视频完整性不代表零漏脸，人工质量复检另行进行。
