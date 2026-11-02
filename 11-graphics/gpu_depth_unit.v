`timescale 1ns/1ps


// GPU Depth Test Unit

// Compares incoming and stored 24/32-bit depth values.
// The actual depth memory is external and may be placed in DDR or cache.

module gpu_depth_unit (
    input [31:0] new_depth_i,
    input [31:0] old_depth_i,
    input [2:0] compare_mode_i,
    input depth_enable_i,
    input depth_write_enable_i,
    output reg pass_o,
    output write_enable_o
);

    localparam [2:0] DEPTH_NEVER = 3'd0;
    localparam [2:0] DEPTH_LESS = 3'd1;
    localparam [2:0] DEPTH_LEQUAL = 3'd2;
    localparam [2:0] DEPTH_GREATER = 3'd3;
    localparam [2:0] DEPTH_GEQUAL = 3'd4;
    localparam [2:0] DEPTH_EQUAL = 3'd5;
    localparam [2:0] DEPTH_ALWAYS = 3'd6;

    always @* begin
        if (!depth_enable_i) begin

            pass_o = 1'b1;
            
        end else begin
            case (compare_mode_i)
                DEPTH_NEVER: pass_o = 1'b0;
                DEPTH_LESS: pass_o = (new_depth_i < old_depth_i);
                DEPTH_LEQUAL: pass_o = (new_depth_i <= old_depth_i);
                DEPTH_GREATER: pass_o = (new_depth_i > old_depth_i);
                DEPTH_GEQUAL: pass_o = (new_depth_i >= old_depth_i);
                DEPTH_EQUAL: pass_o = (new_depth_i == old_depth_i);
                DEPTH_ALWAYS: pass_o = 1'b1;
                default: pass_o = 1'b0;
            endcase

        end
    end


    assign write_enable_o = pass_o && depth_write_enable_i;

endmodule