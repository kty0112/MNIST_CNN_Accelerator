//------------------------------------------------------------------------
// CNN Row Expander (SystemVerilog)
// Converted from VHDL: cnn_row_expander.vhd
//------------------------------------------------------------------------
`include "cnn_config_pkg.vh"

module cnn_row_expander #(
    parameter INPUT_COLUMNS = 28,
    parameter INPUT_ROWS    = 28,
    parameter INPUT_VALUES  = 1,
    parameter INPUT_CYCLES  = 1,
    parameter OUTPUT_CYCLES = 2, // 2클럭 간격을 두어 츌력
    parameter VALUE_BITS    = 10    // CNN_VALUE_RESOLUTION
)(
    // Input stream (Flattened CNN_Stream_T)
    input  logic        i_data_clk,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic [3:0]  i_filter,
    input  logic        i_data_valid,
    // Input data (Flattened CNN_Values_T)
    input  logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] i_data,

    // Output stream
    output logic        o_data_clk,
    output logic [9:0]  o_column,
    output logic [8:0]  o_row,
    output logic [3:0]  o_filter,
    output logic        o_data_valid,
    // Output data
    output logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] o_data
);

    //------------------------------------------------------------------
    // Constants & RAM Configuration
    //------------------------------------------------------------------
    localparam DATA_WIDTH = (VALUE_BITS + CNN_VALUE_NEGATIVE) * (INPUT_VALUES / INPUT_CYCLES);// [cite: 581]
    localparam RAM_DEPTH  = INPUT_COLUMNS * INPUT_CYCLES;// [cite: 582]

    assign o_data_clk = i_data_clk;// [cite: 588]

    // RAM 정의 [cite: 582-583]
    logic [DATA_WIDTH-1:0] buffer_ram [0:RAM_DEPTH-1];
    logic [$clog2(RAM_DEPTH)-1:0] ram_addr_in, ram_addr_out;
    logic [DATA_WIDTH-1:0] ram_data_in, ram_data_out;

    // RAM Write & Read (Falling Edge) 
    // VHDL의 falling_edge 로직을 그대로 반영하여 타이밍 충돌 방지
    always_ff @(negedge i_data_clk) begin
        buffer_ram[ram_addr_in] <= ram_data_in;
        ram_data_out            <= buffer_ram[ram_addr_out];
    end

    //------------------------------------------------------------------
    // Internal Registers (VHDL variables mapping)
    //------------------------------------------------------------------
    logic [VALUE_BITS*(INPUT_VALUES/INPUT_CYCLES)-1:0] i_data_buf;
    logic        valid_reg = 1'b0;
    logic [9:0]  column_buf;// [cite: 590]
    logic [3:0]  filter_cnt;// [cite: 591]
    logic [$clog2(OUTPUT_CYCLES)-1:0] delay_cnt = 0; // [cite: 586]
    logic        reset_col = 1'b0; //[cite: 587]

    struct {
        logic [9:0] column;
        logic [8:0] row;
        logic [3:0] filter;
        logic       data_valid;
    } o_stream_reg; //[cite: 587]

    //------------------------------------------------------------------
    // Main Logic (Rising Edge) [cite: 592-608]
    //------------------------------------------------------------------
    always_ff @(posedge i_data_clk) begin
        // 1. 입력 데이터 버퍼링 [cite: 592-595]
        if (i_data_valid) begin
            i_data_buf <= i_data;
        end
        
        // RAM에 입력할 데이터 포맷팅 (정수형 변환 로직 포함)
        ram_data_in <= i_data_buf; 
        ram_addr_in <= i_column * INPUT_CYCLES + i_filter; //[cite: 595]

        // 2. 출력 지연 카운터 제어 [cite: 596-599]
        if (i_data_valid && !valid_reg && i_column == 0) begin
            delay_cnt <= 0;
            reset_col <= 1'b1;
        end else if (delay_cnt < OUTPUT_CYCLES - 1) begin
            delay_cnt <= delay_cnt + 1;
        end else if (i_column > column_buf) begin
            delay_cnt <= 0;
        end
        valid_reg <= i_data_valid;

        // 3. 출력 데이터 생성 로직 [cite: 600-603]
        if (reset_col) begin
            reset_col <= 1'b0;
            column_buf <= 0;
            filter_cnt <= 0;
            o_stream_reg.data_valid <= 1'b1;
        end else if (delay_cnt == 0 && column_buf < INPUT_COLUMNS - 1) begin
            column_buf <= column_buf + 1;
            filter_cnt <= 0;
            o_stream_reg.data_valid <= 1'b1;
        end else if (filter_cnt < (INPUT_CYCLES - 1) * (INPUT_VALUES / INPUT_CYCLES)) begin
            filter_cnt <= filter_cnt + (INPUT_VALUES / INPUT_CYCLES);
            o_stream_reg.data_valid <= 1'b1;
        end else begin
            o_stream_reg.data_valid <= 1'b0;
        end

        // 좌표 및 필터 번호 업데이트
        o_stream_reg.column <= column_buf;
        o_stream_reg.row    <= i_row;
        o_stream_reg.filter <= filter_cnt;
        ram_addr_out        <= column_buf * INPUT_CYCLES + filter_cnt; //[cite: 604]

        // 4. 최종 출력 스트림 할당 [cite: 605-608]
        o_column     <= o_stream_reg.column;
        o_row        <= o_stream_reg.row;
        o_filter     <= o_stream_reg.filter;
        o_data_valid <= o_stream_reg.data_valid;
        o_data       <= ram_data_out;
    end

endmodule
