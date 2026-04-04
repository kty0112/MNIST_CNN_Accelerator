//------------------------------------------------------------------------
// CNN Row Expander (Verilog)
// Converted from VHDL: cnn_row_expander.vhd
//
// [기능]
//   한 행의 데이터를 버퍼링하고, 출력 시 데이터 간 시간 간격을 늘려줌
//   후단의 Convolution/Pooling이 여러 사이클을 필요로 하기 때문에
//   데이터 사이에 "여유 공간"을 삽입
//
//   입력: -_-_-_-_________  (데이터가 연속으로 밀집)
//   출력: -___-___-___-___  (데이터 사이에 빈 사이클 삽입)
//
// [핵심 개념]
//   - RAM에 한 행 데이터를 저장
//   - Output_Cycles 파라미터로 간격 조절
//   - Falling edge에서 RAM 읽기/쓰기 (Data_CLK의 양 에지 활용)
//
// [VHDL과의 차이]
//   CNN_Stream_T record → 개별 포트
//   CNN_Values_T array  → packed 비트 벡터
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// CNN Row Expander (SystemVerilog)
//------------------------------------------------------------------------
module cnn_row_expander #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 1,
    parameter INPUT_CYCLES   = 1,
    parameter OUTPUT_CYCLES  = 2,
    parameter VALUE_BITS     = 10   // CNN_VALUE_RESOLUTION
)(
    // Input stream
    input  logic        i_data_clk,
    input  logic [9:0]  i_column,
    input  logic [8:0]  i_row,
    input  logic [3:0]  i_filter,
    input  logic        i_data_valid,

    // Input data
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

    localparam VALUES_PER_CYCLE = INPUT_VALUES / INPUT_CYCLES;
    localparam DATA_WIDTH = VALUE_BITS * VALUES_PER_CYCLE;
    localparam RAM_DEPTH  = INPUT_COLUMNS * INPUT_CYCLES;

    assign o_data_clk = i_data_clk;

    // RAM
    logic [DATA_WIDTH-1:0] buffer_ram [0:RAM_DEPTH-1];
    logic [$clog2(RAM_DEPTH)-1:0] ram_addr_in, ram_addr_out;
    logic [DATA_WIDTH-1:0] ram_data_in;
    logic [DATA_WIDTH-1:0] ram_data_out;

    // RAM write on falling edge
    always_ff @(negedge i_data_clk) begin
        buffer_ram[ram_addr_in] <= ram_data_in;
        ram_data_out <= buffer_ram[ram_addr_out];
    end

    // Control registers
    logic [$clog2(OUTPUT_CYCLES)-1:0] delay_cnt;
    logic reset_col;
    logic [9:0]  column_buf;
    logic [3:0]  filter_cnt;
    logic        valid_reg;

    // Output pipeline registers
    logic [9:0]  o_column_reg;
    logic [8:0]  o_row_reg;
    logic [3:0]  o_filter_reg;
    logic        o_valid_reg;

    // Main logic on rising edge
    always_ff @(posedge i_data_clk) begin
        // Input data를 RAM에 저장
        ram_data_in  <= i_data;
        ram_addr_in  <= i_column * INPUT_CYCLES + i_filter;

        // 출력 지연 카운터
        if (i_data_valid && !valid_reg && i_column == 0) begin
            delay_cnt <= 0;
            reset_col <= 1'b1;
        end else if (delay_cnt < OUTPUT_CYCLES - 1) begin
            delay_cnt <= delay_cnt + 1;
        end else if (i_column > column_buf) begin
            delay_cnt <= 0;
        end

        valid_reg <= i_data_valid;

        // 출력 데이터 제어
        if (reset_col) begin
            reset_col   <= 1'b0;
            column_buf  <= 0;
            filter_cnt  <= 0;
            o_valid_reg <= 1'b1;
        end else if (delay_cnt == 0 && column_buf < INPUT_COLUMNS - 1) begin
            column_buf  <= column_buf + 1;
            filter_cnt  <= 0;
            o_valid_reg <= 1'b1;
        end else if (filter_cnt < (INPUT_CYCLES - 1) * VALUES_PER_CYCLE) begin
            filter_cnt <= filter_cnt + VALUES_PER_CYCLE;
        end else begin
            o_valid_reg <= 1'b0;
        end

        // RAM 읽기 주소
        ram_addr_out <= column_buf * INPUT_CYCLES + filter_cnt;

        // Output pipeline
        o_column_reg <= column_buf;
        o_row_reg    <= i_row;
        o_filter_reg <= filter_cnt;

        o_column     <= o_column_reg;
        o_row        <= o_row_reg;
        o_filter     <= o_filter_reg;
        o_data_valid <= o_valid_reg;
        o_data       <= ram_data_out;
    end

endmodule