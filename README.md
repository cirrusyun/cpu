# CS202 RV32I CPU — A 部分（CPU 核心 + Pipeline bonus）

CS202 大作业 cpu_project，**A 部分**（CPU 核心 + 流水线 bonus）的源代码。

## 项目结构

```
cpu_project/
├── README.md                              (this file)
├── .gitignore                             Vivado 工程通用 ignore
├── assembly/                              demand.txt §4.2.1 要求的汇编源 + hex
│   ├── sum_loop.asm + .txt                sum 1..N 循环（speedup demo）
│   ├── ecall_demo.asm + .txt              ECALL bonus 演示 + 非法 SYSTEM
│   ├── load_use_demo.asm + .txt           load-use stall + forward
│   └── branch_demo.asm + .txt             taken branch flush
└── cpu_project.srcs/
    ├── Makefile                           iverilog 一键回归
    ├── sources_1/
    │   ├── cpu/                           A 部分 RTL（12 个文件）
    │   │   ├── cpu.v                      单周期顶层
    │   │   ├── cpu_pipe.v       (NEW)     5 级流水核心
    │   │   ├── cpu_top.v        (NEW)     单周期/流水 mode 切换 wrapper
    │   │   ├── hazard_unit.v    (NEW)     load-use stall + flush
    │   │   ├── forward_unit.v   (NEW)     EX 操作数前递
    │   │   ├── cycle_counter.v  (NEW)     64-bit 周期 / 退休指令计数
    │   │   ├── alu.v / alu_ctrl.v
    │   │   ├── ctrl.v                     主译码器（精确 ECALL 译码）
    │   │   ├── imm_gen.v / load_store_fmt.v / reg_file.v
    │   ├── gpio/                          数码管驱动等（C 部分协作）
    │   └── (B 真实 ifetch.v/dmem.v 待集成)
    ├── sim_1/                             22 个 testbench
    │   ├── fake_ifetch.v / fake_dmem.v    A 域单元仿真用桩（含越界 $fatal）
    │   ├── tb_alu / regfile / imm_gen / load_store_fmt  (unit)
    │   ├── tb_cpu_* (8 个)                单周期集成 TB
    │   ├── tb_pipe_* (9 个)               流水线集成 TB（含 ECALL/forward/load-use/flush）
    │   ├── tb_topmode_switch.v            cpu_top 模式切换
    │   └── tb_speedup_demo.v              SW + HW counter 同程序对比
    ├── constrs_1/top.xdc
    └── _archive/                          早期版本（不参与编译）
```

## 一键回归

```bash
cd cpu_project.srcs
make                          # 22 个 TB 全跑（12 单周期 + 10 pipeline）
                              # 预期：TOTAL: 22 PASS, 0 FAIL
make clean                    # 清 /tmp/cpu_tb_*
make tb_pipe_forward_raw      # 跑单个 TB
make speedup_demo             # 流水 vs 单周期 cycle 数对比
```

依赖：`iverilog` (Icarus Verilog) + `vvp`。所有 TB 用 `-g2012 -Wall` 编译无 warning。

## Bonus 功能（对应 demand.txt §3.2）

### ECALL (max 2 分) — 已实现 ✓

- `ctrl.v` 精确译码 ECALL：要求 `funct12=0, funct3=000, rs1=x0, rd=x0` 四字段全匹配
- EBREAK、保留 SYSTEM 编码、非法 funct12/rs1/rd 全部当作 NOP，不会误触发
- 单周期：`cpu.v` 第 170 行 `next_pc = ecall_trap ? ECALL_HANDLER_PC : ...`
- 流水线：在 EX 阶段触发 `branch_redirect`，flush ID/EX，跳 `0x80` handler
- handler 自包含（不存返回 PC，handler 内 JAL 自循环）

测试：`tb_cpu_ecall.v`、`tb_pipe_ecall.v`（含 `0x00008073` 这种 rs1=x1 的保留编码必须当 NOP）

### Pipeline (max 6 分) — 已实现 ✓

- 5 级流水：IF (在 B 的 ifetch.v) | ID | EX | MEM | WB
- 单周期 + 流水共存于 `cpu_top.v`，通过 `mode_select` 切换（boot-time 配置位）
- 完整覆盖 control hazard + data hazard：
  - **Forwarding**：EX/MEM→EX、MEM/WB→EX、store_data forward
  - **Load-use stall**：1 拍 + ID/EX bubble，按 opcode gate uses_rs1/rs2 避免误判
  - **WB→ID bypass**：解决 RF async-read 与同周期 WB 写入的 race
  - **Branch/JAL/JALR/ECALL flush**：EX 阶段解析 → flush ID/EX + B prefetch 2 拍 bubble
  - **IF/ID held buffer**：stall 期间 A 内部缓存 B 的 prefetch，stall 释放时取回
- `cpu_step` 单步语义：一拍推动整个流水线，可观察 bubble
- HW cycle / inst_retired counter，准确跟踪退休（非"inst != NOP"启发式）

测试：9 个 `tb_pipe_*` + `tb_topmode_switch` + `tb_speedup_demo`

## A↔B 接口契约

详见仓库外的 `/home/yun/CS202/接口对齐检查单.md`。

A 的两个 CPU 核（`cpu.v` 单周期、`cpu_pipe.v` 流水）暴露完全相同的端口给 B：
- 取指：`next_pc / pc_we / branch_redirect ← pc_out / inst_out / pc_fetch`
- 访存：`mem_addr / mem_wdata / mem_be / mem_we ← mem_rdata`
- Debug：`dbg_reg_addr → dbg_reg_data`

A 不直接动 PC（PC 在 B 的 `ifetch.v` 里），不直接动 IMem/DMem 内容。

## 已修复的 bug 记录

详见 `/home/yun/.claude/plans/bonus-pipeline-declarative-sparrow.md` 的实施日志。摘要：

| Bug | 来源 | 修法 |
|---|---|---|
| ctrl JALR 不校验 funct3 | Codex 复核 | 加 `funct3 == 3'b000` |
| ctrl shift 只看 funct7[5] | Codex 复核 | 完整 funct7 校验 |
| ctrl branch 保留 funct3 未挡 | Codex 复核 | 只对合法 funct3 拉 branch |
| ctrl ECALL 未精确译码 | Codex 复核 | 四字段全匹配 |
| IF/ID stall 释放丢指令 | 实现期发现 | A 内 held buffer 一拍缓存 |
| WB→ID async-read race | 实现期发现 | WB→ID bypass mux |
| hazard 误判立即数为 rs2 | 静态复核 | uses_rs1/rs2 按 opcode gate |
| tb_speedup_demo NBA race (cycle 偏差) | 静态复核 | task 退出后 `#1` 跨 NBA region |

## 提交时打包

按 demand.txt §4.2.1 的要求，提交目录应为 `c_rv_姓名列表/`，结构：

```
c_rv_xxx/
├── cpu_project/             ← 当前仓库内容（含 cpu_project.srcs、xpr 等）
├── assembly/                ← 当前 cpu_project/assembly 移到这里
├── other/                   ← bonus 相关其他工具/文档（可选）
└── gitlog.txt               ← git log dump
```

打包脚本提示：
```bash
mkdir -p /tmp/c_rv_xxx
cp -r cpu_project /tmp/c_rv_xxx/cpu_project
mv /tmp/c_rv_xxx/cpu_project/assembly /tmp/c_rv_xxx/assembly
git log > /tmp/c_rv_xxx/gitlog.txt
cd /tmp && zip -r c_rv_xxx.zip c_rv_xxx
```
