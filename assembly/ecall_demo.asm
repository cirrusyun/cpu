# ecall_demo.asm — ECALL bonus 演示
# 用于 tb_pipe_ecall / tb_cpu_ecall
#
# CPU 见到 ECALL 后跳到固定地址 ECALL_HANDLER_PC=0x80。
# 主程序里 ECALL 之后的指令必须被 flush，不能执行。
#
# 主程序（PC 字节地址）：
#   0x00  ADDI  x5,  x0, 7         // x5 = 7
#   0x04  ECALL                    // → 0x80 handler
#   0x08  ADDI  x6,  x0, 99        // SKIPPED (flushed)
#   0x0C  ADDI  x7,  x0, 88        // SKIPPED
#
# Handler（PC 0x80 = mem 字索引 32，hex 文件用 @20 跳过去）：
#   0x80  ADDI  x10, x0, 1         // x10 = 1
#   0x84  ADDI  x11, x0, 2         // x11 = 2
#   0x88  SYSTEM funct12=0 rs1=x1  // reserved encoding，必须当 NOP（ECALL 精确译码不能被骗）
#   0x8C  ADDI  x12, x0, 3         // x12 = 3 （证明上一条 reserved SYSTEM 没触发 trap）
#   0x90  JAL   x0, 0              // halt (self-loop)
#
# 期望结果：x5=7, x6=0, x7=0, x10=1, x11=2, x12=3
