//------------------------------------------------------------------------
// CNN Result AXI-Lite Register (SystemVerilog)
// Converted from VHDL: cnn_result_axilite.vhd
//
// [레지스터 맵 (Register Map)]
//   0x00: Prediction  (인식된 숫자, 0~9)
//   0x04: Probability (신뢰도, 0~1023)
//   0x08: Status      (항상 1로 고정, 디버깅용)
//------------------------------------------------------------------------
module cnn_result_axilite (
    // CNN Result Inputs (From Argmax)
    input  logic [3:0]  prediction,   // 0 ~ 9
    input  logic [9:0]  probability,  // 0 ~ 1023

    // AXI-Lite Slave Interface (To Zynq PS)
    input  logic        S_AXI_ACLK,
    input  logic        S_AXI_ARESETN,

    // Read Address Channel
    input  logic [3:0]  S_AXI_ARADDR,
    input  logic        S_AXI_ARVALID,
    output logic        S_AXI_ARREADY,
    // Read Data Channel
    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  logic        S_AXI_RREADY,

    // Write Address Channel (Dummy - Read Only)
    input  logic [3:0]  S_AXI_AWADDR,
    input  logic        S_AXI_AWVALID,
    output logic        S_AXI_AWREADY,
    // Write Data Channel (Dummy - Read Only)
    input  logic [31:0] S_AXI_WDATA,
    input  logic [3:0]  S_AXI_WSTRB,
    input  logic        S_AXI_WVALID,
    output logic        S_AXI_WREADY,
    // Write Response Channel (Dummy - Read Only)
    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  logic        S_AXI_BREADY
);

    // 내부 레지스터
    logic [3:0]  pred_sync;
    logic [9:0]  prob_sync;
    
    logic        arready_reg;
    logic        rvalid_reg;
    logic [31:0] rdata_reg;

    logic        awready_reg;
    logic        wready_reg;
    logic        bvalid_reg;

    // 출력 할당
    assign S_AXI_ARREADY = arready_reg;
    assign S_AXI_RVALID  = rvalid_reg;
    assign S_AXI_RDATA   = rdata_reg;
    assign S_AXI_RRESP   = 2'b00; // 항상 OKAY 응답

    assign S_AXI_AWREADY = awready_reg;
    assign S_AXI_WREADY  = wready_reg;
    assign S_AXI_BVALID  = bvalid_reg;
    assign S_AXI_BRESP   = 2'b00; // 항상 OKAY 응답

    // CNN 출력값 동기화 (클럭 도메인 안정화) [cite: 43-45]
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            pred_sync <= 0;
            prob_sync <= 0;
        end else begin
            pred_sync <= prediction;
            prob_sync <= probability;
        end
    end

    //------------------------------------------------------------------
    // AXI-Lite Read Logic (ARM 프로세서가 값을 읽어갈 때)
    //------------------------------------------------------------------
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            arready_reg <= 1'b0;
            rvalid_reg  <= 1'b0;
            rdata_reg   <= 32'd0;
        end else begin
            // 핸드셰이크 초기화
            arready_reg <= 1'b0;

            // 주소 수신 및 데이터 디코딩 [cite: 66-77]
            if (S_AXI_ARVALID && !arready_reg && !rvalid_reg) begin
                arready_reg <= 1'b1;

                case (S_AXI_ARADDR[3:2]) // 4바이트(32비트) 단위 주소 접근
                    2'b00: rdata_reg <= {28'd0, pred_sync}; // 0x00: Prediction
                    2'b01: rdata_reg <= {22'd0, prob_sync}; // 0x04: Probability
                    2'b10: rdata_reg <= 32'h00000001;       // 0x08: Status (Valid)
                    default: rdata_reg <= 32'd0;
                endcase
                
                rvalid_reg <= 1'b1;
            end

            // 데이터 전송 완료 처리
            if (rvalid_reg && S_AXI_RREADY) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------
    // AXI-Lite Write Logic (이 모듈은 Read-Only이므로 Write는 무시하고 OKAY만 응답)
    //------------------------------------------------------------------
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            awready_reg <= 1'b0;
            wready_reg  <= 1'b0;
            bvalid_reg  <= 1'b0;
        end else begin
            awready_reg <= 1'b0;
            wready_reg  <= 1'b0;

            // 주소 및 데이터 수신 승인 (빠르게 무시)
            if (S_AXI_AWVALID && !awready_reg && !bvalid_reg) begin
                awready_reg <= 1'b1;
            end
            if (S_AXI_WVALID && !wready_reg && !bvalid_reg) begin
                wready_reg <= 1'b1;
            end

            // 응답 완료 처리
            if (awready_reg && wready_reg && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
            end else if (bvalid_reg && S_AXI_BREADY) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

endmodule
