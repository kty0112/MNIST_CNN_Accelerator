//------------------------------------------------------------------------
// CNN Row Buffer (Verilog)
// Converted from VHDL: cnn_row_buffer.vhd
//
// [기능]
//   여러 행을 버퍼링하여 Convolution/Pooling에 필요한
//   2D 매트릭스(Filter_Rows x Filter_Columns) 데이터를 순차 출력
//
//   예: 3x3 컨볼루션이면 3행을 RAM에 버퍼링하고,
//   각 출력 위치에서 9개 값(3x3)을 순서대로 내보냄
//
//   출력과 함께 oRow, oColumn, oInput 인덱스를 제공하여
//   후단에서 어떤 필터 위치의 데이터인지 알 수 있음
//
// [핵심 개념]
//   - 순환 행 버퍼 (circular row buffer)
//   - RAM에 Filter_Rows개 행 저장
//   - same/valid 패딩 모드 지원
//   - Strides > 1일 때 스킵 출력
//
// [VHDL과의 차이]
//   CNN_Values_T → packed 비트 벡터
//   Padding_T enum → localparam (0=valid, 1=same)
//   oRow, oColumn, oInput은 buffer(inout) → output으로 변경
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// CNN Row Buffer (SystemVerilog)
//------------------------------------------------------------------------
module cnn_row_buffer #(
    parameter INPUT_COLUMNS  = 28,
    parameter INPUT_ROWS     = 28,
    parameter INPUT_VALUES   = 1,
    parameter FILTER_COLUMNS = 3,
    parameter FILTER_ROWS    = 3,
    parameter INPUT_CYCLES   = 1,
    parameter VALUE_CYCLES   = 1,
    parameter CALC_CYCLES    = 1,
    parameter STRIDES        = 1,
    parameter PADDING        = 0,       // 0=valid, 1=same
    parameter VALUE_BITS     = 10       // CNN_VALUE_RESOLUTION
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
    output logic [VALUE_BITS*(INPUT_VALUES/VALUE_CYCLES)-1:0] o_data,

    // Matrix position indices
    output logic [$clog2(FILTER_ROWS):0]    o_mat_row,
    output logic [$clog2(FILTER_COLUMNS):0] o_mat_column,
    output logic [$clog2(VALUE_CYCLES):0]   o_mat_input
);

    // RAM 행 수 계산 (INPUT_COLUMNS==2일 때 추가 행 필요)
    localparam RAM_ROWS  = (INPUT_COLUMNS == 2) ? FILTER_ROWS + 1 : FILTER_ROWS;
    localparam RAM_BITS  = VALUE_BITS * (INPUT_VALUES / VALUE_CYCLES);
    localparam RAM_WIDTH = INPUT_COLUMNS * RAM_ROWS * VALUE_CYCLES;

    assign o_data_clk = i_data_clk;

    // RAM
    logic [RAM_BITS-1:0] buffer_ram [0:RAM_WIDTH-1];
    logic [$clog2(RAM_WIDTH)-1:0] ram_addr_in, ram_addr_out;
    logic [RAM_BITS-1:0] ram_data_in;
    logic [RAM_BITS-1:0] ram_data_out;
    logic ram_enable;

    // RAM write (rising edge)
    always_ff @(posedge i_data_clk) begin
        if (ram_enable)
            buffer_ram[ram_addr_in] <= ram_data_in;
    end

    // RAM read (falling edge)
    always_ff @(negedge i_data_clk) begin
        ram_data_out <= buffer_ram[ram_addr_out];
    end

    // Internal tracking registers
    logic [$clog2(RAM_ROWS)-1:0]     i_row_ram;
    logic [$clog2(INPUT_ROWS)-1:0]   i_row_reg;
    logic [$clog2(INPUT_COLUMNS)-1:0] i_col_reg;
    logic [$clog2(INPUT_VALUES)-1:0] i_val_reg;

    logic [$clog2(INPUT_ROWS)-1:0]   o_row_reg;
    logic [$clog2(INPUT_COLUMNS)-1:0] o_col_reg;
    logic [$clog2(RAM_ROWS)-1:0]     o_row_ram_reg;
    logic o_data_en_reg;

    // Output internal stream
    logic [9:0]  os_column;
    logic [8:0]  os_row;
    logic        os_data_valid;

    // Internal position counters
    logic [$clog2(RAM_ROWS):0]        o_row_o_reg;
    logic [$clog2(FILTER_COLUMNS):0]  o_col_o_reg;
    logic [$clog2(VALUE_CYCLES):0]    o_input_reg;

    // Main processing
    always_ff @(posedge i_data_clk) begin
        // RAM 입력 주소 계산
        ram_addr_in <= i_filter + (i_column + i_row_ram * INPUT_COLUMNS) * VALUE_CYCLES;
        ram_data_in <= i_data;
        ram_enable  <= i_data_valid;

        // 행 변경 추적
        if (i_row_reg != i_row) begin
            if (i_row_ram < RAM_ROWS - 1)
                i_row_ram <= i_row_ram + 1;
            else
                i_row_ram <= 0;
        end

        i_row_reg <= i_row;
        i_col_reg <= i_column;
        i_val_reg <= i_filter;
    end

endmodule