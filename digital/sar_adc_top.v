`timescale 1ns / 1ps

// ========================================================
// [IP Module] 8-Bit SAR ADC Core 
// (기존 구조 변경 없음 - 완벽히 유지)
// ========================================================
module SAR_ADC_CORE (
    input wire clk,
    input wire sys_clr_n,
    input wire start,
    input wire comp_out,
    output wire ST1,
    output wire ST3,
    output wire dac0, dac1, dac2, dac3, dac4, dac5, dac6, dac7
);
    // 상태 머신 레지스터
    reg S1, S0;
    wire NS1, NS0;
    wire ST0, ST2;
    wire ST1_n;

    assign ST0 = ~S1 & ~S0;   // IDLE
    assign ST1 = ~S1 &  S0;   // SAMPLING
    assign ST2 =  S1 & ~S0;   // QUANTIZATION
    assign ST3 =  S1 &  S0;   // RESULT
    assign ST1_n = ~ST1;

    // 8클럭 카운터
    reg [3:0] cnt;
    wire TC8;

    always @(posedge clk or negedge sys_clr_n) begin
        if (!sys_clr_n) cnt <= 4'd0;
        else if (!ST2)  cnt <= 4'd0;
        else            cnt <= cnt + 1'b1;
    end
    assign TC8 = (cnt == 4'd7);

    // 다음 상태 결정 로직
    assign NS1 = ST1 | ST2;
    assign NS0 = (ST0 & start) | (ST2 & TC8) | ST3;

    always @(posedge clk or negedge sys_clr_n) begin
        if (!sys_clr_n) begin
            S1 <= 1'b0;
            S0 <= 1'b0;
        end else begin
            S1 <= NS1;
            S0 <= NS0;
        end
    end

    // 8비트 시프트 레지스터
    wire first_inject;
    reg [7:0] sr;
    assign first_inject = ST2 & (cnt == 4'd0);

    always @(negedge clk or negedge ST1_n) begin
        if (!ST1_n) sr <= 8'b0;
        else        sr <= {first_inject, sr[7:1]};
    end

    // SAR 출력 래치
    reg [7:0] out_q;
    integer i;
    always @(posedge clk or negedge ST1_n) begin
        if (!ST1_n) begin
            out_q <= 8'b0;
        end else begin
            for (i = 0; i < 8; i = i + 1) begin
                if (sr[i]) out_q[i] <= comp_out;
            end
        end
    end

    // DAC 출력 매핑
    wire [7:0] dac_vec = out_q | sr;
    assign {dac7, dac6, dac5, dac4, dac3, dac2, dac1, dac0} = dac_vec;
endmodule


// ========================================================
// [Top Module] Zybo Z7 Board Wrapper 
// (1kHz 정확한 분주 및 내부 정현파 S/H 스트리밍 로직 반영 완료)
// ========================================================
module sar_adc_top (
    input  wire sysclk,
    input  wire comp_out,
    output wire led_st3,
    output wire pmod_st1,
    output wire pmod_dac0, pmod_dac1, pmod_dac2, pmod_dac3,
    output wire pmod_dac4, pmod_dac5, pmod_dac6, pmod_dac7
);

    // 1. 내부 신호 선언
    // [수정] 1kHz 분주(125,000 분주)를 위해 카운터 비트 너비를 7비트에서 17비트로 확장
    reg [16:0] clk_div = 0;
    reg adc_clk = 0;
    reg internal_clr_n = 0;
    reg internal_start = 0;
    reg [15:0] timer = 0;

    wire actual_comp;
    wire final_start;
    wire [7:0] dac_vec;

    // VIO 제어용 와이어 (기존 선언 유지)
    wire vio_dbg_mode_sel;
    wire vio_comp_force;
    wire vio_start_force;

    // =========================================================
    // 2. [변경] 정확한 1kHz 클럭 생성기 (125MHz -> 1kHz)
    // 아날로그부가 감당할 수 있도록 메인 변환 주파수를 완전히 낮춥니다.
    // =========================================================

    `ifdef SIMULATION
        wire [16:0] max_div = 17'd5;      // 시뮬레이션 시 카운트 5에서 토글
    `else
        wire [16:0] max_div = 17'd62499; // 실제 보드에서는 1kHz (62500 분주)
    `endif

    always @(posedge sysclk) begin
        if (clk_div == max_div) begin
            clk_div <= 0;
            adc_clk <= ~adc_clk;
        end else begin
            clk_div <= clk_div + 1;
        end
    end

    // 3. 제어 신호 생성 (1kHz 기준으로 정밀 타이밍 제어)
    always @(posedge adc_clk) begin
        timer <= timer + 1;
        if (timer > 16'd10) internal_clr_n <= 1'b1;
        else                internal_clr_n <= 1'b0;
        
        // 1kHz 클럭 기준 64클럭(64ms)마다 자동으로 변환 시작 펄스 유도
        if (timer[5:0] == 6'd63) internal_start <= 1'b1;
        else                     internal_start <= 1'b0;
    end

    // =========================================================
    // [추가] 32-Point 가상 정현파 발생기 & S/H (Sample & Hold) 모사 로직
    // =========================================================
    reg [4:0] sine_idx = 0;
    reg [7:0] sine_val;

    // S/H 동작: 변환 시작 플래그(final_start)가 뜰 때마다 정현파 전압 값을 샘플링 후 고정
    always @(posedge final_start) begin
        sine_idx <= sine_idx + 1;
    end

    // 8비트 정현파 디지털 전압 테이블
    always @(*) begin
        case(sine_idx)
            5'd0:  sine_val = 8'd128; 5'd1:  sine_val = 8'd153; 5'd2:  sine_val = 8'd177; 5'd3:  sine_val = 8'd199;
            5'd4:  sine_val = 8'd218; 5'd5:  sine_val = 8'd233; 5'd6:  sine_val = 8'd244; 5'd7:  sine_val = 8'd251;
            5'd8:  sine_val = 8'd254; 5'd9:  sine_val = 8'd251; 5'd10: sine_val = 8'd244; 5'd11: sine_val = 8'd233;
            5'd12: sine_val = 8'd218; 5'd13: sine_val = 8'd199; 5'd14: sine_val = 8'd177; 5'd15: sine_val = 8'd153;
            5'd16: sine_val = 8'd128; 5'd17: sine_val = 8'd103; 5'd18: sine_val = 8'd79;  5'd19: sine_val = 8'd57;
            5'd20: sine_val = 8'd38;  5'd21: sine_val = 8'd23;  5'd22: sine_val = 8'd12;  5'd23: sine_val = 8'd5;
            5'd24: sine_val = 8'd2;   5'd25: sine_val = 8'd5;   5'd26: sine_val = 8'd12;  5'd27: sine_val = 8'd23;
            5'd28: sine_val = 8'd38;  5'd29: sine_val = 8'd57;  5'd30: sine_val = 8'd79;  5'd31: sine_val = 8'd103;
        endcase
    end

    // 가상 축차 비교 신호 생성 (S/H된 가상 전압 vs 현재 로직의 DAC 추정값)
    wire sim_comp = (sine_val >= dac_vec);

    // =========================================================
    // 4. [수정] MUX 제어선 할당 변경
    // 디버그 스트리밍 모드(vio_dbg_mode_sel=1)일 때는 내부 가상 정현파 비교 신호를 주입하고, 
    // 변환 시작 트리거는 64ms 주기의 하드웨어 내부 타이머로 강제 자동 구동시킵니다.
    // =========================================================
    assign actual_comp = vio_dbg_mode_sel ? sim_comp : comp_out;
    assign final_start = vio_dbg_mode_sel ? internal_start : internal_start; 

    // 5. SAR ADC CORE 인스턴스화 (1kHz 변환 클럭 인가)
    SAR_ADC_CORE adc_inst (
        .clk(adc_clk),                  // 1kHz 클럭 매핑
        .sys_clr_n(internal_clr_n),
        .start(final_start),
        .comp_out(actual_comp),
        .ST1(pmod_st1),
        .ST3(led_st3),
        .dac0(pmod_dac0), .dac1(pmod_dac1), .dac2(pmod_dac2), .dac3(pmod_dac3),
        .dac4(pmod_dac4), .dac5(pmod_dac5), .dac6(pmod_dac6), .dac7(pmod_dac7)
    );

    assign dac_vec = {pmod_dac7, pmod_dac6, pmod_dac5, pmod_dac4, pmod_dac3, pmod_dac2, pmod_dac1, pmod_dac0};

    // ---------------------------------------------------------
    // 6. 디버깅 IP (기존 포트 맵 매칭 구조 완벽 유지)
    // ---------------------------------------------------------
    `ifndef SIMULATION
        vio_0 u_vio (
          .clk(sysclk),                     // 고속 통신 안정성을 위해 기존대로 125MHz 유지
          .probe_in0(dac_vec),             
          .probe_out0(vio_dbg_mode_sel),   
          .probe_out1(vio_comp_force),     // 자동 스트리밍 모드 시 사용되진 않으나 IP 매칭 보존
          .probe_out2(vio_start_force)     
        );

        ila_0 u_ila (
          .clk(adc_clk),                    // 로직 상태 관찰용 1kHz 매핑
          .probe0(actual_comp),            
          .probe1(dac_vec),                
          .probe2(pmod_st1),               
          .probe3(led_st3),                
          .probe4(final_start)             
        );
    `else
        assign vio_dbg_mode_sel = 1'b0;
        assign vio_comp_force   = 1'b0;
        assign vio_start_force  = 1'b0;
    `endif

endmodule