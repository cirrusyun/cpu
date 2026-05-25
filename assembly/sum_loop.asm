# sum_loop.asm — 累加 1..N，N=10 → x11 = 55
# 用于 tb_speedup_demo / tb_topmode_switch
#
# 寄存器约定：
#   x10 = N (counter, 倒计数到 0)
#   x11 = 累加和
#
# 程序结构（PC 字节地址）：
#   0x00  ADDI  x10, x0, 10        // N = 10
#   0x04  ADDI  x11, x0, 0         // sum = 0
#   0x08  ADD   x11, x11, x10      // sum += N        ← loop top
#   0x0C  ADDI  x10, x10, -1       // N--
#   0x10  BNE   x10, x0, -8        // if N != 0, jump back to 0x08
#   0x14  JAL   x0, 0              // halt (self-loop)
#
# 退出条件：x10 == 0
# 期望结果：x11 = 10+9+8+...+1 = 55
#
# 验证 hazard：
#   - ADD x11,x11,x10 读 x11 (前一拍 ADD 的结果 → EX/MEM→EX forward)
#   - ADDI x10,x10,-1 读 x10 (上一拍 ADDI 的结果 → MEM/WB→EX forward)
#   - BNE x10,x0 读 x10 (上一拍 ADDI 的结果 → EX/MEM→EX forward)
#   - 反向跳转 + 2-cycle branch flush
