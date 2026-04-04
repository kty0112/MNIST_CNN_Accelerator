//------------------------------------------------------------------------
// CNN Result AXI-Lite Register (Verilog)
// Converted from VHDL: cnn_result_axilite.vhd
//
// [기능]
//   CNN의 Prediction(0~9)과 Probability(0~1023)를
//   Zynq PS(ARM)에서 읽을 수 있도록 AXI-Lite 슬레이브 인터페이스 제공
//
// [레지스터 맵]
//   0x00 : Prediction  (4-bit, read-only, 인식된 숫자 0~9)
//   0x04 : Probability (10-bit, read-only, 신뢰도 0~1023)
//   0x08 : Status      (bit0=result_valid, 항상 1)
//
// [VHDL과의 차이]
//   VHDL natural 타입 → Verilog 비트 벡터
//   동작은 동일: 읽기 전용 AXI-Lite 슬레이브
//------------------------------------------------------------------------
//------------------------------------------------------------------------
// CNN Result AXI-Lite Register (SystemVerilog)
//------------------------------------------------------------------------
module cnn_result_axilite (
    // CNN result inputs
    input  logic [3:0]  prediction,     // 0~9
    input  logic [9:0]  probability,    // 0~1023

    // AXI-Lite Slave interface
    input  logic        S_AXI_ACLK,
    input  logic        S_AXI_ARESETN,

    // Read address channel
    input  logic [3:0]  S_AXI_ARADDR,
    input  logic        S_AXI_ARVALID,
    output logic        S_AXI_ARREADY,

    // Read data channel
    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  logic        S_AXI_RREADY,

    // Write channels (unused, required for AXI-Lite)
    input  logic [3:0]  S_AXI_AWADDR,
    input  logic        S_AXI_AWVALID,
    output logic        S_AXI_AWREADY,
    input  logic [31:0] S_AXI_WDATA,
    input  logic [3:0]  S_AXI_WSTRB,
    input  logic        S_AXI_WVALID,
    output logic        S_AXI_WREADY,
    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  logic        S_AXI_BREADY
);

    logic arready_reg;
    logic [3:0] pred_sync;
    logic [9:0] prob_sync;

    // CNN 출력을 AXI 클럭 도메인으로 동기화
    always_ff @(posedge S_AXI_ACLK) begin
        pred_sync <= prediction;
        prob_sync <= probability;
    end

    // Write channel: 수락하고 무시 (읽기 전용 레지스터)
    assign S_AXI_AWREADY = 1'b1;
    assign S_AXI_WREADY  = 1'b1;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = S_AXI_AWVALID & S_AXI_WVALID;

    // Read channel
    assign S_AXI_ARREADY = arready_reg;
    assign S_AXI_RRESP   = 2'b00; // OKAY

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            arready_reg  <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= 32'd0;
        end else begin
            arready_reg <= 1'b0;
            // Read address handshake
            if (S_AXI_ARVALID && !arready_reg && !S_AXI_RVALID) begin
                arready_reg <= 1'b1;
                // 주소 디코딩
                case (S_AXI_ARADDR[3:2])
                    2'b00: S_AXI_RDATA <= {28'd0, pred_sync}; // 0x00: Prediction
                    2'b01: S_AXI_RDATA <= {22'd0, prob_sync}; // 0x04: Probability
                    2'b10: S_AXI_RDATA <= 32'h0000_0001;      // 0x08: Status
                    default: S_AXI_RDATA <= 32'd0;
                endcase

                S_AXI_RVALID <= 1'b1;
            end

            // Read data handshake 완료
            if (S_AXI_RVALID && S_AXI_RREADY)
                S_AXI_RVALID <= 1'b0;
        end
    end

endmodule