//------------------------------------------------------------------------
// NN Layer - Fully Connected Layer (SystemVerilog)
// Converted from VHDL: nn_layer.vhd
//------------------------------------------------------------------------
`include "cnn_config_pkg.vh"

module nn_layer #(
    parameter INPUTS          = 72,
    parameter OUTPUTS         = 10,
    parameter [2:0] ACTIVATION = 3'd0,  // 0=relu
    parameter CALC_CYCLES_IN  = 72,     // 입력 시분할 (1 클럭당 1개씩 72번)
    parameter OUT_CYCLES      = 10,
    parameter OUT_DELAY       = 1,
    parameter CALC_CYCLES_OUT = 10,
    parameter OFFSET_IN       = 0,
    parameter OFFSET_OUT      = 0,
    parameter OFFSET          = 0,
    parameter VALUE_BITS      = 10,
    parameter WEIGHT_BITS     = 8,
    // Flattened 2D Weight Array [OUTPUTS][INPUTS + 1 (Bias)]
    parameter logic signed [WEIGHT_BITS-1:0] WEIGHT_ARRAY [0:OUTPUTS-1][0:INPUTS] = '{default:0}
)(
    // Input stream
    input  logic        i_data_clk,
    input  logic        i_data_valid,
    input  logic [VALUE_BITS*(INPUTS/CALC_CYCLES_IN)-1:0] i_data,
    input  logic [7:0]  i_cycle,  // 현재 입력이 몇 번째 데이터인지 알려주는 인덱스

    // Output stream
    output logic        o_data_clk,
    output logic        o_data_valid,
    output logic [VALUE_BITS*(OUTPUTS/CALC_CYCLES_OUT)-1:0] o_data,
    output logic [7:0]  o_cycle   // 출력되는 결과가 몇 번 클래스(0~9)인지 알려줌
);

    //------------------------------------------------------------------
    // Derived Constants & Types
    //------------------------------------------------------------------
    localparam CALC_OUTPUTS = OUTPUTS / OUT_CYCLES;
    localparam CALC_INPUTS  = INPUTS / CALC_CYCLES_IN;
    localparam OUT_VALUES   = OUTPUTS / CALC_CYCLES_OUT;
    localparam OFFSET_DIFF  = OFFSET_OUT - OFFSET_IN;
    
    // 누산기(Accumulator)의 오버플로우를 막기 위한 최대 비트 폭 계산
    localparam BITS_MAX     = VALUE_BITS + ((OFFSET > 0) ? OFFSET : 0) + $clog2(INPUTS + 1) + 2;
    localparam VALUE_MAX    = (1 << VALUE_BITS) - 1;

    assign o_data_clk = i_data_clk;

    //------------------------------------------------------------------
    // 1. RAM Definitions (SUM & OUT RAM)
    //------------------------------------------------------------------
    typedef logic signed [BITS_MAX:0] sum_set_t [0:CALC_OUTPUTS-1];
    
    // SUM RAM (부분합 저장)
    sum_set_t sum_ram [0:OUT_CYCLES-1];
    logic [$clog2(OUT_CYCLES > 1 ? OUT_CYCLES : 2)-1:0] sum_wr_addr, sum_rd_addr;
    sum_set_t sum_rd_data, sum_wr_data;
    logic sum_wr_ena;

    always_ff @(posedge i_data_clk) begin
        if (sum_wr_ena) sum_ram[sum_wr_addr] <= sum_wr_data;
    end
    assign sum_rd_data = sum_ram[sum_rd_addr];

    // OUT RAM (최종 활성화 함수 통과 결과 저장)
    localparam OUT_RAM_ELEMENTS = (CALC_CYCLES_OUT < OUT_CYCLES) ? CALC_CYCLES_OUT : OUT_CYCLES;
    typedef logic signed [VALUE_BITS:0] out_set_t [0:(OUTPUTS/OUT_RAM_ELEMENTS)-1];
    out_set_t out_ram [0:OUT_RAM_ELEMENTS-1];
    logic [$clog2(OUT_RAM_ELEMENTS > 1 ? OUT_RAM_ELEMENTS : 2)-1:0] out_rd_addr, out_wr_addr;
    out_set_t out_rd_data, out_wr_data;
    logic out_wr_ena;

    always_ff @(posedge i_data_clk) begin
        if (out_wr_ena) out_ram[out_wr_addr] <= out_wr_data;
    end
    assign out_rd_data = out_ram[out_rd_addr];

    //------------------------------------------------------------------
    // 2. Control State & Weight Loader Pipeline
    //------------------------------------------------------------------
    logic en = 0;
    logic [VALUE_BITS*CALC_INPUTS-1:0] idata_buf;
    logic [7:0] icycle_buf;
    logic [$clog2(OUT_CYCLES > 1 ? OUT_CYCLES : 2)-1:0] calc_cnt = 0;
    logic [$clog2(OUT_CYCLES > 1 ? OUT_CYCLES : 2)-1:0] next_calc_cnt = 0;
    logic valid_reg = 0;
    logic next_valid_reg = 0;

    always_comb begin
        next_calc_cnt = calc_cnt;
        next_valid_reg = valid_reg;

        if (i_data_valid) begin
            if (!valid_reg || calc_cnt >= OUT_CYCLES - 1) begin
                next_calc_cnt = 0;
            end else begin
                next_calc_cnt = calc_cnt + 1;
            end
            next_valid_reg = 1'b1;
        end else begin
            next_valid_reg = 1'b0;
        end
    end

    // 현재 계산 사이클에 필요한 가중치만 패키지에서 가져와 버퍼링
    logic signed [WEIGHT_BITS-1:0] weight_buf [0:CALC_OUTPUTS-1][0:CALC_INPUTS-1];

    always_ff @(posedge i_data_clk) begin
        calc_cnt  <= next_calc_cnt;
        valid_reg <= next_valid_reg;

        en <= i_data_valid;
        if (i_data_valid) begin
            idata_buf  <= i_data;
            icycle_buf <= i_cycle;
            for (int o = 0; o < CALC_OUTPUTS; o++) begin
                for (int i = 0; i < CALC_INPUTS; i++) begin
                    int out_idx = o + next_calc_cnt * CALC_OUTPUTS;
                    int in_idx  = i + i_cycle * CALC_INPUTS;
                    weight_buf[o][i] <= WEIGHT_ARRAY[out_idx][in_idx];
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 3. MAC (Multiply-Accumulate) 연산 [FC 레이어 핵심]
    //------------------------------------------------------------------
    logic last_input = 0;
    logic add_bias = 0;
    sum_set_t sum_buf;
    logic [$clog2(OUT_CYCLES > 1 ? OUT_CYCLES : 2)-1:0] calc_buf_en;
    logic [$clog2(OUT_CYCLES > 1 ? OUT_CYCLES : 2)-1:0] calc_buf2;

    always_ff @(posedge i_data_clk) begin
        sum_rd_addr <= next_calc_cnt;
        sum_wr_addr <= calc_cnt;
        calc_buf_en <= calc_cnt;

        last_input <= 1'b0;
        add_bias   <= 1'b0;
        sum_wr_ena <= 1'b0;

        if (en) begin
            sum_set_t sum_var;
            
            if (OUT_CYCLES > 1) sum_var = sum_rd_data;
            
            // 첫 번째 입력(i_cycle == 0)일 때 누산기 초기화
            if (icycle_buf == 0) begin
                for (int o = 0; o < CALC_OUTPUTS; o++) sum_var[o] = 0;
            end

            calc_buf2 <= calc_buf_en;

            // 1D 뉴런 가중치 곱셉 및 누적 로직
            for (int o = 0; o < CALC_OUTPUTS; o++) begin
                for (int i = 0; i < CALC_INPUTS; i++) begin
                    logic signed [VALUE_BITS:0] data_val;
                    data_val = {1'b0, idata_buf[VALUE_BITS*(i+1)-1 -: VALUE_BITS]};
                    
                    logic signed [VALUE_BITS+WEIGHT_BITS:0] prod;
                    prod = data_val * weight_buf[o][i];
                    
                    // 반올림 상수(Bias)를 더한 후 시프트하여 스케일링
                    logic signed [VALUE_BITS+WEIGHT_BITS:0] prod_shifted;
                    prod_shifted = (prod + (1 << (WEIGHT_BITS - OFFSET - 2))) >>> (WEIGHT_BITS - OFFSET - 1);
                    
                    sum_var[o] = sum_var[o] + prod_shifted;
                end
            end

            // 72개의 입력(Flatten Feature)이 모두 들어왔을 때
            if (icycle_buf == CALC_CYCLES_IN - 1) begin
                if (calc_buf_en == OUT_CYCLES - 1) begin
                    last_input <= 1'b1;
                end
                sum_buf  <= sum_var;
                add_bias <= 1'b1;
            end

            if (OUT_CYCLES > 1) begin
                sum_wr_data <= sum_var;
                sum_wr_ena  <= 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    // 4. Bias 추가, 활성화 함수(ReLU) 및 OUT_RAM 저장
    //------------------------------------------------------------------
    localparam ACT_SUM_BUF_CYCLES = (OUT_CYCLES / OUT_RAM_ELEMENTS > 0) ? (OUT_CYCLES / OUT_RAM_ELEMENTS) : 1;
    typedef logic signed [VALUE_BITS:0] act_sum_t [0:CALC_OUTPUTS-1];
    act_sum_t act_sum_buf [0:ACT_SUM_BUF_CYCLES-1];

    always_ff @(posedge i_data_clk) begin
        out_wr_ena <= 1'b0;
        if (add_bias) begin
            act_sum_t act_sum;
            
            for (int o = 0; o < CALC_OUTPUTS; o++) begin
                logic signed [BITS_MAX+1:0] sum_biased;
                int out_idx = o + calc_buf2 * CALC_OUTPUTS;
                
                // 가중치 배열의 마지막 열(INPUTS 인덱스)에 있는 Bias 값 추출
                logic signed [WEIGHT_BITS-1:0] bias_val = WEIGHT_ARRAY[out_idx][INPUTS]; 

                if (OFFSET >= 0) begin
                    sum_biased = sum_buf[o] + (bias_val <<< OFFSET);
                end else begin
                    sum_biased = sum_buf[o] + (bias_val >>> -OFFSET);
                end
                
                if (OFFSET_DIFF > 0) begin
                    sum_biased = sum_biased >>> OFFSET_DIFF;
                end else if (OFFSET_DIFF < 0) begin
                    sum_biased = sum_biased <<< -OFFSET_DIFF;
                end

                // ReLU 연산
                if (sum_biased > 0) begin
                    act_sum[o] = (sum_biased < VALUE_MAX) ? sum_biased[VALUE_BITS:0] : VALUE_MAX;
                end else begin
                    act_sum[o] = 0;
                end
            end

            if (OUT_CYCLES == OUT_RAM_ELEMENTS) begin
                out_wr_addr <= calc_buf2;
                for (int i = 0; i < CALC_OUTPUTS; i++) out_wr_data[i] <= act_sum[i];
                out_wr_ena <= 1'b1;
            end else begin
                int act_sum_buf_cnt = calc_buf2 % ACT_SUM_BUF_CYCLES;
                act_sum_buf[act_sum_buf_cnt] <= act_sum;
                
                if (act_sum_buf_cnt == ACT_SUM_BUF_CYCLES - 1) begin
                    out_wr_addr <= calc_buf2 / ACT_SUM_BUF_CYCLES;
                    for (int i = 0; i < ACT_SUM_BUF_CYCLES; i++) begin
                        for (int j = 0; j < CALC_OUTPUTS; j++) begin
                            out_wr_data[CALC_OUTPUTS * i + j] <= (i == act_sum_buf_cnt) ? act_sum[j] : act_sum_buf[i][j];
                        end
                    end
                    out_wr_ena <= 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 5. Output Stage (시분할 결과 출력)
    //------------------------------------------------------------------
    logic [$clog2(CALC_CYCLES_OUT > 1 ? CALC_CYCLES_OUT : 2)-1:0] ocycle_cnt = CALC_CYCLES_OUT > 0 ? CALC_CYCLES_OUT - 1 : 0;
    logic [$clog2(OUT_DELAY > 1 ? OUT_DELAY : 2)-1:0]  delay_cycle = OUT_DELAY > 0 ? OUT_DELAY - 1 : 0;
    logic valid_reg_o = 0;

    always_ff @(posedge i_data_clk) begin
        logic [$clog2(CALC_CYCLES_OUT > 1 ? CALC_CYCLES_OUT : 2)-1:0] ocycle_cnt_var;
        ocycle_cnt_var = ocycle_cnt;

        if (last_input) begin
            ocycle_cnt_var = 0;
            delay_cycle <= 0;
            valid_reg_o <= 1'b1;
        end else if (OUT_DELAY > 1 && delay_cycle < OUT_DELAY - 1) begin
            delay_cycle <= delay_cycle + 1;
            valid_reg_o <= 1'b0;
        end else if (ocycle_cnt < CALC_CYCLES_OUT - 1) begin
            delay_cycle <= 0;
            ocycle_cnt_var = ocycle_cnt + 1;
            valid_reg_o <= 1'b1;
        end else begin
            valid_reg_o <= 1'b0;
        end

        ocycle_cnt <= ocycle_cnt_var;
        out_rd_addr <= ocycle_cnt_var / (CALC_CYCLES_OUT / OUT_RAM_ELEMENTS);

        if (valid_reg_o) begin
            for (int i = 0; i < OUT_VALUES; i++) begin
                if (CALC_CYCLES_OUT == OUT_RAM_ELEMENTS) begin
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[i];
                end else begin
                    int idx = i + (ocycle_cnt % (CALC_CYCLES_OUT / OUT_RAM_ELEMENTS)) * OUT_VALUES;
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[idx];
                end
            end
            
            // 결과 번호표(0번~9번)를 달아서 출력. Argmax 로직에서 이 번호를 보고 최종 판별합니다.
            o_cycle      <= ocycle_cnt * OUT_VALUES; 
            o_data_valid <= 1'b1;
        end else begin
            o_data_valid <= 1'b0;
        end
    end

endmodule
