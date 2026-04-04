//------------------------------------------------------------------------
// NN Layer - Fully Connected Layer (Verilog)
// Converted from VHDL: nn_layer.vhd
//
// [기능]
//   전결합(Fully Connected) 레이어 연산
//   모든 입력 뉴런과 모든 출력 뉴런 사이의 가중치 곱을 합산
//
//   이 프로젝트에서는:
//   - 입력: 72개 (3x3x8 = Flatten 결과)
//   - 출력: 10개 (숫자 0~9 각 클래스의 점수)
//   - 가중치: 72*10 + 10(bias) = 730개
//
// [동작 원리]
//   1. 입력이 시분할(Calc_Cycles_In)로 들어옴
//   2. ROM에서 가중치 로드
//   3. MAC(Multiply-Accumulate) 연산
//   4. 모든 입력 처리 완료 시 바이어스 가산
//   5. ReLU 활성화 적용
//   6. OUT_RAM에 저장 후 시분할 출력
//
// [Convolution과의 차이]
//   - Row Buffer 불필요 (공간 구조 없음)
//   - 1D 입력 → 1D 출력
//   - iCycle로 시분할 입력 위치 지정
//
// [VHDL과의 차이]
//   - CNN_Weights_T generic → ROM + parameter
//   - oCycle: natural range → bit vector
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// NN Layer - Fully Connected Layer (SystemVerilog)
//------------------------------------------------------------------------
module nn_layer #(
    parameter INPUTS          = 72,
    parameter OUTPUTS         = 10,
    parameter [2:0] ACTIVATION = 3'd0,  // 0=relu
    parameter CALC_CYCLES_IN  = 72,
    parameter OUT_CYCLES      = 10,
    parameter OUT_DELAY       = 1,
    parameter CALC_CYCLES_OUT = 10,
    parameter OFFSET_IN       = 0,
    parameter OFFSET_OUT      = 0,
    parameter OFFSET          = 0,
    parameter VALUE_BITS      = 10,
    parameter WEIGHT_BITS     = 8
)(
    // Input stream
    input  logic        i_data_clk,
    input  logic        i_data_valid,
    input  logic [VALUE_BITS*(INPUTS/CALC_CYCLES_IN)-1:0] i_data,
    input  logic [$clog2(CALC_CYCLES_IN)-1:0] i_cycle,

    // Output stream
    output logic        o_data_clk,
    output logic        o_data_valid,
    output logic [VALUE_BITS*(OUTPUTS/CALC_CYCLES_OUT)-1:0] o_data,
    output logic [$clog2(OUTPUTS)-1:0] o_cycle
);

    localparam CALC_OUTPUTS = OUTPUTS / OUT_CYCLES;
    localparam CALC_INPUTS  = INPUTS / CALC_CYCLES_IN;
    localparam OUT_VALUES   = OUTPUTS / CALC_CYCLES_OUT;
    localparam OFFSET_DIFF  = OFFSET_OUT - OFFSET_IN;
    localparam VALUE_MAX    = (1 << VALUE_BITS) - 1;
    localparam BITS_MAX     = VALUE_BITS + ((OFFSET > 0) ? OFFSET : 0) + $clog2(INPUTS + 1) + 2;

    assign o_data_clk = i_data_clk;

    //------------------------------------------------------------------
    // Weight ROM
    //------------------------------------------------------------------
    // 가중치 배열: [OUTPUTS][INPUTS+1] (마지막 = bias)
    logic signed [WEIGHT_BITS-1:0] weight_rom [0:OUTPUTS*(INPUTS+1)-1];
    logic signed [WEIGHT_BITS-1:0] bias_rom   [0:OUTPUTS-1];

    //------------------------------------------------------------------
    // MAC 연산
    //------------------------------------------------------------------
    logic signed [BITS_MAX:0] sum [0:CALC_OUTPUTS-1];
    logic signed [VALUE_BITS:0] act_result [0:CALC_OUTPUTS-1];

    // ReLU 활성화 함수
    function automatic logic signed [VALUE_BITS:0] relu_func(input logic signed [BITS_MAX:0] val);
        if (val > 0) begin
            if (val < VALUE_MAX)
                relu_func = val[VALUE_BITS:0];
            else
                relu_func = VALUE_MAX;
        end else begin
            relu_func = 0;
        end
    endfunction

    always_ff @(posedge i_data_clk) begin
        o_data_valid <= 1'b0;
        if (i_data_valid) begin
            for (int o = 0; o < CALC_OUTPUTS; o++) begin
                // 첫 사이클: 초기화
                if (i_cycle == 0)
                    sum[o] <= 0;
                
                // MAC 연산
                for (int i = 0; i < CALC_INPUTS; i++) begin
                    sum[o] <= sum[o] +
                        (($signed(i_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS]) *
                          weight_rom[o * (INPUTS+1) + i_cycle * CALC_INPUTS + i] +
                          (1 << (WEIGHT_BITS - OFFSET - 2)))
                         >>> (WEIGHT_BITS - OFFSET - 1));
                end

                // 마지막 사이클: bias + activation
                if (i_cycle == CALC_CYCLES_IN - 1) begin
                    act_result[o] <= relu_func(sum[o] + bias_rom[o]);
                end
            end
        end
    end

endmodule