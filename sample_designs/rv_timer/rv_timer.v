module rv_timer (
	clk_i,
	rst_ni,
	tl_i,
	tl_o,
	alert_rx_i,
	alert_tx_o,
	racl_policies_i,
	racl_error_o,
	intr_timer_expired_hart0_timer0_o
);
	localparam signed [31:0] rv_timer_reg_pkg_NumAlerts = 1;
	parameter [0:0] AlertAsyncOn = {rv_timer_reg_pkg_NumAlerts {1'b1}};
	parameter [31:0] AlertSkewCycles = 1;
	parameter [0:0] EnableRacl = 1'b0;
	parameter [0:0] RaclErrorRsp = EnableRacl;
	localparam signed [31:0] rv_timer_reg_pkg_NumRegs = 10;
	function automatic integer prim_util_pkg_vbits;
		input integer value;
		prim_util_pkg_vbits = (value == 1 ? 1 : $clog2(value));
	endfunction
	localparam [31:0] top_racl_pkg_NrRaclPolicies = 3;
	localparam [31:0] top_racl_pkg_RaclPolicySelLen = prim_util_pkg_vbits(top_racl_pkg_NrRaclPolicies);
	parameter [(rv_timer_reg_pkg_NumRegs * top_racl_pkg_RaclPolicySelLen) - 1:0] RaclPolicySelVec = {rv_timer_reg_pkg_NumRegs {0}};
	input clk_i;
	input rst_ni;
	localparam signed [31:0] prim_mubi_pkg_MuBi4Width = 4;
	localparam signed [31:0] tlul_pkg_DataIntgWidth = 7;
	localparam signed [31:0] tlul_pkg_H2DCmdIntgWidth = 7;
	localparam signed [31:0] top_pkg_TL_AUW = 28;
	localparam signed [31:0] tlul_pkg_RsvdWidth = ((top_pkg_TL_AUW - prim_mubi_pkg_MuBi4Width) - tlul_pkg_H2DCmdIntgWidth) - tlul_pkg_DataIntgWidth;
	localparam signed [31:0] top_pkg_TL_AIW = 8;
	localparam signed [31:0] top_pkg_TL_AW = 32;
	localparam signed [31:0] top_pkg_TL_DW = 32;
	localparam signed [31:0] top_pkg_TL_DBW = top_pkg_TL_DW >> 3;
	localparam signed [31:0] top_pkg_TL_SZW = $clog2($clog2(top_pkg_TL_DBW) + 1);
	input wire [((((((7 + top_pkg_TL_SZW) + top_pkg_TL_AIW) + top_pkg_TL_AW) + top_pkg_TL_DBW) + top_pkg_TL_DW) + (((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth)) + 0:0] tl_i;
	localparam signed [31:0] tlul_pkg_D2HRspIntgWidth = 7;
	localparam signed [31:0] top_pkg_TL_DIW = 1;
	output wire [(((((7 + top_pkg_TL_SZW) + top_pkg_TL_AIW) + top_pkg_TL_DIW) + top_pkg_TL_DW) + (tlul_pkg_D2HRspIntgWidth + tlul_pkg_DataIntgWidth)) + 1:0] tl_o;
	input wire [3:0] alert_rx_i;
	output wire [1:0] alert_tx_o;
	localparam [31:0] top_racl_pkg_NrRaclBits = 4;
	input wire [95:0] racl_policies_i;
	localparam [31:0] top_racl_pkg_NrCtnUidBits = 5;
	output wire [43:0] racl_error_o;
	output wire intr_timer_expired_hart0_timer0_o;
	wire [156:0] reg2hw;
	wire [67:0] hw2reg;
	localparam signed [31:0] rv_timer_reg_pkg_N_HARTS = 1;
	wire [0:0] active;
	wire [11:0] prescaler;
	wire [7:0] step;
	wire [0:0] tick;
	wire [63:0] mtime_d [0:0];
	wire [63:0] mtime [0:0];
	localparam signed [31:0] rv_timer_reg_pkg_N_TIMERS = 1;
	wire [((rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) * 64) - 1:0] mtimecmp;
	wire mtimecmp_update [0:0][0:0];
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_timer_set;
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_timer_en;
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_timer_test_q;
	wire [0:0] intr_timer_test_qe;
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_timer_state_q;
	wire [0:0] intr_timer_state_de;
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_timer_state_d;
	wire [(rv_timer_reg_pkg_N_HARTS * rv_timer_reg_pkg_N_TIMERS) - 1:0] intr_out;
	assign active[0] = reg2hw[154];
	assign prescaler = {reg2hw[141-:12]};
	assign step = {reg2hw[149-:8]};
	assign hw2reg[0] = tick[0];
	assign hw2reg[33] = tick[0];
	assign hw2reg[32-:32] = mtime_d[0][63:32];
	assign hw2reg[65-:32] = mtime_d[0][31:0];
	assign mtime[0] = {reg2hw[97-:32], reg2hw[129-:32]};
	assign mtimecmp = {reg2hw[32-:32], reg2hw[65-:32]};
	assign mtimecmp_update[0][0] = reg2hw[0] | reg2hw[33];
	assign intr_timer_expired_hart0_timer0_o = intr_out[0];
	assign intr_timer_en = reg2hw[153];
	assign intr_timer_state_q = reg2hw[152];
	assign intr_timer_test_q = reg2hw[151];
	assign intr_timer_test_qe = reg2hw[150];
	assign hw2reg[66] = intr_timer_state_de | mtimecmp_update[0][0];
	assign hw2reg[67] = intr_timer_state_d & ~mtimecmp_update[0][0];
	genvar _gv_h_1;
	generate
		for (_gv_h_1 = 0; _gv_h_1 < rv_timer_reg_pkg_N_HARTS; _gv_h_1 = _gv_h_1 + 1) begin : gen_harts
			localparam h = _gv_h_1;
			prim_intr_hw #(.Width(rv_timer_reg_pkg_N_TIMERS)) u_intr_hw(
				.clk_i(clk_i),
				.rst_ni(rst_ni),
				.event_intr_i(intr_timer_set),
				.reg2hw_intr_enable_q_i(intr_timer_en[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS]),
				.reg2hw_intr_test_q_i(intr_timer_test_q[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS]),
				.reg2hw_intr_test_qe_i(intr_timer_test_qe[h]),
				.reg2hw_intr_state_q_i(intr_timer_state_q[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS]),
				.hw2reg_intr_state_de_o(intr_timer_state_de),
				.hw2reg_intr_state_d_o(intr_timer_state_d[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS]),
				.intr_o(intr_out[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS])
			);
			timer_core #(.N(rv_timer_reg_pkg_N_TIMERS)) u_core(
				.clk_i(clk_i),
				.rst_ni(rst_ni),
				.active(active[h]),
				.prescaler(prescaler[-h * 12+:12]),
				.step(step[-h * 8+:8]),
				.tick(tick[h]),
				.mtime_d(mtime_d[h]),
				.mtime(mtime[h]),
				.mtimecmp(mtimecmp[64 * (-h * rv_timer_reg_pkg_N_TIMERS)+:64]),
				.intr(intr_timer_set[h * rv_timer_reg_pkg_N_TIMERS+:rv_timer_reg_pkg_N_TIMERS])
			);
		end
	endgenerate
	wire [0:0] alert_test;
	wire [0:0] alerts;
	rv_timer_reg_top #(
		.EnableRacl(EnableRacl),
		.RaclErrorRsp(RaclErrorRsp),
		.RaclPolicySelVec(RaclPolicySelVec)
	) u_reg(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.tl_i(tl_i),
		.tl_o(tl_o),
		.reg2hw(reg2hw),
		.hw2reg(hw2reg),
		.racl_policies_i(racl_policies_i),
		.racl_error_o(racl_error_o),
		.intg_err_o(alerts[0])
	);
	assign alert_test = {reg2hw[156] & reg2hw[155]};
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < rv_timer_reg_pkg_NumAlerts; _gv_i_2 = _gv_i_2 + 1) begin : gen_alert_tx
			localparam i = _gv_i_2;
			prim_alert_sender #(
				.AsyncOn(AlertAsyncOn[i]),
				.SkewCycles(AlertSkewCycles),
				.IsFatal(1'b1)
			) u_prim_alert_sender(
				.clk_i(clk_i),
				.rst_ni(rst_ni),
				.alert_test_i(alert_test[i]),
				.alert_req_i(alerts[0]),
				.alert_ack_o(),
				.alert_state_o(),
				.alert_rx_i(alert_rx_i[i * 4+:4]),
				.alert_tx_o(alert_tx_o[i * 2+:2])
			);
		end
	endgenerate
endmodule
