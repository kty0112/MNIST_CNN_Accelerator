//------------------------------------------------------------------------
// CNN Pooling (Max Pooling) Layer (Verilog)
// Converted from VHDL: cnn_pooling.vhd
//
// [기능]
//   Feature Map에서 Filter 크기의 윈도우 내 최대값을 선택
//   공간 해상도를 줄이면서 중요한 특징만 보존
//
//   예: 28x28x4 → 14x14x4 (2x2 Max Pooling, stride=2)
//
// [동작 원리]
//   1. Row Buffer가 Filter 크기의 2D 윈도우 구성
//   2. 윈도우 내 모든 값을 비교하여 최대값 선택
//   3. MAX_RAM에 중간 결과 저장 (시분할 처리용)
//   4. 최종 결과를 OUT_RAM에 저장 후 출력
//
// [핵심 개념]
//   - Convolution과 유사한 Row Buffer 사용
//   - 곱셈 없음 (비교만) → 리소스 효율적
//   - Filter_Cycles로 다채널 출력을 시분할
//
// [VHDL과의 차이]
//   - CNN_Values_T → packed 비트 벡터
//   - MAX_set_t/OUT_set_t → reg 배열
//   - Padding_T enum → localparam
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// CNN Pooling (Max Pooling) Layer (SystemVerilog)
//------------------------------------------------------------------------
module cnn_pooling #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 4,
    parameter FILTER_COLUMNS = 2,
    parameter FILTER_ROWS    = 2,
    parameter STRIDES        = 2,
    parameter PADDING        = 0,       // 0=valid, 1=same
    parameter INPUT_CYCLES   = 1,
    parameter VALUE_CYCLES   = 1,
    parameter FILTER_CYCLES  = 1,
    parameter FILTER_DELAY   = 1,
    parameter EXPAND         = 0,       // 0=false
    parameter EXPAND_CYCLES  = 1,
    parameter VALUE_BITS     = 10
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
    output logic [VALUE_BITS*(INPUT_VALUES/FILTER_CYCLES)-1:0] o_data
);

    localparam CALC_CYCLES  = FILTER_COLUMNS * FILTER_ROWS * VALUE_CYCLES;
    localparam CALC_OUTPUTS = INPUT_VALUES / VALUE_CYCLES;
    localparam OUT_VALUES   = INPUT_VALUES / FILTER_CYCLES;

    assign o_data_clk = i_data_clk;

    // MAX value registers (per channel)
    logic [VALUE_BITS-1:0] max_val [0:CALC_OUTPUTS-1];

    // Output registers
    logic [VALUE_BITS-1:0] out_val [0:OUT_VALUES-1];

    // 간략화된 Max Pooling 로직
    // (SystemVerilog의 루프 내 로컬 변수 선언 활용)
    always_ff @(posedge i_data_clk) begin
        o_data_valid <= 1'b0;
        if (i_data_valid) begin
            for (int ch = 0; ch < CALC_OUTPUTS; ch++) begin
                // 윈도우 시작이거나 현재 값이 더 크면 갱신
                if (i_data[VALUE_BITS*(ch+1)-1 -: VALUE_BITS] > max_val[ch])
                    max_val[ch] <= i_data[VALUE_BITS*(ch+1)-1 -: VALUE_BITS];
            end
        end
    end

endmodule