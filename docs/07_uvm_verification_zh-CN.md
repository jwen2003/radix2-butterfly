# UVM 验证

[English](07_uvm_verification_EN.md) | 简体中文

## 1. 范围

本文档记录当前面向流水版 Radix-2 Butterfly 的 UVM 1.2 验证环境。该环境以 Vivado XSim 2025.1 为目标，直接验证 `butterfly_pipe`，不实例化 `butterfly_comb` 或任何物理评测包装层。

本文记录的 UVM 运行将少量定向冒烟事务、约束随机激励和随机 bubble 组合在一起。其结果仅为已测试配置提供证据，不能证明设计在所有可能行为下绝对正确。

## 2. DUT 与时序契约

`butterfly_pipe` 是三级流水：

| 流水级 | 工作 | 寄存或对齐的状态 |
|---|---|---|
| 第一级 | 复数加减 | `S`、`D`、`W` 和 `valid_s1` |
| 第二级 | 四路并行实数乘法 | 四个 33 位乘积、旁路的 `Y0` 和 `valid_s2` |
| 第三级 | 34 位乘积加减、RNE 和饱和 | 四路输出、四个饱和标志和 `valid_out` |

若输入在采样沿 `t` 被观察到满足 `rst=0` 且 `valid_in=1`，对应有效输出必须在边沿 `t+2` 出现。因此，核心延迟为两个周期。启动间隔为 `II=1`，允许相邻周期连续输入有效事务，且必须保持事务顺序。

复位为同步高电平有效。当前 UVM 测试只施加初始复位；尚未实现流水中途复位 sequence。

## 3. UVM 结构

验证环境实现在 `tb/uvm/butterfly_uvm_pkg.sv` 中，并通过 `tb/uvm/butterfly_if.sv` 连接。

| 元素 | 职责 |
|---|---|
| `butterfly_item` | 保存六个有符号 Q1.15 输入分量、观察到的输出字段、周期元数据和 `idle_cycles_before` |
| `butterfly_sequence` | 发送七笔固定定向事务，并将 `idle_cycles_before=0` |
| `butterfly_random_sequence` | 生成全范围有符号 16 位约束随机输入，并检查每次 `randomize()` 调用 |
| `butterfly_sequencer` | 为 driver 仲裁 sequence item |
| `butterfly_driver` | 通过 `driver_cb` 驱动 bubble 和有效事务，不计算期望结果 |
| `butterfly_input_monitor` | 仅发布接口上实际观察到的 `rst=0 && valid_in=1` 事务 |
| `butterfly_output_monitor` | 每周期发布 `valid_out`、输出数据和饱和标志 |
| 独立 predictor | 不调用 V0 或 DUT，独立计算期望定点结果 |
| `butterfly_scoreboard` | 检查延迟、顺序、数值、标志、计数和最终队列状态 |
| `butterfly_agent` | 包含 sequencer、driver 和两个 monitor |
| `butterfly_env` | 将 monitor analysis port 连接到 scoreboard |
| `butterfly_test` | 依次运行定向和约束随机 sequence，并排空流水线 |

`tb/uvm/tb_butterfly_uvm_top.sv` 产生 10 ns 时钟，施加初始同步复位，实例化 `butterfly_pipe`，通过 `uvm_config_db` 传递 virtual interface，调用 `run_test("butterfly_test")`，并提供 1 ms 硬超时。

## 4. 激励与 Bubble

定向 sequence 保留七笔明确的冒烟事务，并以 back-to-back 方式发送。它不解析公共 CSV 文件。

约束随机 sequence 默认生成 1,000 笔事务，可通过 `+NUM_RANDOM=<n>` 覆盖数量。`a_re`、`a_im`、`b_re`、`b_im`、`w_re` 和 `w_im` 均在完整的有符号 16 位范围内随机。

`idle_cycles_before` 被约束为 0 至 3，其分布偏向连续吞吐：

| 每笔事务前的 bubble 周期数 | 目标分布 |
|---:|---:|
| 0 | 约 70% |
| 1 | 约 20% |
| 2 或 3 合计 | 约 10% |

gap 为零时，相邻周期可以连续出现有效事务并保持 `II=1`。在 bubble 周期内，driver 保持 `valid_in=0`。input monitor 不发布 bubble 周期，因此 bubble 不会生成 predictor 条目，也不会扰乱事务顺序。

## 5. 基于实际观察事务的数据流

