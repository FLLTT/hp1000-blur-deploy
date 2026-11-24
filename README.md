# HumanPlus 双目脱敏：clone 后一条 bash

这个仓库只包含小型启动脚本和说明。模型、环境包、输入视频与返回结果均保存在私有 Hugging Face Dataset `FLTTY/Lty-HP1000`；仓库不包含 Token、模型包或原始数据。

在已分配的 GPU 计算节点中执行：

```bash
git clone https://github.com/FLLTT/hp1000-blur-deploy.git hp1000-blur
bash hp1000-blur/run.sh
```

首次运行会在终端提示粘贴仅允许该 HF 仓库读写的 Token。输入不回显，不进入 shell 命令历史；脚本将它保存在 `${XDG_CONFIG_HOME:-~/.config}/humanplus-blur/token.private`（0600），位于 Git checkout 外。随后自动下载并检查软件包、准备独立环境、下载视频、脱敏、验证双目输出并回传。以后的运行自动复用该凭证，不需要再次输入，也不需要手工创建 `token.private`。

私有仓库仍然需要一次身份验证；“两条命令”不是免凭证访问。不要把 Token 写进脚本、README、Git URL或GitHub仓库。

```bash
# 换存储目录，避免占用home配额
bash hp1000-blur/run.sh --work-dir /scratch/humanplus-blur
# 配套批次入口；当前冻结清单仅有一个30秒样本，并不代表10条已经验收
bash hp1000-blur/run.sh --all --work-dir /scratch/humanplus-blur
# Slurm/无交互终端：提前通过安全方式提供0600凭证文件
bash hp1000-blur/run.sh --token-file /private/path/hf-token --work-dir /scratch/humanplus-blur
# 替换缓存Token，重新隐藏输入
bash hp1000-blur/run.sh --new-token
```

也支持作业系统通过秘密环境变量提供 `HF_TOKEN`，此时只创建临时0600文件，退出即删除，不写入永久缓存；不要把实际Token写在命令行中。首次交互输入需在可交互终端中完成，不能在Slurm无终端作业中等待粘贴。

依赖边界：Linux x86_64/glibc>=2.28、兼容NVIDIA驱动、基本bash/tar/gzip/sha256sum/flock和curl或wget。Python、视频工具、PyTorch、算法与模型均由脚本准备。网络按德国正常直连使用，脚本不含国内VPN、代理地址或SSH通道。

请先在集群中申请到一张 GPU，并在分配的计算节点内运行；脚本不会代替 Slurm/PBS 申请资源。若通过批处理提交，请使用 `--token-file`，不要在无交互作业里等待输入。

当前已冻结的是 `session_20260902_132925` 的30秒L-Sequence试验，左右各904帧，实际源PTS44.974–74.968秒。处理、解码、逐PTS及HF回读SHA已在RTX3090测试通过；传输升级复用了已校验的算法结果。完整345秒样本及另外4条完整 L 视频也已在我们的RTX3090服务器处理并回传成功（退出码0）；这个GitHub入口仍只处理30秒样本，方便师兄先验证部署。B200目标节点尚未实测，10条批次尚未验收。

正式HD输出是 `fisheye_left.mp4`、`fisheye_right.mp4`。重复运行复用同一数据/版本已通过的结果，保留失败attempt和日志，处理中断后会整片重试。磁盘按小样本至少50GiB可用预算，GPU建议8–16GiB可用显存，8CPU/32GiB内存；批次资源要按实际输入核算。文件完整性通过不等于零漏脸。


师兄首次验收以终端 `Batch finished: 1/1 passed` 和退出码0为准。默认工作目录在仓库下 `.run/`，使用 `--work-dir` 时则以该目录为根：

- 进度和日志：`work-overlay-r5/jobs/LSEQ_73a37c51d124-45s-75s/attempts/*/inference.log`。
- 最终视频：`work-overlay-r5/jobs/LSEQ_73a37c51d124-45s-75s/output/fisheye_left.mp4` 和 `fisheye_right.mp4`。
- 处理与上传证据：该任务的 `reports/execution.json`、`reports/return_receipt.json`；批次汇总为 `work-overlay-r5/batch.json`。

失败时保留工作目录。请把失败阶段、退出码和上述任务日志反馈给发送者；不要发送Token、请求头或部署下载日志中的完整临时链接。初次运行包含约4.69GB软件包和约607MB输入下载，以及环境展开；总耗时取决于网络、存储和GPU。`--all` 当前与默认入口使用同一个单条短样本，不会自动扩展为10条。
