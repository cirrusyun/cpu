# branch_demo.asm — control hazard 演示（taken branch flush）
# 用于 tb_pipe_branch_flush
#
# 程序（PC 字节地址）：
#   0x00  ADDI  x5, x0, 1          // x5 = 1
#   0x04  BEQ   x5, x5, +12        // 自相等，taken；跳到 PC=4+12=0x10
#                                  //   pipeline: BEQ 在 EX 时，flush ID/EX
#                                  //   后续 2 拍 bubble（IF/ID + ID/EX）
#                                  //   target 第 3 拍才进 EX
#   0x08  ADDI  x6, x0, 99         // SKIPPED — 必须不执行
#   0x0C  ADDI  x7, x0, 88         // SKIPPED — 必须不执行
#   0x10  ADDI  x8, x0, 55         // target — 应执行，x8 = 55
#   0x14  JAL   x0, 0              // halt
#
# 期望结果：x5=1, x6=0 (skipped), x7=0 (skipped), x8=55
