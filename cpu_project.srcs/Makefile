# A 域 testbench 一键脚本
#   用法：
#     make            ← 默认跑全部 tb，汇总 PASS/FAIL
#     make smoke      ← 只跑 smoke
#     make ecall      ← 只跑 ecall bonus
#     make <tb_name>  ← 跑指定 tb（去掉 tb_ 前缀也可）
#     make clean      ← 清掉 /tmp/cpu_tb_*
#
# 依赖：iverilog (Icarus Verilog) + vvp

IVERILOG := iverilog -g2012
VVP      := vvp
SRC      := sources_1/cpu/*.v
SIM      := sim_1/fake_ifetch.v sim_1/fake_dmem.v
BUILD    := /tmp/cpu_tb

# 所有 testbench（按运行顺序）
ALL_TBS := tb_alu tb_regfile tb_imm_gen tb_load_store_fmt \
           tb_cpu_smoke tb_cpu_flush tb_cpu_branch tb_cpu_jalr tb_cpu_ecall \
           tb_cpu_illegal_decode tb_cpu_halt_step tb_cpu_sanity \
           tb_pipe_forward_raw tb_pipe_load_use tb_pipe_load_to_store \
           tb_pipe_branch_flush tb_pipe_jal_jalr tb_pipe_ecall \
           tb_pipe_halt_step tb_pipe_no_false_stall \
           tb_topmode_switch tb_speedup_demo

.PHONY: all clean smoke flush branch jalr ecall halt_step sanity \
        illegal_decode alu regfile imm_gen load_store_fmt \
        pipe_forward_raw pipe_load_use pipe_load_to_store \
        pipe_branch_flush pipe_jal_jalr pipe_ecall pipe_halt_step \
        topmode_switch speedup_demo

# ──────────────────────────────────────────────
# 默认目标：跑全部 + 汇总
# ──────────────────────────────────────────────
all:
	@PASSCNT=0; FAILCNT=0; \
	for tb in $(ALL_TBS); do \
	    if ! $(IVERILOG) -o $(BUILD)_$$tb $(SRC) $(SIM) sim_1/$$tb.v > $(BUILD)_$$tb.log 2>&1; then \
	        printf "  \033[31mFAIL\033[0m  %s (compile error, see $(BUILD)_%s.log)\n" $$tb $$tb; \
	        FAILCNT=$$((FAILCNT+1)); \
	        continue; \
	    fi; \
	    $(VVP) $(BUILD)_$$tb > $(BUILD)_$$tb.out 2>&1; \
	    VVPRC=$$?; \
	    if [ $$VVPRC -eq 0 ] && grep -q PASS $(BUILD)_$$tb.out; then \
	        printf "  \033[32mPASS\033[0m  %s\n" $$tb; \
	        PASSCNT=$$((PASSCNT+1)); \
	    else \
	        printf "  \033[31mFAIL\033[0m  %s (vvp rc=%d, see $(BUILD)_%s.out)\n" $$tb $$VVPRC $$tb; \
	        FAILCNT=$$((FAILCNT+1)); \
	    fi; \
	done; \
	echo ""; \
	echo "TOTAL: $$PASSCNT PASS, $$FAILCNT FAIL"; \
	[ $$FAILCNT -eq 0 ]

# ──────────────────────────────────────────────
# 单个 testbench
# ──────────────────────────────────────────────
# 别名（去掉 tb_ 前缀）
smoke:     tb_cpu_smoke
flush:     tb_cpu_flush
branch:    tb_cpu_branch
jalr:      tb_cpu_jalr
ecall:     tb_cpu_ecall
illegal_decode: tb_cpu_illegal_decode
halt_step: tb_cpu_halt_step
sanity:    tb_cpu_sanity
alu:       tb_alu
regfile:   tb_regfile
imm_gen:   tb_imm_gen
load_store_fmt: tb_load_store_fmt

# Pipeline bonus
pipe_forward_raw:  tb_pipe_forward_raw
pipe_load_use:     tb_pipe_load_use
pipe_load_to_store: tb_pipe_load_to_store
pipe_branch_flush: tb_pipe_branch_flush
pipe_jal_jalr:     tb_pipe_jal_jalr
pipe_ecall:        tb_pipe_ecall
pipe_halt_step:    tb_pipe_halt_step
topmode_switch:    tb_topmode_switch
speedup_demo:      tb_speedup_demo

# 通用模式：make tb_xxx
tb_%:
	@$(IVERILOG) -o $(BUILD)_$@ $(SRC) $(SIM) sim_1/$@.v
	@$(VVP) $(BUILD)_$@

# ──────────────────────────────────────────────
# 集成测试：用 B 的真 ifetch / dmem 替换 fake_*
#   用法：make integ
#         make integ IFETCH=/path/to/ifetch.v DMEM=/path/to/dmem.v
#
#   要求 B 的 ifetch.v 模块名为 fake_ifetch，dmem.v 模块名为 fake_dmem
#   （或者改 A 的 tb 里实例化名，但更省事的是 B 在自己的真模块里用相同 module 名 + 端口）
#
#   提示：建议 B 直接把自己的真 ifetch.v / dmem.v 命名为 fake_ifetch / fake_dmem（仿真用）
#   或者在 B 的真模块外加一层 wrapper，模块名叫 fake_ifetch、内部例化真 ifetch。
# ──────────────────────────────────────────────
IFETCH ?= sources_1/cpu/ifetch.v
DMEM   ?= sources_1/cpu/dmem.v

CPU_SRC := sources_1/cpu/cpu.v sources_1/cpu/alu.v sources_1/cpu/alu_ctrl.v \
           sources_1/cpu/ctrl.v sources_1/cpu/imm_gen.v \
           sources_1/cpu/load_store_fmt.v sources_1/cpu/reg_file.v \
           sources_1/cpu/cpu_pipe.v sources_1/cpu/hazard_unit.v \
           sources_1/cpu/forward_unit.v sources_1/cpu/cpu_top.v \
           sources_1/cpu/cycle_counter.v

INTEG_TBS := tb_cpu_smoke tb_cpu_flush tb_cpu_branch tb_cpu_jalr tb_cpu_ecall \
             tb_cpu_illegal_decode tb_cpu_halt_step tb_cpu_sanity \
             tb_pipe_forward_raw tb_pipe_load_use tb_pipe_load_to_store \
             tb_pipe_branch_flush tb_pipe_jal_jalr tb_pipe_ecall \
             tb_pipe_halt_step tb_pipe_no_false_stall \
             tb_topmode_switch tb_speedup_demo

.PHONY: integ
integ:
	@if [ ! -f "$(IFETCH)" ]; then \
	    echo "ERROR: IFETCH file not found: $(IFETCH)"; \
	    echo "       Specify with: make integ IFETCH=/path/to/ifetch.v"; exit 1; \
	fi
	@if [ ! -f "$(DMEM)" ]; then \
	    echo "ERROR: DMEM file not found: $(DMEM)"; \
	    echo "       Specify with: make integ DMEM=/path/to/dmem.v"; exit 1; \
	fi
	@echo "Integration test: using"
	@echo "  IFETCH = $(IFETCH)"
	@echo "  DMEM   = $(DMEM)"
	@echo ""
	@PASSCNT=0; FAILCNT=0; \
	for tb in $(INTEG_TBS); do \
	    $(IVERILOG) -o $(BUILD)_integ_$$tb $(CPU_SRC) $(IFETCH) $(DMEM) sim_1/$$tb.v > $(BUILD)_integ_$$tb.log 2>&1; \
	    if [ $$? -ne 0 ]; then \
	        printf "  \033[31mFAIL\033[0m  %s (compile error, see $(BUILD)_integ_%s.log)\n" $$tb $$tb; \
	        FAILCNT=$$((FAILCNT+1)); \
	        continue; \
	    fi; \
	    $(VVP) $(BUILD)_integ_$$tb > $(BUILD)_integ_$$tb.out 2>&1; \
	    VVPRC=$$?; \
	    if [ $$VVPRC -eq 0 ] && grep -q PASS $(BUILD)_integ_$$tb.out; then \
	        printf "  \033[32mPASS\033[0m  %s\n" $$tb; \
	        PASSCNT=$$((PASSCNT+1)); \
	    else \
	        printf "  \033[31mFAIL\033[0m  %s (vvp rc=%d, see $(BUILD)_integ_%s.out)\n" $$tb $$VVPRC $$tb; \
	        FAILCNT=$$((FAILCNT+1)); \
	    fi; \
	done; \
	echo ""; \
	echo "INTEGRATION TOTAL: $$PASSCNT PASS, $$FAILCNT FAIL"; \
	[ $$FAILCNT -eq 0 ]

# ──────────────────────────────────────────────
clean:
	@rm -f $(BUILD)_*
