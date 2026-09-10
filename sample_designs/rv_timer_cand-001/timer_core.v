module timer_core (
	clk_i,
	rst_ni,
	active,
	prescaler,
	step,
	tick,
	mtime_d,
	mtime,
	mtimecmp,
	intr
);
	parameter signed [31:0] N = 1;
	input clk_i;
	input rst_ni;
	input active;
	input [11:0] prescaler;
	input [7:0] step;
	output wire tick;
	output wire [63:0] mtime_d;
	input [63:0] mtime;
	input [(N * 64) - 1:0] mtimecmp;
	output wire [N - 1:0] intr;
	reg [11:0] tick_count;
	always @(posedge clk_i or negedge rst_ni) begin : generate_tick
		if (!rst_ni)
			tick_count <= 12'h000;
		else if (!active)
			tick_count <= 12'h000;
		else if (tick_count == prescaler)
			tick_count <= 12'h000;
		else
			tick_count <= tick_count + 1'b1;
	end
	assign tick = active & (tick_count >= prescaler);
	// apex(timing): The critical path is the timer feedback add from the
	// lower mtime register through this combinational update into the upper
	// mtime register.  `step` is only 8 bits, so adding it to the 64-bit timer
	// can be expressed as an 8-bit add, a carry into bits [31:8], and a carry
	// into bits [63:32].  This preserves exactly `mtime + zero_extend(step)`
	// while making the low-to-upper dependency explicit; a generic 64-bit `+`
	// lets the mapper build one long carry cone that it is not obliged to split
	// at this protocol width boundary.
	wire [8:0] mtime_low8_sum;
	wire mtime_carry8;
	wire mtime_carry32;
	assign mtime_low8_sum = {1'b0, mtime[7:0]} + {1'b0, step};
	assign mtime_carry8 = mtime_low8_sum[8];
	assign mtime_carry32 = mtime_carry8 & (&mtime[31:8]);
	assign mtime_d[7:0] = mtime_low8_sum[7:0];
	assign mtime_d[31:8] = mtime[31:8] + {{23 {1'b0}}, mtime_carry8};
	assign mtime_d[63:32] = mtime[63:32] + {{31 {1'b0}}, mtime_carry32};
	genvar _gv_t_1;
	generate
		for (_gv_t_1 = 0; _gv_t_1 < N; _gv_t_1 = _gv_t_1 + 1) begin : gen_intr
			localparam t = _gv_t_1;
			assign intr[t] = active & (mtime >= mtimecmp[((N - 1) - t) * 64+:64]);
		end
	endgenerate
endmodule