scoreboard 不把 driver 的动作直接当作事务已经到达 DUT 的证明。数据路径为：

```text
sequence → sequencer → driver → interface
                               ↓
                    input monitor → predictor → expected queue

interface → output monitor → scoreboard comparison
```

input monitor 对接口采样，并且只在实际观察到 `rst=0 && valid_in=1` 时发布事务。output monitor 每周期都发布观察结果，包括 `valid_out=0` 的周期，因此 scoreboard 既能发现预期周期缺少有效输出，也能发现没有预期事务时出现有效输出。

driver 和 monitor clocking block 均使用下降沿事件。driver 在 DUT 下一个上升沿采样前半个周期准备输入，monitor 则观察前一个上升沿 DUT 更新后已经稳定的值，从而避免与 DUT 的非阻塞赋值发生竞争。

## 6. 独立定点 Predictor

predictor 不调用也不实例化 `butterfly_comb`、`butterfly_pipe` 或共用 RTL 算术辅助模块，而是独立实现数值契约：

1. 以 17 位有符号结果计算 `S = A + B` 和 `D = A - B`；
2. 执行四个有符号 17×16 位乘法，每个均保留完整的 33 位结果；
3. 对乘积进行符号扩展，并以 34 位计算实部和虚部的乘积组合结果；
4. 使用 round-to-nearest, ties-to-even 将 Q4.30 结果转换为 Q1.15；
5. 先舍入，再做范围检查并饱和到有符号 16 位 Q1.15；
6. 独立计算 `sat_y0_re`、`sat_y0_im`、`sat_y1_re` 和 `sat_y1_im`。

RNE 使用移位后的基值、guard bit、sticky bits 和保留结果的最低有效位。恰好处于中点时，仅当保留结果为奇数才进位。饱和检查在舍入之后执行，因此舍入进位越过 Q1.15 边界的情况能够得到正确处理。

## 7. Scoreboard 检查

input monitor 发布的每笔事务都会产生一个标记为 `input_cycle + 2` 的期望条目。scoreboard 检查：

- `valid_out` 是否恰好在要求的周期拉高；
- 没有到期事务时是否错误出现 `valid_out`；
- expected queue 中的 FIFO 输出顺序；
- `y0_re`、`y0_im`、`y1_re` 和 `y1_im`；
- 四个分量级饱和标志；
- 输入计数与已检查输出计数是否相等；
- 仿真结束时 expected queue 是否为空。

output monitor 每周期发布结果，使延迟检查器能够观察 bubble 的位置，同时又不会向 predictor 插入 bubble 条目。

## 8. 已完成的 XSim 运行

当前已完成的运行使用 Vivado XSim 2025.1 和 UVM 1.2。

| 结果 | 数值 |
|---|---:|
| 定向事务 | 7 |
| 约束随机事务 | 1,000 |
| 事务总数 | 1,007 |
| 随机 bubble | 0 至 3 周期，约 70% / 20% / 10% |
| `inputs` | 1,007 |
| `outputs_checked` | 1,007 |
| `remaining_queue` | 0 |
| `errors` | 0 |
| `UVM_WARNING` | 0 |
| `UVM_ERROR` | 0 |
| `UVM_FATAL` | 0 |
| 正常仿真结束时间 | 24,890 ns |

该结果确认在这一次仿真运行中，定向加约束随机测试通过了当前实现的 predictor、顺序、标志和两周期延迟检查。

## 9. 与 Legacy 回归的关系

现有非 UVM V1 testbench `tb/v1/tb_butterfly_pipe.sv` 也已经在 XSim 下成功重放 `tb/test_vectors/butterfly_common.csv` 中全部 1,071 个 Python 生成向量。

该 legacy 结果与 UVM 结果相互独立。当前 UVM sequence 运行的是七笔明确的定向事务和 1,000 笔新生成的约束随机事务，并未重放 1,071 个 CSV 向量。

## 10. 尚未完成的验证工作

当前 UVM 环境尚未完成：

- mid-flight reset UVM sequence（流水中途复位 UVM sequence）；
- functional coverage；
- SystemVerilog Assertions（`SVA`）；
- 通过 UVM 重放 1,071 个 CSV 向量；
- 多 seed regression；
- 自动化命令行回归；
- coverage closure；
- formal verification（形式验证）。

受这些限制，不能把一次通过的随机测试解释为穷尽验证或绝对正确性的证明。
