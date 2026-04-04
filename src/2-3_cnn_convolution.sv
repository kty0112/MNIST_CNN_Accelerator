//------------------------------------------------------------------------
// CNN Convolution Layer (SystemVerilog)
//------------------------------------------------------------------------
module cnn_convolution #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 1,
    parameter FILTER_COLUMNS = 3,
    parameter FILTER_ROWS    = 3,
    parameter FILTERS        = 4,
    parameter STRIDES        = 1,
    parameter [2:0] ACTIVATION = 3'd0,  // 0=relu
    parameter PADDING        = 1,       // 0=valid, 1=same
    parameter INPUT_CYCLES   = 1,
    parameter VALUE_CYCLES   = 1,
    parameter CALC_CYCLES    = 1,
    parameter FILTER_CYCLES  = 1,
    parameter FILTER_DELAY   = 1,
    parameter EXPAND         = 1,       // 1=true
    parameter EXPAND_CYCLES  = 0,
    parameter OFFSET_IN      = 0,
    parameter OFFSET_OUT     = 0,
    parameter OFFSET         = 0,
    parameter VALUE_BITS     = 10,
    parameter WEIGHT_BITS    = 8
)(
    // Input stream
    input  logic        i_data_clk,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic [3:0]  i_filter,
    input  logic        i_data_valid,
    input  logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] i_data,

    // Output stream
    output logic        o_data_clk,
    output logic [9:0]  o_column,
    output logic [8:0]  o_row,
    output logic [3:0]  o_filter,
    output logic        o_data_valid,
    output logic [VALUE_BITS*(FILTERS/FILTER_CYCLES)-1:0] o_data
);

    // Derived constants
    localparam MATRIX_VALUES       = FILTER_COLUMNS * FILTER_ROWS;
    localparam MATRIX_VALUE_CYCLES = MATRIX_VALUES * VALUE_CYCLES;
    localparam CALC_FILTERS        = FILTERS / CALC_CYCLES;
    localparam OUT_FILTERS         = FILTERS / FILTER_CYCLES;
    localparam TOTAL_WEIGHTS       = INPUT_VALUES * MATRIX_VALUES;

    // Bit-width for accumulator (enough for sum of products)
    localparam BITS_MAX = VALUE_BITS + OFFSET + $clog2(MATRIX_VALUES * INPUT_VALUES + 1) + 2;

    assign o_data_clk = i_data_clk;

    //------------------------------------------------------------------
    // Weight ROM
    //------------------------------------------------------------------
    logic signed [WEIGHT_BITS-1:0] weight_rom [0:FILTERS*TOTAL_WEIGHTS-1];
    logic signed [WEIGHT_BITS-1:0] bias_rom   [0:FILTERS-1];

    //------------------------------------------------------------------
    // Internal signals
    //------------------------------------------------------------------
    logic signed [BITS_MAX:0] sum [0:CALC_FILTERS-1];
    logic signed [VALUE_BITS:0] act_result [0:CALC_FILTERS-1];

    // ReLU activation function
    function automatic logic signed [VALUE_BITS:0] relu_func(input logic signed [BITS_MAX:0] val);
        if (val > 0) begin
            if (val < (1 << VALUE_BITS) - 1)
                relu_func = val[VALUE_BITS:0];
            else
                relu_func = (1 << VALUE_BITS) - 1;
        end else begin
            relu_func = 0;
        end
    endfunction

endmodule