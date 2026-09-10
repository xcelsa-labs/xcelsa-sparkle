// Clean behavioural Verilog — technology-independent
// Converted from prim_generic/rtl/prim_xnor2.sv (OpenTitan project)
module prim_xnor2 (
	in0_i,
	in1_i,
	out_o
);
	parameter signed [31:0] Width = 1;
	input wire [Width-1:0] in0_i;
	input wire [Width-1:0] in1_i;
	output wire [Width-1:0] out_o;
	assign out_o = ~(in0_i ^ in1_i);
endmodule
