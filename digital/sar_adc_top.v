`timescale 1ns / 1ps // [cite: 1]

// ========================================================
// [IP Module] 8-Bit SAR ADC Core 
// ========================================================
module SAR_ADC_CORE (
    input wire clk,
    input wire sys_clr_n,
    input wire start,
    input wire comp_out,
    output wire ST1,
    output wire ST3,
    output wire dac0, dac1, dac2, dac3, dac4, dac5, dac6, dac7
); // [cite: 1]
    // 상태 머신 레지스터
    reg S1, S0; // [cite: 2]
    wire NS1, NS0;
    wire ST0, ST2;
    wire ST1_n; // [cite: 2]

    assign ST0 = ~S1 & ~S0;   // IDLE [cite: 3]
    assign ST1 = ~S1 &  S0;   // SAMPLING [cite: 3]
    assign ST2 =  S1 & ~S0;   // QUANTIZATION [cite: 4, 5]
    assign ST3 =  S1 &  S0;   // RESULT [cite: 5, 6]
    assign ST1_n = ~ST1; // [cite: 6]

    // 8클럭 카운터
    reg [3:0] cnt;
    wire TC8; // [cite: 6]

    always @(posedge clk or negedge sys_clr_n) begin // [cite: 7]
        if (!sys_clr_n) cnt <= 4'd0; // [cite: 7]
        else if (!ST2)  cnt <= 4'd0; // [cite: 8]
        else            cnt <= cnt + 1'b1; // [cite: 8]
    end // [cite: 9]
    assign TC8 = (cnt == 4'd7); // [cite: 9]

    // 다음 상태 결정 로직
    assign NS1 = ST1 | ST2; // [cite: 10]
    assign NS0 = (ST0 & start) | (ST2 & TC8) | ST3; // [cite: 11]

    always @(posedge clk or negedge sys_clr_n) begin // [cite: 12]
        if (!sys_clr_n) begin // [cite: 12]
            S1 <= 1'b0;
            S0 <= 1'b0; // [cite: 13]
        end else begin
            S1 <= NS1;
            S0 <= NS0; // [cite: 13, 14]
        end
    end // [cite: 14]

    // 8비트 시프트 레지스터
    wire first_inject; // [cite: 14]
    reg [7:0] sr; // [cite: 15]
    assign first_inject = ST2 & (cnt == 4'd0); // [cite: 15]

    always @(negedge clk or negedge ST1_n) begin // [cite: 16]
        if (!ST1_n) sr <= 8'b0; // [cite: 16]
        else        sr <= {first_inject, sr[7:1]}; // [cite: 17]
    end // [cite: 18]

    // SAR 출력 래치
    reg [7:0] out_q;
    integer i; // [cite: 18]

    always @(posedge clk or negedge ST1_n) begin // [cite: 19]
        if (!ST1_n) begin // [cite: 19]
            out_q <= 8'b0; // [cite: 19]
        end else begin // [cite: 20]
            for (i = 0; i < 8; i = i + 1) begin // [cite: 20]
                if (sr[i]) out_q[i] <= comp_out; // [cite: 20]
            end // [cite: 21]
        end
    end

    // DAC 출력 매핑
    wire [7:0] dac_vec = out_q | sr; // [cite: 21, 22]
    assign {dac7, dac6, dac5, dac4, dac3, dac2, dac1, dac0} = dac_vec; // [cite: 22]
endmodule // [cite: 23]


// ========================================================
// [Top Module] Zybo Z7 Board Wrapper 
// ========================================================
module sar_adc_top (
    input  wire sysclk,
    input  wire comp_out,
    output wire led_st3,
    output wire pmod_st1,
    output wire pmod_dac0, pmod_dac1, pmod_dac2, pmod_dac3,
    output wire pmod_dac4, pmod_dac5, pmod_dac6, pmod_dac7
); // [cite: 23]
    // 1. 내부 신호 선언
    reg [16:0] clk_div = 0;
    reg adc_clk = 0; // [cite: 24]
    reg internal_clr_n = 0;
    reg internal_start = 0;
    reg [15:0] timer = 0; // [cite: 25]

    wire actual_comp;
    wire final_start;
    wire [7:0] dac_vec; // [cite: 25]

    // VIO 제어용 와이어
    wire vio_dbg_mode_sel;
    wire vio_comp_force;
    wire vio_start_force; // [cite: 26]

    // =========================================================
    // 2. 정확한 1kHz 클럭 생성기 (125MHz -> 1kHz)
    // =========================================================
    `ifdef SIMULATION
        wire [16:0] max_div = 17'd5; // 시뮬레이션 환경 고속 구동 [cite: 27]
    `else
        wire [16:0] max_div = 17'd62499; // 실제 보드 1kHz (62500 분주) [cite: 28]
    `endif

    always @(posedge sysclk) begin // [cite: 29]
        if (clk_div == max_div) begin // [cite: 29]
            clk_div <= 0;
            adc_clk <= ~adc_clk; // [cite: 30]
        end else begin
            clk_div <= clk_div + 1; // [cite: 30]
        end // [cite: 31]
    end

    // 3. 제어 신호 생성 (1kHz 기준으로 정밀 타이밍 제어)
    always @(posedge adc_clk) begin // [cite: 31]
        timer <= timer + 1; // [cite: 31]
        if (timer > 16'd10) internal_clr_n <= 1'b1; // [cite: 32]
        else                internal_clr_n <= 1'b0; // [cite: 32]
        
        // 1kHz 클럭 기준 64클럭(64ms)마다 자동으로 변환 시작 펄스 유도
        if (timer[5:0] == 6'd63) internal_start <= 1'b1; // [cite: 33]
        else                     internal_start <= 1'b0; // [cite: 34]
    end // [cite: 35]

    // =========================================================
    // 4. [수정 완료] 32-Point 가상 정현파 발생기 & 안정화된 S/H 로직
    // =========================================================
    reg [4:0] sine_idx = 0; // [cite: 35]
    reg [7:0] sine_val; // [cite: 36]

    // Race Condition 방지를 위해 변환이 완전히 종료된 시점(led_st3 상승 엣지)에만 인덱스 증가
    always @(posedge led_st3) begin // [cite: 36]
        sine_idx <= sine_idx + 1; // [cite: 36]
    end // [cite: 37]

    // 8비트 정현파 디지털 전압 테이블
    always @(*) begin // [cite: 37]
        case(sine_idx)
            5'd0:  sine_val = 8'd128; // [cite: 37]
            5'd1:  sine_val = 8'd153; 5'd2:  sine_val = 8'd177; 5'd3:  sine_val = 8'd199; // [cite: 38]
            5'd4:  sine_val = 8'd218; // [cite: 38]
            5'd5:  sine_val = 8'd233; 5'd6:  sine_val = 8'd244; 5'd7:  sine_val = 8'd251; // [cite: 39]
            5'd8:  sine_val = 8'd254; // [cite: 39]
            5'd9:  sine_val = 8'd251; 5'd10: sine_val = 8'd244; 5'd11: sine_val = 8'd233; // [cite: 40]
            5'd12: sine_val = 8'd218; // [cite: 40]
            5'd13: sine_val = 8'd199; 5'd14: sine_val = 8'd177; 5'd15: sine_val = 8'd153; // [cite: 41]
            5'd16: sine_val = 8'd128; 5'd17: sine_val = 8'd103; // [cite: 41]
            5'd18: sine_val = 8'd79;  5'd19: sine_val = 8'd57; // [cite: 42]
            5'd20: sine_val = 8'd38;  5'd21: sine_val = 8'd23;  5'd22: sine_val = 8'd12; // [cite: 42]
            5'd23: sine_val = 8'd5; // [cite: 43]
            5'd24: sine_val = 8'd2;   5'd25: sine_val = 8'd5;   5'd26: sine_val = 8'd12;  5'd27: sine_val = 8'd23; // [cite: 43]
            5'd28: sine_val = 8'd38;  5'd29: sine_val = 8'd57;  5'd30: sine_val = 8'd79;  5'd31: sine_val = 8'd103; // [cite: 44]
        endcase // [cite: 45]
    end

    // 가상 축차 비교 신호 생성 (S/H된 가상 전압 vs 현재 로직의 DAC 추정값)
    wire sim_comp = (sine_val >= dac_vec); // [cite: 45]

    // =========================================================
    // 5. MUX 및 상태 클리어 제어선 최적화
    // =========================================================
    assign actual_comp = vio_dbg_mode_sel ? sim_comp : comp_out; // [cite: 46, 47]
    assign final_start = internal_start; // [cite: 47]

    // =========================================================
    // 6. SAR ADC CORE 인스턴스화
    // =========================================================
    SAR_ADC_CORE adc_inst (
        .clk(adc_clk),                  
        .sys_clr_n(internal_clr_n),
        .start(final_start),
        .comp_out(actual_comp),
        .ST1(pmod_st1),
        .ST3(led_st3),
        .dac0(pmod_dac0), .dac1(pmod_dac1), .dac2(pmod_dac2), .dac3(pmod_dac3),
        .dac4(pmod_dac4), .dac5(pmod_dac5), .dac6(pmod_dac6), .dac7(pmod_dac7)
    ); // [cite: 48, 49]

    assign dac_vec = {pmod_dac7, pmod_dac6, pmod_dac5, pmod_dac4, pmod_dac3, pmod_dac2, pmod_dac1, pmod_dac0}; // [cite: 49]

    // =========================================================
    // 7. 디버깅 IP 모듈 (Tcl 스크립트와 포트 100% 매칭 완료)
    // =========================================================
    `ifndef SIMULATION
        vio_0 u_vio (
            .clk(sysclk),
            .probe_in0(dac_vec),             // 8-bit DAC Vector [cite: 50]
            .probe_in1(pmod_st1),            // 1-bit ST1 (Sampling Phase 주석 깨짐 정돈 완료) [cite: 50, 51]
            .probe_in2(led_st3),             // 1-bit ST3 (Result Valid Phase) [cite: 51]
            .probe_out0(vio_dbg_mode_sel),   
            .probe_out1(vio_comp_force),     
            .probe_out2(vio_start_force)     // [cite: 51]
        );

        ila_0 u_ila (
            .clk(adc_clk),                  // [cite: 52]
            .probe0(actual_comp),            
            .probe1(dac_vec),                
            .probe2(pmod_st1),    // [cite: 52]
            .probe3(led_st3),                // [cite: 53]
            .probe4(final_start)             // [cite: 53]
        ); // [cite: 54]
    `else
        assign vio_dbg_mode_sel = 1'b0; // [cite: 54]
        assign vio_comp_force   = 1'b0;
        assign vio_start_force  = 1'b0; // [cite: 55]
    `endif

endmodule // [cite: 55]