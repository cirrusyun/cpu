# load_use_demo.asm — load-use 冒险演示
# 用于 tb_pipe_load_use
#
# DMem 初始：dmem[0] = 42
#
# 程序（PC 字节地址）：
#   0x00  LW    x6, 0(x0)          // x6 = dmem[0] = 42
#   0x04  ADD   x7, x6, x6         // x7 = x6 + x6   ← load-use！
#                                  //   pipeline 中 LW 在 EX 阶段时，ADD 在 ID，
#                                  //   ADD 的 rs1=rs2=x6 == LW 的 rd
#                                  //   → hazard_unit 检测出 load_use，stall 1 拍
#                                  //   1 拍后 LW 在 MEM/WB，ADD 在 EX，MEM/WB→EX forward
#                                  //   x7 = 42 + 42 = 84
#   0x08  JAL   x0, 0              // halt
#
# 期望结果：x6=42, x7=84
#
# 不修这个 hazard 的话，ADD 会读到 x6 的旧值（0），x7 = 0。
