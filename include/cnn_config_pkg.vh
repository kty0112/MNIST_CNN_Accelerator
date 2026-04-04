//------------------------------------------------------------------------
// CNN Config Package (Verilog Header)
// Converted from VHDL: cnn_config_pkg.vhd
// Original: OnSemi_CNN_Ultra (Leon Beier, Protop Solutions UG, 2020)
//
// VHDL의 CNN 설정 패키지를 Verilog 헤더로 변환.
// VHDL의 subtype/type은 bit-width 파라미터로,
// 함수(relu_f 등)는 Verilog function으로 변환.
//------------------------------------------------------------------------
`ifndef CNN_CONFIG_PKG_VH
`define CNN_CONFIG_PKG_VH

// Resolution parameters
localparam CNN_VALUE_RESOLUTION     = 10;   // 데이터 값 비트 수
localparam CNN_WEIGHT_RESOLUTION    = 8;    // 가중치 비트 수
localparam CNN_PARAMETER_RESOLUTION = 8;    // 파라미터 비트 수

// Input dimensions
localparam CNN_INPUT_COLUMNS = 448;
localparam CNN_INPUT_ROWS    = 448;
localparam CNN_MAX_FILTERS   = 8;

// Values are always positive (ReLU) → no sign bit needed
localparam CNN_VALUE_NEGATIVE = 0;

// CNN_Value_T: 0 ~ 2^10-1 = 0 ~ 1023
localparam CNN_VALUE_BITS = CNN_VALUE_RESOLUTION;  // 10 bits
localparam CNN_VALUE_MAX  = (1 << CNN_VALUE_RESOLUTION) - 1;

// CNN_Weight_T: -(2^7-1) ~ +(2^7-1) = -127 ~ +127
localparam CNN_WEIGHT_BITS = CNN_WEIGHT_RESOLUTION;  // 8 bits (signed)

// Leaky ReLU multiplier: 2^(8-1)/10 = 12
localparam signed [CNN_WEIGHT_BITS-1:0] LEAKY_RELU_MULT = (1 << (CNN_WEIGHT_RESOLUTION-1)) / 10;

//------------------------------------------------------------------------
// VHDL CNN_Stream_T record → Verilog 신호 매핑
//------------------------------------------------------------------------
// Column     : natural range 0 to CNN_Input_Columns-1  → [col_bits-1:0] column
// Row        : natural range 0 to CNN_Input_Rows-1     → [row_bits-1:0] row
// Filter     : natural range 0 to CNN_Max_Filters-1    → [flt_bits-1:0] filter
// Data_Valid : std_logic                                → data_valid
// Data_CLK   : std_logic                                → data_clk
//------------------------------------------------------------------------

// Activation function encoding (VHDL enum → Verilog localparam)
localparam [2:0] ACT_RELU       = 3'd0;
localparam [2:0] ACT_LINEAR     = 3'd1;
localparam [2:0] ACT_LEAKY_RELU = 3'd2;
localparam [2:0] ACT_STEP       = 3'd3;
localparam [2:0] ACT_SIGN       = 3'd4;

// Padding mode encoding
localparam PAD_VALID = 1'b0;
localparam PAD_SAME  = 1'b1;

`endif
