module rv_timer_reg_top (
	clk_i,
	rst_ni,
	tl_i,
	tl_o,
	reg2hw,
	hw2reg,
	racl_policies_i,
	racl_error_o,
	intg_err_o
);
	reg _sv2v_0;
	parameter [0:0] EnableRacl = 1'b0;
	parameter [0:0] RaclErrorRsp = 1'b1;
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
	output wire [156:0] reg2hw;
	input wire [67:0] hw2reg;
	localparam [31:0] top_racl_pkg_NrRaclBits = 4;
	input wire [95:0] racl_policies_i;
	localparam [31:0] top_racl_pkg_NrCtnUidBits = 5;
	output wire [43:0] racl_error_o;
	output wire intg_err_o;
	localparam signed [31:0] AW = 9;
	localparam signed [31:0] DW = 32;
	localparam signed [31:0] DBW = 4;
	wire reg_we;
	wire reg_re;
	wire [8:0] reg_addr;
	wire [31:0] reg_wdata;
	wire [3:0] reg_be;
	wire [31:0] reg_rdata;
	wire reg_error;
	wire addrmiss;
	reg wr_err;
	reg [31:0] reg_rdata_next;
	wire reg_busy;
	wire [((((((7 + top_pkg_TL_SZW) + top_pkg_TL_AIW) + top_pkg_TL_AW) + top_pkg_TL_DBW) + top_pkg_TL_DW) + (((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth)) + 0:0] tl_reg_h2d;
	wire [(((((7 + top_pkg_TL_SZW) + top_pkg_TL_AIW) + top_pkg_TL_DIW) + top_pkg_TL_DW) + (tlul_pkg_D2HRspIntgWidth + tlul_pkg_DataIntgWidth)) + 1:0] tl_reg_d2h;
	wire intg_err;
	tlul_cmd_intg_chk u_chk(
		.tl_i(tl_i),
		.err_o(intg_err)
	);
	wire reg_we_err;
	reg [9:0] reg_we_check;
	prim_reg_we_check #(.OneHotWidth(10)) u_prim_reg_we_check(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.oh_i(reg_we_check),
		.en_i(reg_we && !addrmiss),
		.err_o(reg_we_err)
	);
	reg err_q;
	always @(posedge clk_i or negedge rst_ni)
		if (!rst_ni)
			err_q <= 1'sb0;
		else if (intg_err || reg_we_err)
			err_q <= 1'b1;
	assign intg_err_o = (err_q | intg_err) | reg_we_err;
	wire [(((((7 + top_pkg_TL_SZW) + top_pkg_TL_AIW) + top_pkg_TL_DIW) + top_pkg_TL_DW) + (tlul_pkg_D2HRspIntgWidth + tlul_pkg_DataIntgWidth)) + 1:0] tl_o_pre;
	tlul_rsp_intg_gen #(
		.EnableRspIntgGen(1),
		.EnableDataIntgGen(1)
	) u_rsp_intg_gen(
		.tl_i(tl_o_pre),
		.tl_o(tl_o)
	);
	assign tl_reg_h2d = tl_i;
	assign tl_o_pre = tl_reg_d2h;
	function automatic [3:0] sv2v_cast_CFE33;
		input reg [3:0] inp;
		sv2v_cast_CFE33 = inp;
	endfunction
	tlul_adapter_reg #(
		.RegAw(AW),
		.RegDw(DW),
		.EnableDataIntgGen(0)
	) u_reg_if(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.tl_i(tl_reg_h2d),
		.tl_o(tl_reg_d2h),
		.en_ifetch_i(sv2v_cast_CFE33(4'h9)),
		.intg_error_o(),
		.we_o(reg_we),
		.re_o(reg_re),
		.addr_o(reg_addr),
		.wdata_o(reg_wdata),
		.be_o(reg_be),
		.busy_i(reg_busy),
		.rdata_i(reg_rdata),
		.error_i(reg_error | (RaclErrorRsp & racl_error_o[43]))
	);
	assign reg_rdata = reg_rdata_next;
	assign reg_error = (addrmiss | wr_err) | intg_err;
	wire alert_test_we;
	wire alert_test_wd;
	wire ctrl_we;
	wire ctrl_qs;
	wire ctrl_wd;
	wire intr_enable0_we;
	wire intr_enable0_qs;
	wire intr_enable0_wd;
	wire intr_state0_we;
	wire intr_state0_qs;
	wire intr_state0_wd;
	wire intr_test0_we;
	wire intr_test0_wd;
	wire cfg0_we;
	wire [11:0] cfg0_prescale_qs;
	wire [11:0] cfg0_prescale_wd;
	wire [7:0] cfg0_step_qs;
	wire [7:0] cfg0_step_wd;
	wire timer_v_lower0_we;
	wire [31:0] timer_v_lower0_qs;
	wire [31:0] timer_v_lower0_wd;
	wire timer_v_upper0_we;
	wire [31:0] timer_v_upper0_qs;
	wire [31:0] timer_v_upper0_wd;
	wire compare_lower0_0_we;
	wire [31:0] compare_lower0_0_qs;
	wire [31:0] compare_lower0_0_wd;
	wire compare_upper0_0_we;
	wire [31:0] compare_upper0_0_qs;
	wire [31:0] compare_upper0_0_wd;
	wire alert_test_qe;
	wire [0:0] alert_test_flds_we;
	assign alert_test_qe = &alert_test_flds_we;
	localparam [31:0] sv2v_uu_u_alert_test_DW = 1;
	localparam [0:0] sv2v_uu_u_alert_test_ext_d_0 = 1'sb0;
	prim_subreg_ext #(.DW(1)) u_alert_test(
		.re(1'b0),
		.we(alert_test_we),
		.wd(alert_test_wd),
		.d(sv2v_uu_u_alert_test_ext_d_0),
		.qre(),
		.qe(alert_test_flds_we[0]),
		.q(reg2hw[156]),
		.ds(),
		.qs()
	);
	assign reg2hw[155] = alert_test_qe;
	localparam signed [31:0] sv2v_uu_u_ctrl_DW = 1;
	localparam [0:0] sv2v_uu_u_ctrl_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(1),
		.SwAccess(3'd0),
		.RESVAL(1'h0),
		.Mubi(1'b0)
	) u_ctrl(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(ctrl_we),
		.wd(ctrl_wd),
		.de(1'b0),
		.d(sv2v_uu_u_ctrl_ext_d_0),
		.qe(),
		.q(reg2hw[154]),
		.ds(),
		.qs(ctrl_qs)
	);
	localparam signed [31:0] sv2v_uu_u_intr_enable0_DW = 1;
	localparam [0:0] sv2v_uu_u_intr_enable0_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(1),
		.SwAccess(3'd0),
		.RESVAL(1'h0),
		.Mubi(1'b0)
	) u_intr_enable0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(intr_enable0_we),
		.wd(intr_enable0_wd),
		.de(1'b0),
		.d(sv2v_uu_u_intr_enable0_ext_d_0),
		.qe(),
		.q(reg2hw[153]),
		.ds(),
		.qs(intr_enable0_qs)
	);
	prim_subreg #(
		.DW(1),
		.SwAccess(3'd3),
		.RESVAL(1'h0),
		.Mubi(1'b0)
	) u_intr_state0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(intr_state0_we),
		.wd(intr_state0_wd),
		.de(hw2reg[66]),
		.d(hw2reg[67]),
		.qe(),
		.q(reg2hw[152]),
		.ds(),
		.qs(intr_state0_qs)
	);
	wire intr_test0_qe;
	wire [0:0] intr_test0_flds_we;
	assign intr_test0_qe = &intr_test0_flds_we;
	localparam [31:0] sv2v_uu_u_intr_test0_DW = 1;
	localparam [0:0] sv2v_uu_u_intr_test0_ext_d_0 = 1'sb0;
	prim_subreg_ext #(.DW(1)) u_intr_test0(
		.re(1'b0),
		.we(intr_test0_we),
		.wd(intr_test0_wd),
		.d(sv2v_uu_u_intr_test0_ext_d_0),
		.qre(),
		.qe(intr_test0_flds_we[0]),
		.q(reg2hw[151]),
		.ds(),
		.qs()
	);
	assign reg2hw[150] = intr_test0_qe;
	localparam signed [31:0] sv2v_uu_u_cfg0_prescale_DW = 12;
	localparam [11:0] sv2v_uu_u_cfg0_prescale_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(12),
		.SwAccess(3'd0),
		.RESVAL(12'h000),
		.Mubi(1'b0)
	) u_cfg0_prescale(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(cfg0_we),
		.wd(cfg0_prescale_wd),
		.de(1'b0),
		.d(sv2v_uu_u_cfg0_prescale_ext_d_0),
		.qe(),
		.q(reg2hw[141-:12]),
		.ds(),
		.qs(cfg0_prescale_qs)
	);
	localparam signed [31:0] sv2v_uu_u_cfg0_step_DW = 8;
	localparam [7:0] sv2v_uu_u_cfg0_step_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(8),
		.SwAccess(3'd0),
		.RESVAL(8'h01),
		.Mubi(1'b0)
	) u_cfg0_step(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(cfg0_we),
		.wd(cfg0_step_wd),
		.de(1'b0),
		.d(sv2v_uu_u_cfg0_step_ext_d_0),
		.qe(),
		.q(reg2hw[149-:8]),
		.ds(),
		.qs(cfg0_step_qs)
	);
	prim_subreg #(
		.DW(32),
		.SwAccess(3'd0),
		.RESVAL(32'h00000000),
		.Mubi(1'b0)
	) u_timer_v_lower0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(timer_v_lower0_we),
		.wd(timer_v_lower0_wd),
		.de(hw2reg[33]),
		.d(hw2reg[65-:32]),
		.qe(),
		.q(reg2hw[129-:32]),
		.ds(),
		.qs(timer_v_lower0_qs)
	);
	prim_subreg #(
		.DW(32),
		.SwAccess(3'd0),
		.RESVAL(32'h00000000),
		.Mubi(1'b0)
	) u_timer_v_upper0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(timer_v_upper0_we),
		.wd(timer_v_upper0_wd),
		.de(hw2reg[0]),
		.d(hw2reg[32-:32]),
		.qe(),
		.q(reg2hw[97-:32]),
		.ds(),
		.qs(timer_v_upper0_qs)
	);
	wire compare_lower0_0_qe;
	wire [0:0] compare_lower0_0_flds_we;
	prim_flop #(
		.Width(1),
		.ResetValue(0)
	) u_compare_lower0_00_qe(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.d_i(&compare_lower0_0_flds_we),
		.q_o(compare_lower0_0_qe)
	);
	localparam signed [31:0] sv2v_uu_u_compare_lower0_0_DW = 32;
	localparam [31:0] sv2v_uu_u_compare_lower0_0_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(32),
		.SwAccess(3'd0),
		.RESVAL(32'hffffffff),
		.Mubi(1'b0)
	) u_compare_lower0_0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(compare_lower0_0_we),
		.wd(compare_lower0_0_wd),
		.de(1'b0),
		.d(sv2v_uu_u_compare_lower0_0_ext_d_0),
		.qe(compare_lower0_0_flds_we[0]),
		.q(reg2hw[65-:32]),
		.ds(),
		.qs(compare_lower0_0_qs)
	);
	assign reg2hw[33] = compare_lower0_0_qe;
	wire compare_upper0_0_qe;
	wire [0:0] compare_upper0_0_flds_we;
	prim_flop #(
		.Width(1),
		.ResetValue(0)
	) u_compare_upper0_00_qe(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.d_i(&compare_upper0_0_flds_we),
		.q_o(compare_upper0_0_qe)
	);
	localparam signed [31:0] sv2v_uu_u_compare_upper0_0_DW = 32;
	localparam [31:0] sv2v_uu_u_compare_upper0_0_ext_d_0 = 1'sb0;
	prim_subreg #(
		.DW(32),
		.SwAccess(3'd0),
		.RESVAL(32'hffffffff),
		.Mubi(1'b0)
	) u_compare_upper0_0(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.we(compare_upper0_0_we),
		.wd(compare_upper0_0_wd),
		.de(1'b0),
		.d(sv2v_uu_u_compare_upper0_0_ext_d_0),
		.qe(compare_upper0_0_flds_we[0]),
		.q(reg2hw[32-:32]),
		.ds(),
		.qs(compare_upper0_0_qs)
	);
	assign reg2hw[0] = compare_upper0_0_qe;
	reg [9:0] addr_hit;
	wire [15:0] racl_role_vec;
	wire [3:0] racl_role;
	reg [9:0] racl_addr_hit_read;
	reg [9:0] racl_addr_hit_write;
	function automatic [3:0] sv2v_cast_1A4F1;
		input reg [3:0] inp;
		sv2v_cast_1A4F1 = inp;
	endfunction
	function automatic [3:0] top_racl_pkg_tlul_extract_racl_role_bits;
		input reg [tlul_pkg_RsvdWidth - 1:0] rsvd;
		reg unused_rsvd_bits;
		begin
			unused_rsvd_bits = ^{rsvd};
			top_racl_pkg_tlul_extract_racl_role_bits = sv2v_cast_1A4F1(rsvd[8:5]);
		end
	endfunction
	generate
		if (EnableRacl) begin : gen_racl_role_logic
			assign racl_role = top_racl_pkg_tlul_extract_racl_role_bits(tl_i[((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 0) - (((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) - 1) - (tlul_pkg_RsvdWidth + 17))-:((tlul_pkg_RsvdWidth + 17) >= 18 ? tlul_pkg_RsvdWidth : 19 - (tlul_pkg_RsvdWidth + 17))]);
			prim_onehot_enc #(.OneHotWidth(16)) u_racl_role_encode(
				.in_i(racl_role),
				.en_i(1'b1),
				.out_o(racl_role_vec)
			);
		end
		else begin : gen_no_racl_role_logic
			assign racl_role = 1'sb0;
			assign racl_role_vec = 1'sb0;
		end
	endgenerate
	localparam signed [31:0] rv_timer_reg_pkg_BlockAw = 9;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_ALERT_TEST_OFFSET = 9'h000;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_CFG0_OFFSET = 9'h10c;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_COMPARE_LOWER0_0_OFFSET = 9'h118;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_COMPARE_UPPER0_0_OFFSET = 9'h11c;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_CTRL_OFFSET = 9'h004;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_INTR_ENABLE0_OFFSET = 9'h100;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_INTR_STATE0_OFFSET = 9'h104;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_INTR_TEST0_OFFSET = 9'h108;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_TIMER_V_LOWER0_OFFSET = 9'h110;
	localparam [8:0] rv_timer_reg_pkg_RV_TIMER_TIMER_V_UPPER0_OFFSET = 9'h114;
	always @(*) begin
		if (_sv2v_0)
			;
		racl_addr_hit_read = 1'sb0;
		racl_addr_hit_write = 1'sb0;
		addr_hit[0] = reg_addr == rv_timer_reg_pkg_RV_TIMER_ALERT_TEST_OFFSET;
		addr_hit[1] = reg_addr == rv_timer_reg_pkg_RV_TIMER_CTRL_OFFSET;
		addr_hit[2] = reg_addr == rv_timer_reg_pkg_RV_TIMER_INTR_ENABLE0_OFFSET;
		addr_hit[3] = reg_addr == rv_timer_reg_pkg_RV_TIMER_INTR_STATE0_OFFSET;
		addr_hit[4] = reg_addr == rv_timer_reg_pkg_RV_TIMER_INTR_TEST0_OFFSET;
		addr_hit[5] = reg_addr == rv_timer_reg_pkg_RV_TIMER_CFG0_OFFSET;
		addr_hit[6] = reg_addr == rv_timer_reg_pkg_RV_TIMER_TIMER_V_LOWER0_OFFSET;
		addr_hit[7] = reg_addr == rv_timer_reg_pkg_RV_TIMER_TIMER_V_UPPER0_OFFSET;
		addr_hit[8] = reg_addr == rv_timer_reg_pkg_RV_TIMER_COMPARE_LOWER0_0_OFFSET;
		addr_hit[9] = reg_addr == rv_timer_reg_pkg_RV_TIMER_COMPARE_UPPER0_0_OFFSET;
		if (EnableRacl) begin : gen_racl_hit
			begin : sv2v_autoblock_1
				reg [31:0] slice_idx;
				for (slice_idx = 0; slice_idx < 10; slice_idx = slice_idx + 1)
					begin
						racl_addr_hit_read[slice_idx] = addr_hit[slice_idx] & |(racl_policies_i[(RaclPolicySelVec[(9 - slice_idx) * top_racl_pkg_RaclPolicySelLen+:top_racl_pkg_RaclPolicySelLen] * 32) + 15-:16] & racl_role_vec);
						racl_addr_hit_write[slice_idx] = addr_hit[slice_idx] & |(racl_policies_i[(RaclPolicySelVec[(9 - slice_idx) * top_racl_pkg_RaclPolicySelLen+:top_racl_pkg_RaclPolicySelLen] * 32) + 31-:16] & racl_role_vec);
					end
			end
		end
		else begin : gen_no_racl
			racl_addr_hit_read = addr_hit;
			racl_addr_hit_write = addr_hit;
		end
	end
	assign addrmiss = (reg_re || reg_we ? ~|addr_hit : 1'b0);
	assign racl_error_o[43] = |addr_hit & ((reg_re & ~|racl_addr_hit_read) | (reg_we & ~|racl_addr_hit_write));
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	assign racl_error_o[31-:top_pkg_TL_AW] = sv2v_cast_32(reg_addr);
	assign racl_error_o[41-:4] = racl_role;
	assign racl_error_o[42] = 1'b0;
	function automatic [4:0] sv2v_cast_CEF44;
		input reg [4:0] inp;
		sv2v_cast_CEF44 = inp;
	endfunction
	function automatic [4:0] top_racl_pkg_tlul_extract_ctn_uid_bits;
		input reg [tlul_pkg_RsvdWidth - 1:0] rsvd;
		reg unused_rsvd_bits;
		begin
			unused_rsvd_bits = ^{rsvd};
			top_racl_pkg_tlul_extract_ctn_uid_bits = sv2v_cast_CEF44(rsvd[4:0]);
		end
	endfunction
	generate
		if (EnableRacl) begin : gen_racl_log
			assign racl_error_o[37-:5] = top_racl_pkg_tlul_extract_ctn_uid_bits(tl_i[((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 0) - (((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) - 1) - (tlul_pkg_RsvdWidth + 17))-:((tlul_pkg_RsvdWidth + 17) >= 18 ? tlul_pkg_RsvdWidth : 19 - (tlul_pkg_RsvdWidth + 17))]);
			assign racl_error_o[32] = tl_i[6 + (top_pkg_TL_SZW + (top_pkg_TL_AIW + (top_pkg_TL_AW + (top_pkg_TL_DBW + (top_pkg_TL_DW + ((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 0))))))-:((6 + (top_pkg_TL_SZW + ((32'sd8 + 32'sd32) + (top_pkg_TL_DBW + (32'sd32 + ((tlul_pkg_RsvdWidth + (32'sd4 + 32'sd7)) + 7)))))) >= (3 + (top_pkg_TL_SZW + ((32'sd8 + 32'sd32) + (top_pkg_TL_DBW + (32'sd32 + ((tlul_pkg_RsvdWidth + (32'sd4 + 32'sd7)) + 8)))))) ? ((6 + (top_pkg_TL_SZW + (top_pkg_TL_AIW + (top_pkg_TL_AW + (top_pkg_TL_DBW + (top_pkg_TL_DW + ((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 0))))))) - (3 + (top_pkg_TL_SZW + (top_pkg_TL_AIW + (top_pkg_TL_AW + (top_pkg_TL_DBW + (top_pkg_TL_DW + ((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 1)))))))) + 1 : ((3 + (top_pkg_TL_SZW + (top_pkg_TL_AIW + (top_pkg_TL_AW + (top_pkg_TL_DBW + (top_pkg_TL_DW + ((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 1))))))) - (6 + (top_pkg_TL_SZW + (top_pkg_TL_AIW + (top_pkg_TL_AW + (top_pkg_TL_DBW + (top_pkg_TL_DW + ((((tlul_pkg_RsvdWidth + prim_mubi_pkg_MuBi4Width) + tlul_pkg_H2DCmdIntgWidth) + tlul_pkg_DataIntgWidth) + 0)))))))) + 1)] == 3'h4;
		end
		else begin : gen_no_racl_log
			assign racl_error_o[37-:5] = 1'sb0;
			assign racl_error_o[32] = 1'b0;
		end
	endgenerate
	localparam [39:0] rv_timer_reg_pkg_RV_TIMER_PERMIT = 40'b0001000100010001000101111111111111111111;
	always @(*) begin
		if (_sv2v_0)
			;
		wr_err = reg_we & ((((((((((racl_addr_hit_write[0] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[36+:4] & ~reg_be)) | (racl_addr_hit_write[1] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[32+:4] & ~reg_be))) | (racl_addr_hit_write[2] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[28+:4] & ~reg_be))) | (racl_addr_hit_write[3] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[24+:4] & ~reg_be))) | (racl_addr_hit_write[4] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[20+:4] & ~reg_be))) | (racl_addr_hit_write[5] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[16+:4] & ~reg_be))) | (racl_addr_hit_write[6] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[12+:4] & ~reg_be))) | (racl_addr_hit_write[7] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[8+:4] & ~reg_be))) | (racl_addr_hit_write[8] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[4+:4] & ~reg_be))) | (racl_addr_hit_write[9] & |(rv_timer_reg_pkg_RV_TIMER_PERMIT[0+:4] & ~reg_be)));
	end
	assign alert_test_we = (racl_addr_hit_write[0] & reg_we) & !reg_error;
	assign alert_test_wd = reg_wdata[0];
	assign ctrl_we = (racl_addr_hit_write[1] & reg_we) & !reg_error;
	assign ctrl_wd = reg_wdata[0];
	assign intr_enable0_we = (racl_addr_hit_write[2] & reg_we) & !reg_error;
	assign intr_enable0_wd = reg_wdata[0];
	assign intr_state0_we = (racl_addr_hit_write[3] & reg_we) & !reg_error;
	assign intr_state0_wd = reg_wdata[0];
	assign intr_test0_we = (racl_addr_hit_write[4] & reg_we) & !reg_error;
	assign intr_test0_wd = reg_wdata[0];
	assign cfg0_we = (racl_addr_hit_write[5] & reg_we) & !reg_error;
	assign cfg0_prescale_wd = reg_wdata[11:0];
	assign cfg0_step_wd = reg_wdata[23:16];
	assign timer_v_lower0_we = (racl_addr_hit_write[6] & reg_we) & !reg_error;
	assign timer_v_lower0_wd = reg_wdata[31:0];
	assign timer_v_upper0_we = (racl_addr_hit_write[7] & reg_we) & !reg_error;
	assign timer_v_upper0_wd = reg_wdata[31:0];
	assign compare_lower0_0_we = (racl_addr_hit_write[8] & reg_we) & !reg_error;
	assign compare_lower0_0_wd = reg_wdata[31:0];
	assign compare_upper0_0_we = (racl_addr_hit_write[9] & reg_we) & !reg_error;
	assign compare_upper0_0_wd = reg_wdata[31:0];
	always @(*) begin
		if (_sv2v_0)
			;
		reg_we_check[0] = alert_test_we;
		reg_we_check[1] = ctrl_we;
		reg_we_check[2] = intr_enable0_we;
		reg_we_check[3] = intr_state0_we;
		reg_we_check[4] = intr_test0_we;
		reg_we_check[5] = cfg0_we;
		reg_we_check[6] = timer_v_lower0_we;
		reg_we_check[7] = timer_v_upper0_we;
		reg_we_check[8] = compare_lower0_0_we;
		reg_we_check[9] = compare_upper0_0_we;
	end
	always @(*) begin
		if (_sv2v_0)
			;
		reg_rdata_next = 1'sb0;
		(* full_case, parallel_case *)
		case (1'b1)
			racl_addr_hit_read[0]: reg_rdata_next[0] = 1'sb0;
			racl_addr_hit_read[1]: reg_rdata_next[0] = ctrl_qs;
			racl_addr_hit_read[2]: reg_rdata_next[0] = intr_enable0_qs;
			racl_addr_hit_read[3]: reg_rdata_next[0] = intr_state0_qs;
			racl_addr_hit_read[4]: reg_rdata_next[0] = 1'sb0;
			racl_addr_hit_read[5]: begin
				reg_rdata_next[11:0] = cfg0_prescale_qs;
				reg_rdata_next[23:16] = cfg0_step_qs;
			end
			racl_addr_hit_read[6]: reg_rdata_next[31:0] = timer_v_lower0_qs;
			racl_addr_hit_read[7]: reg_rdata_next[31:0] = timer_v_upper0_qs;
			racl_addr_hit_read[8]: reg_rdata_next[31:0] = compare_lower0_0_qs;
			racl_addr_hit_read[9]: reg_rdata_next[31:0] = compare_upper0_0_qs;
			default: reg_rdata_next = 1'sb1;
		endcase
	end
	wire shadow_busy;
	assign shadow_busy = 1'b0;
	assign reg_busy = shadow_busy;
	wire unused_wdata;
	wire unused_be;
	assign unused_wdata = ^reg_wdata;
	assign unused_be = ^reg_be;
	wire unused_policy_sel;
	assign unused_policy_sel = ^racl_policies_i;
	initial _sv2v_0 = 0;
endmodule
