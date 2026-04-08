//------------------------------------------------------------------------
// CNN Pooling (Max Pooling) Layer (SystemVerilog)
// Converted from VHDL: cnn_pooling.vhd
//------------------------------------------------------------------------
`include "cnn_config_pkg.vh"

module cnn_pooling #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 4,
    parameter FILTER_COLUMNS = 2,
    parameter FILTER_ROWS    = 2,
    parameter STRIDES        = 1,
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

    //------------------------------------------------------------------
    // Derived Constants & Types
    //------------------------------------------------------------------
    localparam CALC_CYCLES  = FILTER_COLUMNS * FILTER_ROWS * VALUE_CYCLES;
    localparam CALC_OUTPUTS = INPUT_VALUES / VALUE_CYCLES;
    localparam OUT_VALUES   = INPUT_VALUES / FILTER_CYCLES;
    localparam OUT_RAM_ELEMENTS = (CALC_CYCLES < FILTER_CYCLES) ? CALC_CYCLES : FILTER_CYCLES;

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
            localparam MAX_EXPAND = (VALUE_CYCLES * CALC_CYCLES + 1 > EXPAND_CYCLES) ? 
                                    (VALUE_CYCLES * CALC_CYCLES + 1) : EXPAND_CYCLES;
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
    logic [VALUE_BITS*CALC_OUTPUTS-1:0] mat_data;

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
    // 3. RAM Definitions (MAX & OUT RAM)
    //------------------------------------------------------------------
    typedef logic [VALUE_BITS-1:0] max_set_t [0:CALC_OUTPUTS-1];
    
    // MAX RAM (중간 최대값 저장)
    max_set_t max_ram [0:CALC_CYCLES-1];
    logic [$clog2(CALC_CYCLES):0] max_rd_addr, max_wr_addr;
    max_set_t max_rd_data, max_wr_data;
    logic max_wr_ena;

    always_ff @(posedge mat_data_clk) begin
        if (max_wr_ena) max_ram[max_wr_addr] <= max_wr_data;
    end
    assign max_rd_data = max_ram[max_rd_addr];

    // OUT RAM (최종 최대값 저장)
    typedef logic [VALUE_BITS-1:0] out_set_t [0:(INPUT_VALUES/OUT_RAM_ELEMENTS)-1];
    out_set_t out_ram [0:OUT_RAM_ELEMENTS-1];
    logic [$clog2(OUT_RAM_ELEMENTS):0] out_rd_addr, out_wr_addr;
    out_set_t out_rd_data, out_wr_data;
    logic out_wr_ena;

    always_ff @(posedge mat_data_clk) begin
        if (out_wr_ena) out_ram[out_wr_addr] <= out_wr_data;
    end
    assign out_rd_data = out_ram[out_rd_addr];

    //------------------------------------------------------------------
    // 4. Control State & Max Extraction Logic
    //------------------------------------------------------------------
    logic [$clog2(CALC_CYCLES):0] calc_cnt = CALC_CYCLES > 0 ? CALC_CYCLES - 1 : 0;
    logic valid_reg = 0;
    
    logic en = 0;
    logic [VALUE_BITS*CALC_OUTPUTS-1:0] idata_buf;
    logic [$clog2(CALC_CYCLES):0]       calc_buf;
    logic [$clog2(CALC_CYCLES):0]       next_calc_cnt;
    logic next_valid_reg;

    always_comb begin
        next_calc_cnt = calc_cnt;
        next_valid_reg = valid_reg;

        if (mat_data_valid) begin
            if (!valid_reg || calc_cnt >= CALC_CYCLES - 1) begin
                next_calc_cnt = 0;
            end else begin
                next_calc_cnt = calc_cnt + 1;
            end
            next_valid_reg = 1'b1;
        end else begin
            next_valid_reg = 1'b0;
        end
    end

    always_ff @(posedge mat_data_clk) begin
        calc_cnt  <= next_calc_cnt;
        valid_reg <= next_valid_reg;

        en <= mat_data_valid;
        if (mat_data_valid) begin
            idata_buf <= mat_data;
            calc_buf  <= next_calc_cnt;
        end
    end

    //------------------------------------------------------------------
    // 5. Max Pooling 연산
    //------------------------------------------------------------------
    logic last_input = 0;
    
    always_ff @(posedge mat_data_clk) begin
        max_rd_addr <= next_calc_cnt;
        max_wr_addr <= calc_buf;

        last_input <= 1'b0;
        max_wr_ena <= 1'b0;
        out_wr_ena <= 1'b0;

        if (en) begin
            max_set_t max_var;
            
            // 첫 사이클이면 0으로 초기화, 아니면 이전 최대값 불러오기
            if (calc_buf == 0) begin
                for (int o = 0; o < CALC_OUTPUTS; o++) max_var[o] = 0;
            end else if (CALC_CYCLES > 1) begin
                max_var = max_rd_data;
            end

            // 윈도우 내 픽셀 값 비교 (Max)
            for (int o = 0; o < CALC_OUTPUTS; o++) begin
                logic [VALUE_BITS-1:0] data_val = idata_buf[VALUE_BITS*(o+1)-1 -: VALUE_BITS];
                if (data_val > max_var[o]) begin
                    max_var[o] = data_val;
                end
            end

            // 윈도우 계산이 끝나면 OUT_RAM에 최종 결과 저장
            if (calc_buf == CALC_CYCLES - 1) begin
                last_input <= 1'b1;
                out_wr_addr <= 0; // Pooling의 경우 단순화
                
                for (int i = 0; i < CALC_OUTPUTS; i++) begin
                    out_wr_data[i] <= max_var[i];
                end
                out_wr_ena <= 1'b1;
            end

            if (CALC_CYCLES > 1) begin
                max_wr_data <= max_var;
                max_wr_ena  <= 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    // 6. Output Stage (결과 출력)
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

        if (valid_reg_o) begin
            for (int i = 0; i < OUT_VALUES; i++) begin
                if (FILTER_CYCLES == OUT_RAM_ELEMENTS) begin
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[i];
                end else begin
                    int idx = i + (ocycle_cnt % (FILTER_CYCLES / OUT_RAM_ELEMENTS)) * OUT_VALUES;
                    o_data[VALUE_BITS*(i+1)-1 -: VALUE_BITS] <= out_rd_data[idx];
                end
            end
            o_filter     <= ocycle_cnt * (INPUT_VALUES / FILTER_CYCLES);
            o_data_valid <= 1'b1;
            o_row        <= orow_buf;
            o_column     <= ocolumn_buf;
        end else begin
            o_data_valid <= 1'b0;
        end
    end

endmodule
