//------------------------------------------------------------------------
// CNN Convolution Layer (SystemVerilog)
// Converted from VHDL: cnn_convolution.vhd
//------------------------------------------------------------------------
`include "cnn_config_pkg.vh"

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
    parameter WEIGHT_BITS    = 8,
    // Flattened 2D Weight Array [FILTERS][INPUT_VALUES*FILTER_COLUMNS*FILTER_ROWS + 1]
    parameter logic signed [WEIGHT_BITS-1:0] WEIGHT_ARRAY [0:FILTERS-1][0:(INPUT_VALUES*FILTER_COLUMNS*FILTER_ROWS)] = '{default:0}
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

    //------------------------------------------------------------------
    // Derived Constants & Types
    //------------------------------------------------------------------
    localparam MATRIX_VALUES       = FILTER_COLUMNS * FILTER_ROWS;
    localparam MATRIX_VALUE_CYCLES = MATRIX_VALUES * VALUE_CYCLES;
    localparam CALC_FILTERS        = FILTERS / CALC_CYCLES;
    localparam OUT_FILTERS         = FILTERS / FILTER_CYCLES;
    localparam CALC_STEPS          = (INPUT_VALUES * MATRIX_VALUES) / MATRIX_VALUE_CYCLES;
    localparam OFFSET_DIFF         = OFFSET_OUT - OFFSET_IN;
    localparam BITS_MAX            = VALUE_BITS + ((OFFSET > 0) ? OFFSET : 0) + $clog2(MATRIX_VALUES * INPUT_VALUES + 1) + 2;
    localparam VALUE_MAX           = (1 << VALUE_BITS) - 1;

    assign o_data_clk = i_data_clk;

    //------------------------------------------------------------------
    // 1. Expand Logic
    //------------------------------------------------------------------
    logic        exp_data_clk;
    logic [9:0]  exp_column;
    logic [8:0]  exp_row;
    logic [3:0]  exp_filter;
    logic        exp_data_valid;
    logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] exp_data;

    generate
        if (EXPAND) begin : gen_expand
            localparam MAX_EXPAND = (MATRIX_VALUE_CYCLES * CALC_CYCLES + 1 > EXPAND_CYCLES) ? 
                                    (MATRIX_VALUE_CYCLES * CALC_CYCLES + 1) : EXPAND_CYCLES;
            cnn_row_expander #(
                .INPUT_COLUMNS (INPUT_COLUMNS),
                .INPUT_ROWS    (INPUT_ROWS),
                .INPUT_VALUES  (INPUT_VALUES),
                .INPUT_CYCLES  (INPUT_CYCLES),
                .OUTPUT_CYCLES (MAX_EXPAND),
                .VALUE_BITS    (VALUE_BITS)
            ) u_expander (
                .i_data_clk  (i_data_clk),
                .i_column    (i_column),
                .i_row       (i_row),
                .i_filter    (i_filter),
                .i_data_valid(i_data_valid),
                .i_data      (i_data),
                .o_data_clk  (exp_data_clk),
                .o_column    (exp_column),
                .o_row       (exp_row),
                .o_filter    (exp_filter),
                .o_data_valid(exp_data_valid),
                .o_data      (exp_data)
            );
        end else begin : gen_no_expand
            assign exp_data_clk   = i_data_clk;
            assign exp_column     = i_column;
            assign exp_row        = i_row;
            assign exp_filter     = i_filter;
            assign exp_data_valid = i_data_valid;
            assign exp_data       = i_data;
        end
    endgenerate

    //------------------------------------------------------------------
    // 2. Row Buffer
    //------------------------------------------------------------------
    logic        mat_data_clk;
    logic [9:0]  mat_column;
    logic [8:0]  mat_row;
    logic [3:0]  mat_filter;
    logic        mat_data_valid;
    logic [VALUE_BITS*CALC_STEPS-1:0] mat_data;

    cnn_row_buffer #(
        .INPUT_COLUMNS  (INPUT_COLUMNS),
        .INPUT_ROWS     (INPUT_ROWS),
        .INPUT_VALUES   (INPUT_VALUES),
        .FILTER_COLUMNS (FILTER_COLUMNS),
        .FILTER_ROWS    (FILTER_ROWS),
        .INPUT_CYCLES   (INPUT_CYCLES),
        .VALUE_CYCLES   (VALUE_CYCLES),
        .CALC_CYCLES    (CALC_CYCLES),
        .STRIDES        (STRIDES),
        .PADDING        (PADDING),
        .VALUE_BITS     (VALUE_BITS)
    ) u_row_buffer (
        .i_data_clk  (exp_data_clk),
        .i_column    (exp_column),
        .i_row       (exp_row),
        .i_filter    (exp_filter),
        .i_data_valid(exp_data_valid),
        .i_data      (exp_data),
        .o_data_clk  (mat_data_clk),
        .o_column    (mat_column),
        .o_row       (mat_row),
        .o_filter    (mat_filter),
        .o_data_valid(mat_data_valid),
        .o_data      (mat_data),
        .o_mat_row   (),
        .o_mat_column(),
        .o_mat_input ()
    );

    //------------------------------------------------------------------
    // 3. RAM Definitions (SUM & OUT RAM)
    //------------------------------------------------------------------
    typedef logic signed [BITS_MAX:0] sum_set_t [0:CALC_FILTERS-1];
    sum_set_t sum_ram [0:CALC_CYCLES-1];
    logic [$clog2(CALC_CYCLES):0] sum_rd_addr, sum_wr_addr;
    sum_set_t sum_rd_data, sum_wr_data;
    logic sum_wr_ena;

    // 분산 RAM 추론을 위해 읽기는 Asynchronous하게 구성
    always_ff @(posedge mat_data_clk) begin
        if (sum_wr_ena) sum_ram[sum_wr_addr] <= sum_wr_data;
    end
    assign sum_rd_data = sum_ram[sum_rd_addr];

    localparam OUT_RAM_ELEMENTS = (CALC_CYCLES < FILTER_CYCLES) ? CALC_CYCLES : FILTER_CYCLES;
    typedef logic signed [VALUE_BITS:0] out_set_t [0:(FILTERS/OUT_RAM_ELEMENTS)-1];
    out_set_t out_ram [0:OUT_RAM_ELEMENTS-1];
    logic [$clog2(OUT_RAM_ELEMENTS):0] out_rd_addr, out_wr_addr;
    out_set_t out_rd_data, out_wr_data;
    logic out_wr_ena;

    always_ff @(posedge mat_data_clk) begin
        if (out_wr_ena) out_ram[out_wr_addr] <= out_wr_data;
    end
    assign out_rd_data = out_ram[out_rd_addr];

    //------------------------------------------------------------------
    // 4. Control State & Weight Loader Pipeline
    //------------------------------------------------------------------
    logic [$clog2(MATRIX_VALUE_CYCLES):0] cycle_cnt = 0;
    logic [$clog2(CALC_CYCLES):0]         calc_cnt = CALC_CYCLES > 0 ? CALC_CYCLES - 1 : 0;
    logic valid_reg = 0;

    logic en = 0;
    logic [VALUE_BITS*CALC_STEPS-1:0] idata_buf;
    logic [$clog2(MATRIX_VALUE_CYCLES):0] cycle_buf;
    logic [$clog2(CALC_CYCLES):0]         calc_buf;
    logic signed [WEIGHT_BITS-1:0] weight_buf [0:CALC_FILTERS-1][0:CALC_STEPS-1];

    logic [$clog2(MATRIX_VALUE_CYCLES):0] next_cycle_cnt;
    logic [$clog2(CALC_CYCLES):0]         next_calc_cnt;
    logic next_valid_reg;

    always_comb begin
        next_calc_cnt = calc_cnt;
        next_cycle_cnt = cycle_cnt;
        next_valid_reg = valid_reg;

        if (mat_data_valid) begin
            if (!valid_reg) begin
                next_calc_cnt = 0;
                next_cycle_cnt = 0;
            end else if (calc_cnt < CALC_CYCLES - 1) begin
                next_calc_cnt = calc_cnt + 1;
            end else if (cycle_cnt < MATRIX_VALUE_CYCLES - 1) begin
                next_calc_cnt = 0;
                next_cycle_cnt = cycle_cnt + 1;
            end
            next_valid_reg = 1'b1;
        end else begin
            next_valid_reg = 1'b0;
        end
    end

    always_ff @(posedge mat_data_clk) begin
        calc_cnt  <= next_calc_cnt;
        cycle_cnt <= next_cycle_cnt;
        valid_reg <= next_valid_reg;

        en <= mat_data_valid;
        if (mat_data_valid) begin
            idata_buf <= mat_data;
            cycle_buf <= next_cycle_cnt;
            calc_buf  <= next_calc_cnt;
            
            // 패키지 헤더(cnn_data_pkg)에 있는 파라미터에서 현재 연산에 필요한 가중치만 버퍼링
            for (int f = 0; f < CALC_FILTERS; f++) begin
                for (int s = 0; s < CALC_STEPS; s++) begin
                    int filter_idx = f + next_calc_cnt * CALC_FILTERS;
                    int input_idx  = s + next_cycle_cnt * CALC_STEPS;
                    weight_buf[f][s] <= WEIGHT_ARRAY[filter_idx][input_idx];
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 5. MAC (Multiply-Accumulate) 연산
    //------------------------------------------------------------------
    logic last_input = 0;
    logic add_bias = 0;
    sum_set_t sum_buf;
    logic [$clog2(CALC_CYCLES):0] calc_buf2;

    always_ff @(posedge mat_data_clk) begin
        sum_rd_addr <= next_calc_cnt;
        sum_wr_addr <= calc_buf;

        last_input <= 1'b0;
        add_bias   <= 1'b0;
        sum_wr_ena <= 1'b0;

        if (en) begin
            sum_set_t sum_var;
            
            // 기존 누적값(Partial Sum) 로드
            if (CALC_CYCLES > 1) sum_var = sum_rd_data;
            if (cycle_buf == 0) begin
                for (int o = 0; o < CALC_FILTERS; o++) sum_var[o] = 0;
            end

            calc_buf2 <= calc_buf;

            // 핵심 MAC 루프: 곱셈, 반올림, 스케일링 [cite: 593-594]
            for (int o = 0; o < CALC_FILTERS; o++) begin
                for (int i = 0; i < CALC_STEPS; i++) begin
                    logic signed [VALUE_BITS:0] data_val;
                    data_val = {1'b0, idata_buf[VALUE_BITS*(i+1)-1 -: VALUE_BITS]}; // Unsigned to Signed
                    
                    logic signed [VALUE_BITS+WEIGHT_BITS:0] prod;
                    prod = data_val * weight_buf[o][i];
                    
                    logic signed [VALUE_BITS+WEIGHT_BITS:0] prod_shifted;
                    prod_shifted = (prod + (1 << (WEIGHT_BITS - OFFSET - 2))) >>> (WEIGHT_BITS - OFFSET - 1);
                    
                    sum_var[o] = sum_var[o] + prod_shifted;
                end
            end

            // 모든 픽셀 누적이 완료되었는지 체크
            if (cycle_buf == MATRIX_VALUE_CYCLES - 1) begin
                if (calc_buf == CALC_CYCLES - 1) begin
                    last_input <= 1'b1;
                end
                sum_buf  <= sum_var;
                add_bias <= 1'b1;
            end

            if (CALC_CYCLES > 1) begin
                sum_wr_data <= sum_var;
                sum_wr_ena  <= 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    // 6. Bias 추가, 활성화 함수(ReLU) 및 OUT_RAM 저장
    //------------------------------------------------------------------
    localparam ACT_SUM_BUF_CYCLES = (CALC_CYCLES / OUT_RAM_ELEMENTS > 0) ? (CALC_CYCLES / OUT_RAM_ELEMENTS) : 1;
    typedef logic signed [VALUE_BITS:0] act_sum_t [0:CALC_FILTERS-1];
    act_sum_t act_sum_buf [0:ACT_SUM_BUF_CYCLES-1];

    always_ff @(posedge mat_data_clk) begin
        out_wr_ena <= 1'b0;
        if (add_bias) begin
            act_sum_t act_sum;
            
            for (int o = 0; o < CALC_FILTERS; o++) begin
                logic signed [BITS_MAX+1:0] sum_biased;
                int filter_idx = o + calc_buf2 * CALC_FILTERS;
                logic signed [WEIGHT_BITS-1:0] bias_val = WEIGHT_ARRAY[filter_idx][MATRIX_VALUES*INPUT_VALUES]; // 배열 마지막은 항상 Bias

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

                // ReLU 적용 [cite: 580]
                if (sum_biased > 0) begin
                    act_sum[o] = (sum_biased < VALUE_MAX) ? sum_biased[VALUE_BITS:0] : VALUE_MAX;
                end else begin
                    act_sum[o] = 0;
                end
            end

            if (CALC_CYCLES == OUT_RAM_ELEMENTS) begin
                out_wr_addr <= calc_buf2;
                for (int i = 0; i < CALC_FILTERS; i++) out_wr_data[i] <= act_sum[i];
                out_wr_ena <= 1'b1;
            end else begin
                int act_sum_buf_cnt = calc_buf2 % ACT_SUM_BUF_CYCLES;
                act_sum_buf[act_sum_buf_cnt] <= act_sum;
                
                if (act_sum_buf_cnt == ACT_SUM_BUF_CYCLES - 1) begin
                    out_wr_addr <= calc_buf2 / ACT_SUM_BUF_CYCLES;
                    for (int i = 0; i < ACT_SUM_BUF_CYCLES; i++) begin
                        for (int j = 0; j < CALC_FILTERS; j++) begin
                            out_wr_data[CALC_FILTERS * i + j] <= (i == act_sum_buf_cnt) ? act_sum[j] : act_sum_buf[i][j];
                        end
                    end
                    out_wr_ena <= 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 7. Output Stage (결과 출력)
    //------------------------------------------------------------------
    logic [$clog2(FILTER_CYCLES):0] ocycle_cnt = FILTER_CYCLES > 0 ? FILTER_CYCLES - 1 : 0;
    logic [$clog2(FILTER_DELAY):0]  delay_cycle = FILTER_DELAY > 0 ? FILTER_DELAY - 1 : 0;
    logic valid_reg_o = 0;
    logic [9:0] ocolumn_buf;
    logic [8:0] orow_buf;

    always_ff @(posedge mat_data_clk) begin
        logic [$clog2(FILTER_CYCLES):0] ocycle_cnt_var;
        ocycle_cnt_var = ocycle_cnt;

        if (last_input) begin
            ocolumn_buf <= mat_column;
            orow_buf    <= mat_row;
            ocycle_cnt_var = 0;
            delay_cycle <= 0;
            valid_reg_o <= 1'b1;
        end else if (FILTER_DELAY > 1 && delay_cycle < FILTER_DELAY - 1) begin
            delay_cycle <= delay_cycle + 1;
            valid_reg_o <= 1'b0;
        end else if (ocycle_cnt < FILTER_CYCLES - 1) begin
            delay_cycle <= 0;
            ocycle_cnt_var = ocycle_cnt + 1;
            valid_reg_o <= 1'b1;
        end else begin
            valid_reg_o <= 1'b0;
        end

        ocycle_cnt <= ocycle_cnt_var;
        out_rd_addr <= ocycle_cnt_var / (FILTER_CYCLES / OUT_RAM_ELEMENTS);

        // VHDL의 Signal 타이밍을 정확히 복제하기 위해 레지스터된 Valid 플래그 사용
        if (valid_reg_o) begin
            for (int i = 0; i < OUT_FILTERS; i++) begin
                if (FILTER_CYCLES == OUT_RAM_ELEMENTS) begin
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[i];
                end else begin
                    int idx = i + (ocycle_cnt % (FILTER_CYCLES / OUT_RAM_ELEMENTS)) * OUT_FILTERS;
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[idx];
                end
            end
            o_filter     <= ocycle_cnt * OUT_FILTERS;
            o_data_valid <= 1'b1;
            o_row        <= orow_buf;
            o_column     <= ocolumn_buf;
        end else begin
            o_data_valid <= 1'b0;
        end
    end

endmodule
